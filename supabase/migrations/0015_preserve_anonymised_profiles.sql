-- 0015_preserve_anonymised_profiles.sql
-- Preserve anonymised profile/history rows when the corresponding Supabase Auth identity is deleted.

DO $$
DECLARE v_constraint text;
BEGIN
  SELECT c.conname INTO v_constraint
  FROM pg_constraint c
  JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=ANY(c.conkey)
  WHERE c.contype='f' AND c.conrelid='public.profiles'::regclass
    AND c.confrelid='auth.users'::regclass AND a.attname='id'
  LIMIT 1;
  IF v_constraint IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.profiles DROP CONSTRAINT %I', v_constraint);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.delete_my_account() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_uid uuid := auth.uid(); v profiles;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  SELECT * INTO v FROM profiles WHERE id=v_uid FOR UPDATE;
  IF v.id IS NULL THEN RAISE EXCEPTION 'Profile not found'; END IF;
  IF v.account_status='deleted' THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM ride_requests WHERE passenger_id=v_uid AND status IN ('open','negotiating','accepted'))
     OR EXISTS (SELECT 1 FROM rides WHERE (passenger_id=v_uid OR driver_id=v_uid) AND status IN ('en_route','arrived','started'))
     OR EXISTS (SELECT 1 FROM delivery_orders WHERE (passenger_id=v_uid OR driver_id=v_uid) AND status IN ('open','accepted','picked_up'))
  THEN RAISE EXCEPTION 'active ride: finish or cancel your current request before deleting the account'; END IF;

  DELETE FROM saved_places WHERE user_id=v_uid;
  DELETE FROM notifications WHERE user_id=v_uid;
  DELETE FROM notification_prefs WHERE user_id=v_uid;
  DELETE FROM storage.objects WHERE bucket_id='driver-documents' AND name LIKE v_uid::text || '/%';
  DELETE FROM vehicles WHERE driver_id=v_uid;
  DELETE FROM driver_documents WHERE driver_id=v_uid;
  DELETE FROM verified_phones WHERE user_id=v_uid;
  UPDATE ride_requests SET status='cancelled' WHERE passenger_id=v_uid AND status IN ('open','negotiating');
  UPDATE offers SET status='declined' WHERE driver_id=v_uid AND status='pending';

  UPDATE profiles SET name='Compte supprimé', phone=NULL,
    vehicle_make=NULL, vehicle_model=NULL, vehicle_plate=NULL, vehicle_color=NULL,
    is_online=false, current_lat=NULL, current_lng=NULL,
    account_status='deleted', status_reason='deleted_by_user'
  WHERE id=v_uid;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.delete_my_account() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;
