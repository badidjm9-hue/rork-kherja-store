-- 0010_places_notifications_vehicles_reports.sql
-- Additive only. NOT applied to any project; review and test on a disposable project first.
-- Depends on 0001 (profiles, rides), 0002 (admin permissions, has_perm, write_audit),
-- 0003 (driver_documents), 0006 (require_phone_for_driver), 0008 (delivery_orders).
--
--  1. saved_places            passenger/driver favourite addresses (own rows only, max 20)
--  2. notifications           per-user inbox; rows are created by triggers / admin broadcast only
--     notification_prefs      per-user switches (rides / promotions)
--  3. vehicles                driver vehicles (car|moto), one primary, mirrored to profiles.vehicle_*
--  4. app_settings            key/value admin settings (staff only), audited
--  5. admin RPCs              vehicles, broadcasts, report summary, settings
--  6. ride_receipt()          participant-only receipt for a completed ride

-- ===================== permissions =====================
INSERT INTO public.admin_permissions (code, description) VALUES
  ('vehicles.read', 'Voir les véhicules'),
  ('vehicles.manage', 'Suspendre / réactiver des véhicules'),
  ('notifications.read', 'Voir les notifications envoyées'),
  ('notifications.manage', 'Envoyer des notifications'),
  ('reports.read', 'Voir les rapports'),
  ('settings.read', 'Voir les paramètres'),
  ('settings.manage', 'Modifier les paramètres')
ON CONFLICT (code) DO NOTHING;

INSERT INTO public.admin_role_permissions (role_code, permission_code)
SELECT 'super_admin', code FROM public.admin_permissions
ON CONFLICT DO NOTHING;
INSERT INTO public.admin_role_permissions (role_code, permission_code) VALUES
  ('operations_manager', 'vehicles.read'), ('operations_manager', 'vehicles.manage'),
  ('operations_manager', 'notifications.read'), ('operations_manager', 'notifications.manage'),
  ('operations_manager', 'reports.read'),
  ('support_agent', 'vehicles.read'), ('support_agent', 'notifications.read'),
  ('financial_manager', 'reports.read')
ON CONFLICT DO NOTHING;

-- ===================== saved_places =====================
CREATE TABLE IF NOT EXISTS public.saved_places (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  kind text NOT NULL DEFAULT 'favorite' CHECK (kind IN ('home','work','favorite')),
  label text NOT NULL CHECK (char_length(btrim(label)) BETWEEN 1 AND 60),
  address text NOT NULL CHECK (char_length(btrim(address)) BETWEEN 1 AND 200),
  lat double precision NOT NULL CHECK (lat BETWEEN -90 AND 90),
  lng double precision NOT NULL CHECK (lng BETWEEN -180 AND 180),
  created_at timestamptz NOT NULL DEFAULT now()
);
-- one home and one work per user
CREATE UNIQUE INDEX IF NOT EXISTS uq_saved_places_home_work
  ON public.saved_places (user_id, kind) WHERE kind IN ('home','work');
CREATE INDEX IF NOT EXISTS idx_saved_places_user ON public.saved_places (user_id, created_at DESC);

ALTER TABLE public.saved_places ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Own saved places read" ON public.saved_places;
DROP POLICY IF EXISTS "Own saved places insert" ON public.saved_places;
DROP POLICY IF EXISTS "Own saved places update" ON public.saved_places;
DROP POLICY IF EXISTS "Own saved places delete" ON public.saved_places;
CREATE POLICY "Own saved places read" ON public.saved_places FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "Own saved places insert" ON public.saved_places FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "Own saved places update" ON public.saved_places FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "Own saved places delete" ON public.saved_places FOR DELETE USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.limit_saved_places() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF (SELECT count(*) FROM public.saved_places WHERE user_id = NEW.user_id) >= 20 THEN
    RAISE EXCEPTION 'Too many saved places (max 20)' USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.limit_saved_places() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_limit_saved_places ON public.saved_places;
CREATE TRIGGER trg_limit_saved_places BEFORE INSERT ON public.saved_places
  FOR EACH ROW EXECUTE FUNCTION public.limit_saved_places();

-- ===================== notifications =====================
CREATE TABLE IF NOT EXISTS public.notification_broadcasts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  audience text NOT NULL CHECK (audience IN ('all','passengers','drivers')),
  kind text NOT NULL CHECK (kind IN ('system','promo')),
  title text NOT NULL,
  body text NOT NULL,
  recipients integer NOT NULL DEFAULT 0,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.notification_broadcasts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Staff read broadcasts" ON public.notification_broadcasts;
CREATE POLICY "Staff read broadcasts" ON public.notification_broadcasts FOR SELECT USING (public.has_perm('notifications.read'));

CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('ride','delivery','document','system','promo')),
  title text NOT NULL,
  body text NOT NULL DEFAULT '',
  data jsonb NOT NULL DEFAULT '{}'::jsonb,
  broadcast_id uuid REFERENCES public.notification_broadcasts(id) ON DELETE SET NULL,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON public.notifications (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON public.notifications (user_id) WHERE read_at IS NULL;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Own notifications read" ON public.notifications;
DROP POLICY IF EXISTS "Own notifications delete" ON public.notifications;
CREATE POLICY "Own notifications read" ON public.notifications FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "Own notifications delete" ON public.notifications FOR DELETE USING (user_id = auth.uid());
-- No INSERT/UPDATE policies: inserts come from SECURITY DEFINER code, read state via RPCs below.

CREATE TABLE IF NOT EXISTS public.notification_prefs (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  rides boolean NOT NULL DEFAULT true,
  promotions boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.notification_prefs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Own prefs read" ON public.notification_prefs;
DROP POLICY IF EXISTS "Own prefs insert" ON public.notification_prefs;
DROP POLICY IF EXISTS "Own prefs update" ON public.notification_prefs;
CREATE POLICY "Own prefs read" ON public.notification_prefs FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "Own prefs insert" ON public.notification_prefs FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "Own prefs update" ON public.notification_prefs FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- Internal helper: insert a notification honouring the user's switches. Not callable by clients.
CREATE OR REPLACE FUNCTION public.push_notification(
  p_user uuid, p_kind text, p_title text, p_body text, p_data jsonb DEFAULT '{}'::jsonb, p_broadcast uuid DEFAULT NULL
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_prefs public.notification_prefs;
BEGIN
  SELECT * INTO v_prefs FROM public.notification_prefs WHERE user_id = p_user;
  IF FOUND THEN
    IF p_kind IN ('ride','delivery') AND NOT v_prefs.rides THEN RETURN false; END IF;
    IF p_kind = 'promo' AND NOT v_prefs.promotions THEN RETURN false; END IF;
  END IF;
  INSERT INTO public.notifications (user_id, kind, title, body, data, broadcast_id)
  VALUES (p_user, p_kind, p_title, p_body, coalesce(p_data, '{}'::jsonb), p_broadcast);
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.push_notification(uuid, text, text, text, jsonb, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.mark_notification_read(p_id uuid) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  UPDATE public.notifications SET read_at = coalesce(read_at, now()) WHERE id = p_id AND user_id = auth.uid();
$$;
CREATE OR REPLACE FUNCTION public.mark_all_notifications_read() RETURNS integer
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  WITH u AS (UPDATE public.notifications SET read_at = now() WHERE user_id = auth.uid() AND read_at IS NULL RETURNING 1)
  SELECT count(*)::int FROM u;
$$;
CREATE OR REPLACE FUNCTION public.unread_notification_count() RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT count(*)::int FROM public.notifications WHERE user_id = auth.uid() AND read_at IS NULL;
$$;
REVOKE ALL ON FUNCTION public.mark_notification_read(uuid), public.mark_all_notifications_read(), public.unread_notification_count() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_notification_read(uuid), public.mark_all_notifications_read(), public.unread_notification_count() TO authenticated;

-- Ride events -> notifications (fr/ar by recipient language).
CREATE OR REPLACE FUNCTION public.notify_ride_event() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_lang text;
  v_to uuid;
  v_title text;
  v_body text;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NEW; END IF;
  IF NEW.status = 'en_route' THEN
    v_to := NEW.passenger_id;
  ELSIF NEW.status IN ('arrived','started','completed') THEN
    v_to := NEW.passenger_id;
  ELSIF NEW.status = 'cancelled' THEN
    v_to := NEW.driver_id;
  ELSE
    RETURN NEW;
  END IF;
  SELECT language INTO v_lang FROM public.profiles WHERE id = v_to;
  v_lang := coalesce(v_lang, 'fr');
  v_title := CASE NEW.status
    WHEN 'en_route'  THEN CASE WHEN v_lang = 'ar' THEN 'السائق في الطريق' ELSE 'Votre chauffeur est en route' END
    WHEN 'arrived'   THEN CASE WHEN v_lang = 'ar' THEN 'وصل السائق' ELSE 'Votre chauffeur est arrivé' END
    WHEN 'started'   THEN CASE WHEN v_lang = 'ar' THEN 'بدأت الرحلة' ELSE 'La course a commencé' END
    WHEN 'completed' THEN CASE WHEN v_lang = 'ar' THEN 'انتهت الرحلة' ELSE 'Course terminée' END
    ELSE CASE WHEN v_lang = 'ar' THEN 'أُلغيت الرحلة' ELSE 'Course annulée' END END;
  v_body := NEW.pickup_label || ' → ' || NEW.dest_label;
  PERFORM public.push_notification(v_to, 'ride', v_title, v_body, jsonb_build_object('ride_id', NEW.id, 'status', NEW.status));
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.notify_ride_event() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_notify_ride_event ON public.rides;
CREATE TRIGGER trg_notify_ride_event AFTER INSERT OR UPDATE OF status ON public.rides
  FOR EACH ROW EXECUTE FUNCTION public.notify_ride_event();

-- Document review -> notification for the driver.
CREATE OR REPLACE FUNCTION public.notify_document_review() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_lang text;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status NOT IN ('approved','rejected') THEN RETURN NEW; END IF;
  SELECT language INTO v_lang FROM public.profiles WHERE id = NEW.driver_id;
  PERFORM public.push_notification(
    NEW.driver_id, 'document',
    CASE WHEN NEW.status = 'approved'
      THEN CASE WHEN coalesce(v_lang,'fr') = 'ar' THEN 'تم قبول وثيقتك' ELSE 'Document validé' END
      ELSE CASE WHEN coalesce(v_lang,'fr') = 'ar' THEN 'تم رفض وثيقتك' ELSE 'Document refusé' END END,
    coalesce(NEW.reason, ''),
    jsonb_build_object('doc_type', NEW.doc_type, 'status', NEW.status));
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.notify_document_review() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_notify_document_review ON public.driver_documents;
CREATE TRIGGER trg_notify_document_review AFTER UPDATE OF status ON public.driver_documents
  FOR EACH ROW EXECUTE FUNCTION public.notify_document_review();

-- ===================== vehicles =====================
CREATE TABLE IF NOT EXISTS public.vehicles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  category text NOT NULL CHECK (category IN ('car','moto')),
  make text NOT NULL CHECK (char_length(btrim(make)) BETWEEN 1 AND 40),
  model text NOT NULL CHECK (char_length(btrim(model)) BETWEEN 1 AND 40),
  year integer CHECK (year BETWEEN 1990 AND 2100),
  plate text NOT NULL CHECK (char_length(btrim(plate)) BETWEEN 3 AND 20),
  color text NOT NULL DEFAULT '' CHECK (char_length(color) <= 30),
  seats integer NOT NULL DEFAULT 4 CHECK (seats BETWEEN 1 AND 8),
  is_primary boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended')),
  suspended_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_vehicles_primary ON public.vehicles (driver_id) WHERE is_primary;
CREATE UNIQUE INDEX IF NOT EXISTS uq_vehicles_plate ON public.vehicles (upper(regexp_replace(plate, '[\s-]', '', 'g')));
CREATE INDEX IF NOT EXISTS idx_vehicles_driver ON public.vehicles (driver_id);

ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Driver reads own vehicles" ON public.vehicles;
DROP POLICY IF EXISTS "Driver inserts own vehicles" ON public.vehicles;
DROP POLICY IF EXISTS "Driver updates own vehicles" ON public.vehicles;
DROP POLICY IF EXISTS "Driver deletes own vehicles" ON public.vehicles;
DROP POLICY IF EXISTS "Staff read vehicles" ON public.vehicles;
CREATE POLICY "Driver reads own vehicles" ON public.vehicles FOR SELECT USING (driver_id = auth.uid());
CREATE POLICY "Driver inserts own vehicles" ON public.vehicles FOR INSERT WITH CHECK (driver_id = auth.uid());
CREATE POLICY "Driver updates own vehicles" ON public.vehicles FOR UPDATE USING (driver_id = auth.uid()) WITH CHECK (driver_id = auth.uid());
CREATE POLICY "Driver deletes own vehicles" ON public.vehicles FOR DELETE USING (driver_id = auth.uid());
CREATE POLICY "Staff read vehicles" ON public.vehicles FOR SELECT USING (public.has_perm('vehicles.read'));

-- Drivers need a verified phone (0006) and cannot touch admin-owned fields.
DROP TRIGGER IF EXISTS trg_driver_phone_vehicles ON public.vehicles;
CREATE TRIGGER trg_driver_phone_vehicles BEFORE INSERT ON public.vehicles
  FOR EACH ROW EXECUTE FUNCTION public.require_phone_for_driver();

CREATE OR REPLACE FUNCTION public.vehicles_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  NEW.updated_at := now();
  IF TG_OP = 'INSERT' THEN
    IF (SELECT count(*) FROM public.vehicles WHERE driver_id = NEW.driver_id) >= 5 THEN
      RAISE EXCEPTION 'Too many vehicles (max 5)' USING ERRCODE = 'P0001';
    END IF;
    NEW.status := 'active';          -- clients cannot create pre-suspended/other states
    NEW.suspended_reason := NULL;
    -- first vehicle becomes primary
    IF NOT EXISTS (SELECT 1 FROM public.vehicles WHERE driver_id = NEW.driver_id) THEN NEW.is_primary := true; END IF;
  ELSIF auth.uid() IS NOT NULL AND auth.uid() = OLD.driver_id AND NOT public.has_perm('vehicles.manage') THEN
    -- the owner cannot change moderation fields or ownership
    NEW.status := OLD.status;
    NEW.suspended_reason := OLD.suspended_reason;
    NEW.driver_id := OLD.driver_id;
    IF NEW.status = 'suspended' AND NEW.is_primary AND NOT OLD.is_primary THEN
      RAISE EXCEPTION 'A suspended vehicle cannot be primary' USING ERRCODE = 'P0001';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.vehicles_guard() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_vehicles_guard ON public.vehicles;
CREATE TRIGGER trg_vehicles_guard BEFORE INSERT OR UPDATE ON public.vehicles
  FOR EACH ROW EXECUTE FUNCTION public.vehicles_guard();

-- Keep profiles.vehicle_* (used by existing ride screens) mirrored from the primary vehicle.
CREATE OR REPLACE FUNCTION public.vehicles_sync_profile() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_driver uuid := coalesce(NEW.driver_id, OLD.driver_id); v public.vehicles;
BEGIN
  SELECT * INTO v FROM public.vehicles WHERE driver_id = v_driver AND is_primary;
  IF FOUND THEN
    UPDATE public.profiles SET vehicle_make = v.make, vehicle_model = v.model, vehicle_plate = v.plate, vehicle_color = v.color
    WHERE id = v_driver;
  ELSE
    UPDATE public.profiles SET vehicle_make = NULL, vehicle_model = NULL, vehicle_plate = NULL, vehicle_color = NULL
    WHERE id = v_driver;
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.vehicles_sync_profile() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_vehicles_sync ON public.vehicles;
CREATE TRIGGER trg_vehicles_sync AFTER INSERT OR UPDATE OR DELETE ON public.vehicles
  FOR EACH ROW EXECUTE FUNCTION public.vehicles_sync_profile();

-- Atomically make one of my vehicles primary.
CREATE OR REPLACE FUNCTION public.set_primary_vehicle(p_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v public.vehicles;
BEGIN
  SELECT * INTO v FROM public.vehicles WHERE id = p_id AND driver_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Vehicle not found'; END IF;
  IF v.status <> 'active' THEN RAISE EXCEPTION 'Vehicle suspended'; END IF;
  UPDATE public.vehicles SET is_primary = false WHERE driver_id = auth.uid() AND is_primary AND id <> p_id;
  UPDATE public.vehicles SET is_primary = true WHERE id = p_id;
END;
$$;
REVOKE ALL ON FUNCTION public.set_primary_vehicle(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_primary_vehicle(uuid) TO authenticated;

-- Staff: suspend / reactivate with reason, audited.
CREATE OR REPLACE FUNCTION public.admin_set_vehicle_status(p_id uuid, p_status text, p_reason text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_before public.vehicles; v_after public.vehicles;
BEGIN
  PERFORM public.require_perm('vehicles.manage');
  IF p_status NOT IN ('active','suspended') THEN RAISE EXCEPTION 'Invalid status'; END IF;
  IF p_status = 'suspended' AND coalesce(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'Reason required'; END IF;
  SELECT * INTO v_before FROM public.vehicles WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vehicle not found'; END IF;
  UPDATE public.vehicles
     SET status = p_status,
         suspended_reason = CASE WHEN p_status = 'suspended' THEN btrim(p_reason) ELSE NULL END,
         is_primary = CASE WHEN p_status = 'suspended' THEN false ELSE is_primary END
   WHERE id = p_id RETURNING * INTO v_after;
  PERFORM public.write_audit('vehicle.' || p_status, 'vehicle', p_id::text, to_jsonb(v_before), to_jsonb(v_after), p_reason);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_set_vehicle_status(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_vehicle_status(uuid, text, text) TO authenticated;

-- ===================== admin: broadcasts =====================
CREATE OR REPLACE FUNCTION public.admin_send_broadcast(p_audience text, p_kind text, p_title text, p_body text) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id uuid; v_n integer := 0; r record;
BEGIN
  PERFORM public.require_perm('notifications.manage');
  IF p_audience NOT IN ('all','passengers','drivers') THEN RAISE EXCEPTION 'Invalid audience'; END IF;
  IF p_kind NOT IN ('system','promo') THEN RAISE EXCEPTION 'Invalid kind'; END IF;
  IF char_length(btrim(coalesce(p_title,''))) NOT BETWEEN 1 AND 80 THEN RAISE EXCEPTION 'Invalid title'; END IF;
  IF char_length(btrim(coalesce(p_body,''))) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Invalid body'; END IF;
  INSERT INTO public.notification_broadcasts (audience, kind, title, body, created_by)
  VALUES (p_audience, p_kind, btrim(p_title), btrim(p_body), auth.uid()) RETURNING id INTO v_id;
  FOR r IN
    SELECT id FROM public.profiles
     WHERE p_audience = 'all' OR (p_audience = 'passengers' AND role = 'passenger') OR (p_audience = 'drivers' AND role = 'driver')
  LOOP
    IF public.push_notification(r.id, p_kind, btrim(p_title), btrim(p_body), '{}'::jsonb, v_id) THEN v_n := v_n + 1; END IF;
  END LOOP;
  UPDATE public.notification_broadcasts SET recipients = v_n WHERE id = v_id;
  PERFORM public.write_audit('notification.broadcast', 'broadcast', v_id::text, NULL,
    jsonb_build_object('audience', p_audience, 'kind', p_kind, 'title', btrim(p_title), 'recipients', v_n), NULL);
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_send_broadcast(text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_send_broadcast(text, text, text, text) TO authenticated;

-- ===================== admin: settings =====================
CREATE TABLE IF NOT EXISTS public.app_settings (
  key text PRIMARY KEY CHECK (key ~ '^[a-z0-9_.]{1,60}$'),
  value jsonb NOT NULL,
  updated_by uuid REFERENCES auth.users(id),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Staff read settings" ON public.app_settings;
CREATE POLICY "Staff read settings" ON public.app_settings FOR SELECT USING (public.has_perm('settings.read'));
-- Writes only through admin_set_setting.

INSERT INTO public.app_settings (key, value) VALUES
  ('support.phone', '""'::jsonb),
  ('support.email', '""'::jsonb),
  ('ride.offer_ttl_minutes', '10'::jsonb),
  ('maintenance.banner', '""'::jsonb)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.admin_set_setting(p_key text, p_value jsonb) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_before jsonb;
BEGIN
  PERFORM public.require_perm('settings.manage');
  IF p_key NOT IN ('support.phone','support.email','ride.offer_ttl_minutes','maintenance.banner') THEN
    RAISE EXCEPTION 'Unknown setting';
  END IF;
  IF p_key = 'ride.offer_ttl_minutes' AND (jsonb_typeof(p_value) <> 'number' OR (p_value #>> '{}')::numeric NOT BETWEEN 1 AND 120) THEN
    RAISE EXCEPTION 'Invalid value';
  END IF;
  IF p_key <> 'ride.offer_ttl_minutes' AND (jsonb_typeof(p_value) <> 'string' OR char_length(p_value #>> '{}') > 300) THEN
    RAISE EXCEPTION 'Invalid value';
  END IF;
  SELECT value INTO v_before FROM public.app_settings WHERE key = p_key;
  INSERT INTO public.app_settings (key, value, updated_by, updated_at) VALUES (p_key, p_value, auth.uid(), now())
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_by = EXCLUDED.updated_by, updated_at = now();
  PERFORM public.write_audit('setting.update', 'setting', p_key, to_jsonb(v_before), p_value, NULL);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_set_setting(text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_setting(text, jsonb) TO authenticated;

-- ===================== admin: reports =====================
CREATE OR REPLACE FUNCTION public.admin_report_summary(p_from date, p_to date) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_from timestamptz; v_to timestamptz; v_out jsonb;
BEGIN
  PERFORM public.require_perm('reports.read');
  IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN RAISE EXCEPTION 'Invalid range'; END IF;
  IF p_to - p_from > 366 THEN RAISE EXCEPTION 'Range too large'; END IF;
  v_from := p_from::timestamptz;
  v_to := (p_to + 1)::timestamptz;
  SELECT jsonb_build_object(
    'rides_by_status', coalesce((SELECT jsonb_object_agg(status, n) FROM (
        SELECT status, count(*) n FROM public.rides WHERE created_at >= v_from AND created_at < v_to GROUP BY status) s), '{}'::jsonb),
    'rides_revenue', coalesce((SELECT sum(fare) FROM public.rides WHERE status = 'completed' AND created_at >= v_from AND created_at < v_to), 0),
    'rides_avg_fare', coalesce((SELECT round(avg(fare)) FROM public.rides WHERE status = 'completed' AND created_at >= v_from AND created_at < v_to), 0),
    'deliveries_by_status', coalesce((SELECT jsonb_object_agg(status, n) FROM (
        SELECT status, count(*) n FROM public.delivery_orders WHERE created_at >= v_from AND created_at < v_to GROUP BY status) s), '{}'::jsonb),
    'deliveries_revenue', coalesce((SELECT sum(delivery_fee) FROM public.delivery_orders WHERE status = 'delivered' AND created_at >= v_from AND created_at < v_to), 0),
    'new_passengers', (SELECT count(*) FROM public.profiles WHERE role = 'passenger' AND created_at >= v_from AND created_at < v_to),
    'new_drivers', (SELECT count(*) FROM public.profiles WHERE role = 'driver' AND created_at >= v_from AND created_at < v_to),
    'active_drivers', (SELECT count(DISTINCT driver_id) FROM public.rides WHERE created_at >= v_from AND created_at < v_to),
    'daily', coalesce((SELECT jsonb_agg(jsonb_build_object('day', d, 'rides', rides, 'revenue', revenue) ORDER BY d) FROM (
        SELECT g::date AS d,
               (SELECT count(*) FROM public.rides r WHERE r.created_at >= g AND r.created_at < g + interval '1 day') AS rides,
               (SELECT coalesce(sum(fare),0) FROM public.rides r WHERE r.status = 'completed' AND r.created_at >= g AND r.created_at < g + interval '1 day') AS revenue
          FROM generate_series(v_from, v_to - interval '1 day', interval '1 day') g) x), '[]'::jsonb),
    'top_drivers', coalesce((SELECT jsonb_agg(jsonb_build_object('driver_id', driver_id, 'name', name, 'trips', trips, 'revenue', revenue)) FROM (
        SELECT r.driver_id, p.name, count(*) trips, sum(r.fare) revenue
          FROM public.rides r JOIN public.profiles p ON p.id = r.driver_id
         WHERE r.status = 'completed' AND r.created_at >= v_from AND r.created_at < v_to
         GROUP BY r.driver_id, p.name ORDER BY count(*) DESC, sum(r.fare) DESC LIMIT 5) t), '[]'::jsonb)
  ) INTO v_out;
  RETURN v_out;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_report_summary(date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_report_summary(date, date) TO authenticated;

-- ===================== receipt =====================
CREATE OR REPLACE FUNCTION public.ride_receipt(p_ride uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE r public.rides; d public.profiles; v_dist numeric;
BEGIN
  SELECT * INTO r FROM public.rides WHERE id = p_ride AND (passenger_id = auth.uid() OR driver_id = auth.uid());
  IF NOT FOUND THEN RAISE EXCEPTION 'Receipt not found'; END IF;
  IF r.status <> 'completed' THEN RAISE EXCEPTION 'Receipt available after completion'; END IF;
  SELECT * INTO d FROM public.profiles WHERE id = r.driver_id;
  SELECT distance_km INTO v_dist FROM public.ride_requests WHERE id = r.request_id;
  RETURN jsonb_build_object(
    'ride_id', r.id,
    'reference', upper(substr(replace(r.id::text, '-', ''), 1, 8)),
    'status', r.status,
    'vehicle', r.vehicle,
    'fare', r.fare,
    'distance_km', v_dist,
    'pickup_label', r.pickup_label,
    'dest_label', r.dest_label,
    'created_at', r.created_at,
    'started_at', r.started_at,
    'completed_at', r.completed_at,
    'driver_name', d.name,
    'vehicle_make', d.vehicle_make,
    'vehicle_model', d.vehicle_model,
    'vehicle_plate', d.vehicle_plate,
    'payment', 'cash');
END;
$$;
REVOKE ALL ON FUNCTION public.ride_receipt(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ride_receipt(uuid) TO authenticated;

-- ===================== defence in depth =====================
-- Supabase grants table privileges to anon/authenticated by default; RLS alone already blocks these
-- writes, but revoking the privileges makes the intent explicit and fails loudly.
REVOKE INSERT, UPDATE ON public.notifications FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.notification_broadcasts FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.app_settings FROM anon, authenticated;
REVOKE ALL ON public.saved_places, public.notification_prefs, public.vehicles, public.notifications,
  public.notification_broadcasts, public.app_settings FROM anon;
