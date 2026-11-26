-- 0012: support/SOS notifications and serialized SOS rate limiting.
-- Additive only. NOT applied to any Supabase project.
-- Depends on 0010 (notifications/push_notification) and 0011 (support_tickets/sos_alerts).

-- Serialize concurrent SOS requests per authenticated user so the 3-per-10-minute
-- limit cannot be bypassed by simultaneous requests.
CREATE INDEX IF NOT EXISTS idx_sos_user_created
  ON public.sos_alerts (user_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.raise_sos(
  p_ride_id uuid,
  p_lat double precision,
  p_lng double precision
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  -- A transaction-scoped per-user lock closes the count/insert race.
  PERFORM pg_advisory_xact_lock(hashtextextended(v_user::text, 0));

  IF p_ride_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM rides
    WHERE id = p_ride_id AND v_user IN (passenger_id, driver_id)
  ) THEN
    RAISE EXCEPTION 'RIDE_NOT_FOUND';
  END IF;

  IF (
    SELECT count(*)
    FROM sos_alerts
    WHERE user_id = v_user
      AND created_at > now() - interval '10 minutes'
  ) >= 3 THEN
    RAISE EXCEPTION 'SOS_RATE_LIMIT';
  END IF;

  INSERT INTO sos_alerts (user_id, ride_id, lat, lng)
  VALUES (v_user, p_ride_id, p_lat, p_lng)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.raise_sos(uuid, double precision, double precision) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.raise_sos(uuid, double precision, double precision) TO authenticated;

-- Notify all active staff roles that can read support when a new ticket is created.
CREATE OR REPLACE FUNCTION public.notify_support_ticket_event()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_admin record;
  v_lang text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    FOR v_admin IN
      SELECT DISTINCT au.user_id, coalesce(p.language, 'fr') AS language
      FROM admin_users au
      JOIN admin_role_permissions rp
        ON rp.role_code = au.role_code AND rp.permission_code = 'support.read'
      JOIN profiles p ON p.id = au.user_id
      WHERE au.active
    LOOP
      PERFORM public.push_notification(
        v_admin.user_id,
        'system',
        CASE WHEN v_admin.language = 'ar' THEN 'طلب دعم جديد' ELSE 'Nouvelle demande de support' END,
        CASE WHEN v_admin.language = 'ar' THEN 'وصل طلب دعم جديد من أحد المستخدمين.' ELSE 'Une nouvelle demande de support a été reçue.' END,
        jsonb_build_object('entity_type', 'support_ticket', 'entity_id', NEW.id, 'event', 'created')
      );
    END LOOP;
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
    SELECT coalesce(language, 'fr') INTO v_lang
    FROM profiles WHERE id = NEW.user_id;

    PERFORM public.push_notification(
      NEW.user_id,
      'system',
      CASE WHEN v_lang = 'ar' THEN 'تحديث طلب الدعم' ELSE 'Mise à jour de votre demande' END,
      CASE
        WHEN NEW.status = 'in_progress' AND v_lang = 'ar' THEN 'طلبك قيد المعالجة من فريق الدعم.'
        WHEN NEW.status = 'resolved' AND v_lang = 'ar' THEN 'تمت معالجة طلب الدعم.'
        WHEN NEW.status = 'in_progress' THEN 'Votre demande est en cours de traitement.'
        WHEN NEW.status = 'resolved' THEN 'Votre demande a été résolue.'
        ELSE 'Le statut de votre demande a changé.'
      END,
      jsonb_build_object('entity_type', 'support_ticket', 'entity_id', NEW.id, 'event', 'status_changed', 'status', NEW.status)
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_support_ticket_notify_insert ON public.support_tickets;
CREATE TRIGGER trg_support_ticket_notify_insert
  AFTER INSERT ON public.support_tickets
  FOR EACH ROW EXECUTE FUNCTION public.notify_support_ticket_event();

DROP TRIGGER IF EXISTS trg_support_ticket_notify_status ON public.support_tickets;
CREATE TRIGGER trg_support_ticket_notify_status
  AFTER UPDATE OF status ON public.support_tickets
  FOR EACH ROW EXECUTE FUNCTION public.notify_support_ticket_event();

-- SOS alerts notify the same support staff; subsequent acknowledgement/resolution
-- is sent to the person who raised the alert.
CREATE OR REPLACE FUNCTION public.notify_sos_event()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_admin record;
  v_lang text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    FOR v_admin IN
      SELECT DISTINCT au.user_id, coalesce(p.language, 'fr') AS language
      FROM admin_users au
      JOIN admin_role_permissions rp
        ON rp.role_code = au.role_code AND rp.permission_code = 'support.read'
      JOIN profiles p ON p.id = au.user_id
      WHERE au.active
    LOOP
      PERFORM public.push_notification(
        v_admin.user_id,
        'system',
        CASE WHEN v_admin.language = 'ar' THEN 'تنبيه SOS جديد' ELSE 'Nouvelle alerte SOS' END,
        CASE WHEN v_admin.language = 'ar' THEN 'أرسل أحد المستخدمين تنبيه طوارئ.' ELSE 'Un utilisateur a envoyé une alerte d’urgence.' END,
        jsonb_build_object('entity_type', 'sos_alert', 'entity_id', NEW.id, 'event', 'created')
      );
    END LOOP;
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
    SELECT coalesce(language, 'fr') INTO v_lang
    FROM profiles WHERE id = NEW.user_id;

    PERFORM public.push_notification(
      NEW.user_id,
      'system',
      CASE WHEN v_lang = 'ar' THEN 'تحديث تنبيه SOS' ELSE 'Mise à jour de votre alerte SOS' END,
      CASE
        WHEN NEW.status = 'acknowledged' AND v_lang = 'ar' THEN 'تم استلام تنبيهك ويتولى فريق الدعم متابعته.'
        WHEN NEW.status = 'resolved' AND v_lang = 'ar' THEN 'تم إغلاق تنبيه الطوارئ.'
        WHEN NEW.status = 'acknowledged' THEN 'Votre alerte a été prise en charge par le support.'
        WHEN NEW.status = 'resolved' THEN 'Votre alerte SOS a été clôturée.'
        ELSE 'Le statut de votre alerte a changé.'
      END,
      jsonb_build_object('entity_type', 'sos_alert', 'entity_id', NEW.id, 'event', 'status_changed', 'status', NEW.status)
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sos_notify_insert ON public.sos_alerts;
CREATE TRIGGER trg_sos_notify_insert
  AFTER INSERT ON public.sos_alerts
  FOR EACH ROW EXECUTE FUNCTION public.notify_sos_event();

DROP TRIGGER IF EXISTS trg_sos_notify_status ON public.sos_alerts;
CREATE TRIGGER trg_sos_notify_status
  AFTER UPDATE OF status ON public.sos_alerts
  FOR EACH ROW EXECUTE FUNCTION public.notify_sos_event();

REVOKE ALL ON FUNCTION public.notify_support_ticket_event(), public.notify_sos_event() FROM PUBLIC, anon, authenticated;
