-- 0014_admin_deleted_account_guard.sql
-- Keep deleted accounts terminal: even privileged account-status RPC calls cannot reactivate them.
-- This is additive; historical migrations remain immutable.

CREATE OR REPLACE FUNCTION public.admin_set_account_status(p_user uuid, p_status text, p_reason text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_before profiles;
BEGIN
  SELECT * INTO v_before FROM profiles WHERE id = p_user FOR UPDATE;
  IF v_before.id IS NULL THEN RAISE EXCEPTION 'User not found'; END IF;
  PERFORM public.require_perm(CASE WHEN v_before.role = 'driver' THEN 'drivers.manage' ELSE 'users.manage' END);
  IF v_before.account_status = 'deleted' THEN RAISE EXCEPTION 'Deleted accounts cannot be reactivated'; END IF;
  IF p_status NOT IN ('active','suspended') THEN RAISE EXCEPTION 'Invalid status'; END IF;
  IF p_status = 'suspended' AND coalesce(trim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required'; END IF;
  UPDATE profiles SET account_status = p_status, status_reason = p_reason,
    is_online = CASE WHEN p_status = 'suspended' THEN false ELSE is_online END
  WHERE id = p_user;
  IF p_status = 'suspended' THEN
    UPDATE ride_requests SET status = 'cancelled' WHERE passenger_id = p_user AND status IN ('open','negotiating');
    UPDATE offers SET status = 'declined' WHERE driver_id = p_user AND status = 'pending';
  END IF;
  PERFORM public.write_audit('account.' || p_status, 'profile', p_user::text,
    jsonb_build_object('account_status', v_before.account_status), jsonb_build_object('account_status', p_status), p_reason);
END;
$$;
