-- 0011: support tickets and SOS alerts (additive; NOT applied to any project; review on a disposable DB first).
-- Depends on 0002 (permissions, write_audit) and 0010 (app_settings).
-- Support contact shown in the apps is entered by admins in app_settings (support.phone / support.email); nothing is invented here.

-- ===== support tickets =====
CREATE TABLE IF NOT EXISTS public.support_tickets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  ride_id uuid REFERENCES public.rides(id),
  category text NOT NULL CHECK (category IN ('ride','payment','account','safety','other')),
  message text NOT NULL CHECK (char_length(message) BETWEEN 5 AND 1000),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','in_progress','resolved')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_support_user ON public.support_tickets (user_id, created_at DESC);
ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Own tickets read" ON public.support_tickets FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "Own tickets insert" ON public.support_tickets FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND status = 'open'
    AND (ride_id IS NULL OR EXISTS (SELECT 1 FROM public.rides r WHERE r.id = ride_id AND auth.uid() IN (r.passenger_id, r.driver_id))));

-- ===== SOS alerts (rate-limited: max 3 per 10 minutes) =====
CREATE TABLE IF NOT EXISTS public.sos_alerts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  ride_id uuid REFERENCES public.rides(id),
  lat double precision CHECK (lat BETWEEN -90 AND 90),
  lng double precision CHECK (lng BETWEEN -180 AND 180),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','acknowledged','resolved')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sos_status ON public.sos_alerts (status, created_at DESC);
ALTER TABLE public.sos_alerts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Own sos read" ON public.sos_alerts FOR SELECT TO authenticated USING (user_id = auth.uid());
-- Creation only through raise_sos() (validates ride membership, rate limit).

CREATE OR REPLACE FUNCTION public.raise_sos(p_ride_id uuid, p_lat double precision, p_lng double precision) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF p_ride_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM rides WHERE id = p_ride_id AND auth.uid() IN (passenger_id, driver_id)) THEN
    RAISE EXCEPTION 'RIDE_NOT_FOUND';
  END IF;
  IF (SELECT count(*) FROM sos_alerts WHERE user_id = auth.uid() AND created_at > now() - interval '10 minutes') >= 3 THEN
    RAISE EXCEPTION 'SOS_RATE_LIMIT';
  END IF;
  INSERT INTO sos_alerts (user_id, ride_id, lat, lng) VALUES (auth.uid(), p_ride_id, p_lat, p_lng) RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- ===== new admin permissions =====
INSERT INTO public.admin_permissions (code, description) VALUES
  ('support.read', 'Voir les demandes de support et alertes SOS'),
  ('support.manage', 'Traiter les demandes de support et alertes SOS')
ON CONFLICT (code) DO NOTHING;
INSERT INTO public.admin_role_permissions (role_code, permission_code)
SELECT 'super_admin', code FROM public.admin_permissions ON CONFLICT DO NOTHING;
INSERT INTO public.admin_role_permissions (role_code, permission_code) VALUES
  ('operations_manager','support.read'),('operations_manager','support.manage'),
  ('support_agent','support.read'),('support_agent','support.manage')
ON CONFLICT DO NOTHING;

CREATE POLICY "Staff read support" ON public.support_tickets FOR SELECT USING (public.has_perm('support.read'));
CREATE POLICY "Staff read sos" ON public.sos_alerts FOR SELECT USING (public.has_perm('support.read'));

CREATE OR REPLACE FUNCTION public.admin_set_ticket_status(p_id uuid, p_status text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_old text;
BEGIN
  PERFORM public.require_perm('support.manage');
  IF p_status NOT IN ('open','in_progress','resolved') THEN RAISE EXCEPTION 'Invalid status'; END IF;
  SELECT status INTO v_old FROM support_tickets WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ticket not found'; END IF;
  UPDATE support_tickets SET status = p_status WHERE id = p_id;
  PERFORM public.write_audit('support.' || p_status, 'support_ticket', p_id::text,
    jsonb_build_object('status', v_old), jsonb_build_object('status', p_status), NULL);
END $$;

CREATE OR REPLACE FUNCTION public.admin_set_sos_status(p_id uuid, p_status text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_old text;
BEGIN
  PERFORM public.require_perm('support.manage');
  IF p_status NOT IN ('acknowledged','resolved') THEN RAISE EXCEPTION 'Invalid status'; END IF;
  SELECT status INTO v_old FROM sos_alerts WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Alert not found'; END IF;
  UPDATE sos_alerts SET status = p_status WHERE id = p_id;
  PERFORM public.write_audit('sos.' || p_status, 'sos_alert', p_id::text,
    jsonb_build_object('status', v_old), jsonb_build_object('status', p_status), NULL);
END $$;


CREATE OR REPLACE FUNCTION public.get_support_contact() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN auth.uid() IS NULL THEN '{}'::jsonb ELSE jsonb_build_object(
    'phone', coalesce((SELECT value #>> '{}' FROM app_settings WHERE key = 'support.phone'), ''),
    'email', coalesce((SELECT value #>> '{}' FROM app_settings WHERE key = 'support.email'), '')) END
$$;

REVOKE ALL ON FUNCTION public.raise_sos(uuid, double precision, double precision), public.admin_set_ticket_status(uuid, text),
  public.admin_set_sos_status(uuid, text), public.get_support_contact() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.raise_sos(uuid, double precision, double precision), public.admin_set_ticket_status(uuid, text),
  public.admin_set_sos_status(uuid, text), public.get_support_contact() TO authenticated;
