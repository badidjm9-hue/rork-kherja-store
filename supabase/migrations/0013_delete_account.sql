-- 0013_delete_account.sql
-- In-app account deletion (App Store guideline 5.1.1(v) / Google Play account-deletion policy).
--
-- Design: ride, wallet and message history must survive for the OTHER party (the driver's
-- earnings, the passenger's receipts, dispute evidence), and several of those tables reference
-- profiles without ON DELETE CASCADE. So the profile is ANONYMISED and closed (account_status =
-- 'deleted') instead of being hard-deleted, and every piece of personal data that is not needed
-- for those records is removed.
--
-- NOT done here (needs the auth-otp Edge Function, i.e. a deploy): removing the Supabase Auth
-- identity itself. Until that exists the phone number stays registered to the closed account.
-- Clients sign the user out as soon as the RPC succeeds and refuse any session whose profile is
-- 'deleted'.

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'profiles_account_status_check') THEN
    ALTER TABLE public.profiles DROP CONSTRAINT profiles_account_status_check;
  END IF;
  ALTER TABLE public.profiles ADD CONSTRAINT profiles_account_status_check
    CHECK (account_status IN ('active','suspended','deleted'));
END $$;

CREATE OR REPLACE FUNCTION public.delete_my_account() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v profiles;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  SELECT * INTO v FROM profiles WHERE id = v_uid FOR UPDATE;
  IF v.id IS NULL THEN RAISE EXCEPTION 'Profile not found'; END IF;
  IF v.account_status = 'deleted' THEN RETURN; END IF; -- idempotent

  -- Never abandon someone mid-trip.
  IF EXISTS (SELECT 1 FROM ride_requests WHERE passenger_id = v_uid AND status IN ('open','negotiating','accepted'))
     OR EXISTS (SELECT 1 FROM rides WHERE (passenger_id = v_uid OR driver_id = v_uid) AND status IN ('en_route','arrived','started'))
     OR EXISTS (SELECT 1 FROM delivery_orders WHERE (passenger_id = v_uid OR driver_id = v_uid) AND status IN ('open','accepted','picked_up'))
  THEN
    RAISE EXCEPTION 'active ride: finish or cancel your current request before deleting the account';
  END IF;

  -- Personal data that has no business value for anyone else.
  DELETE FROM saved_places WHERE user_id = v_uid;
  DELETE FROM notifications WHERE user_id = v_uid;
  DELETE FROM notification_prefs WHERE user_id = v_uid;
  DELETE FROM vehicles WHERE driver_id = v_uid;
  DELETE FROM driver_documents WHERE driver_id = v_uid;
  DELETE FROM verified_phones WHERE user_id = v_uid;
  UPDATE ride_requests SET status = 'cancelled' WHERE passenger_id = v_uid AND status IN ('open','negotiating');
  UPDATE offers SET status = 'declined' WHERE driver_id = v_uid AND status = 'pending';

  -- Anonymise the profile (runs as the function owner, so the protected-field trigger lets it through).
  UPDATE profiles SET
    name = 'Compte supprimé',
    phone = NULL,
    vehicle_make = NULL, vehicle_model = NULL, vehicle_plate = NULL, vehicle_color = NULL,
    is_online = false, current_lat = NULL, current_lng = NULL,
    account_status = 'deleted',
    status_reason = 'deleted_by_user'
  WHERE id = v_uid;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.delete_my_account() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;
