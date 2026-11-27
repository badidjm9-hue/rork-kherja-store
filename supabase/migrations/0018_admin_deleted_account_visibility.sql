-- 0018_admin_deleted_account_visibility.sql
-- Deleted profiles remain as historical FK anchors, not active customers or recipients.
-- Staff accounts are not counted as passengers/drivers and do not receive customer broadcasts.

CREATE OR REPLACE FUNCTION public.push_notification(
  p_user uuid, p_kind text, p_title text, p_body text, p_data jsonb DEFAULT '{}'::jsonb, p_broadcast uuid DEFAULT NULL
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_prefs public.notification_prefs;
BEGIN
  -- Deleted profiles remain as historical FK anchors but must not receive new notifications.
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user AND account_status <> 'deleted') THEN
    RETURN false;
  END IF;
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

CREATE OR REPLACE FUNCTION public.admin_overview(p_from timestamptz, p_to timestamptz) RETURNS jsonb
LANGUAGE plpgsql STABLE
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v jsonb;
BEGIN
  PERFORM public.require_perm('overview.read');
  SELECT jsonb_build_object(
    'passengers', (SELECT count(*) FROM profiles p WHERE p.role = 'passenger' AND p.account_status <> 'deleted' AND NOT EXISTS (SELECT 1 FROM admin_users a WHERE a.user_id = p.id)),
    'drivers', (SELECT count(*) FROM profiles p WHERE p.role = 'driver' AND p.account_status <> 'deleted' AND NOT EXISTS (SELECT 1 FROM admin_users a WHERE a.user_id = p.id)),
    'drivers_online', (SELECT count(*) FROM profiles p WHERE p.role = 'driver' AND p.account_status = 'active' AND p.is_online AND NOT EXISTS (SELECT 1 FROM admin_users a WHERE a.user_id = p.id)),
    'drivers_pending', (SELECT count(*) FROM profiles p WHERE p.role = 'driver' AND p.driver_status = 'pending' AND p.account_status <> 'deleted' AND NOT EXISTS (SELECT 1 FROM admin_users a WHERE a.user_id = p.id)),
    'suspended', (SELECT count(*) FROM profiles WHERE account_status = 'suspended'),
    'deleted', (SELECT count(*) FROM profiles WHERE account_status = 'deleted'),
    'open_requests', (SELECT count(*) FROM ride_requests WHERE status IN ('open','negotiating') AND expires_at > now()),
    'active_rides', (SELECT count(*) FROM rides WHERE status IN ('en_route','arrived','started')),
    'completed', (SELECT count(*) FROM rides WHERE status = 'completed' AND created_at BETWEEN p_from AND p_to),
    'cancelled', (SELECT count(*) FROM rides WHERE status = 'cancelled' AND created_at BETWEEN p_from AND p_to),
    'requests', (SELECT count(*) FROM ride_requests WHERE created_at BETWEEN p_from AND p_to),
    'gross', (SELECT coalesce(sum(fare), 0) FROM rides WHERE status = 'completed' AND completed_at BETWEEN p_from AND p_to),
    'commission', (SELECT coalesce(sum(commission), 0) FROM rides WHERE status = 'completed' AND completed_at BETWEEN p_from AND p_to),
    'driver_net', (SELECT coalesce(sum(driver_net), 0) FROM rides WHERE status = 'completed' AND completed_at BETWEEN p_from AND p_to),
    'refunds', (SELECT coalesce(sum(amount), 0) FROM transactions WHERE kind = 'refund' AND created_at BETWEEN p_from AND p_to),
    'avg_fare', (SELECT coalesce(round(avg(fare)), 0) FROM rides WHERE status = 'completed' AND completed_at BETWEEN p_from AND p_to),
    'by_vehicle', (SELECT coalesce(jsonb_object_agg(vehicle, n), '{}'::jsonb) FROM (
        SELECT vehicle, count(*) n FROM rides WHERE created_at BETWEEN p_from AND p_to GROUP BY vehicle) t),
    'series', (SELECT coalesce(jsonb_agg(jsonb_build_object('day', d, 'rides', coalesce(r.n, 0), 'gross', coalesce(r.g, 0), 'commission', coalesce(r.c, 0)) ORDER BY d), '[]'::jsonb)
      FROM generate_series(date_trunc('day', p_from AT TIME ZONE 'Africa/Algiers'), date_trunc('day', p_to AT TIME ZONE 'Africa/Algiers'), interval '1 day') AS gs(d)
      LEFT JOIN (
        SELECT date_trunc('day', completed_at AT TIME ZONE 'Africa/Algiers') AS dday, count(*) AS n, sum(fare) AS g, sum(commission) AS c
        FROM rides WHERE status = 'completed' AND completed_at BETWEEN p_from AND p_to GROUP BY 1
      ) r ON r.dday = gs.d)
  ) INTO v;
  RETURN v;
END;
$$;

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
    SELECT p.id FROM public.profiles p
     WHERE p.account_status <> 'deleted'
       AND NOT EXISTS (SELECT 1 FROM public.admin_users a WHERE a.user_id = p.id)
       AND (p_audience = 'all' OR (p_audience = 'passengers' AND p.role = 'passenger') OR (p_audience = 'drivers' AND p.role = 'driver'))
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
