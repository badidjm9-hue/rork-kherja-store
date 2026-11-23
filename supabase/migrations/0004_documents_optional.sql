-- Documents are not yet uploadable from the mobile apps: approval no longer
-- requires them (re-enable once the upload flow ships).
CREATE OR REPLACE FUNCTION public.admin_set_driver_status(p_user uuid, p_status text, p_reason text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_before profiles;
BEGIN
  PERFORM public.require_perm('drivers.approve');
  IF p_status NOT IN ('approved','rejected','pending') THEN RAISE EXCEPTION 'Invalid status'; END IF;
  SELECT * INTO v_before FROM profiles WHERE id = p_user FOR UPDATE;
  IF v_before.id IS NULL OR v_before.role <> 'driver' THEN RAISE EXCEPTION 'Driver not found'; END IF;
  IF p_status = 'rejected' AND coalesce(trim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required'; END IF;
  UPDATE profiles SET driver_status = p_status, status_reason = p_reason,
    is_online = CASE WHEN p_status = 'approved' THEN is_online ELSE false END
  WHERE id = p_user;
  PERFORM public.write_audit('driver.' || p_status, 'profile', p_user::text,
    jsonb_build_object('driver_status', v_before.driver_status), jsonb_build_object('driver_status', p_status), p_reason);
END;
$$;
