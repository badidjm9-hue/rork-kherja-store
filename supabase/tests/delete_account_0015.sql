-- Disposable PostgreSQL test for migration 0015 only.
SET client_min_messages = notice;
DO $$
DECLARE v_uid uuid := 'eeeeeeee-0000-0000-0000-000000000015';
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint c WHERE c.contype='f'
    AND c.conrelid='public.profiles'::regclass AND c.confrelid='auth.users'::regclass) THEN
    RAISE EXCEPTION 'profiles still cascades from auth.users';
  END IF;
  INSERT INTO auth.users(id,email) VALUES(v_uid,'u213555900015@phone.kherja.app');
  UPDATE public.profiles SET name='Delete Test', phone='0555900015' WHERE id=v_uid;
  INSERT INTO storage.objects(bucket_id,name,owner) VALUES('driver-documents',v_uid::text||'/license_test.jpg',v_uid);
  PERFORM set_config('request.jwt.claim.sub',v_uid::text,false);
  PERFORM public.delete_my_account();
  IF EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id='driver-documents' AND name LIKE v_uid::text||'/%') THEN
    RAISE EXCEPTION 'driver document objects were not removed';
  END IF;
  IF (SELECT account_status FROM public.profiles WHERE id=v_uid) <> 'deleted' THEN
    RAISE EXCEPTION 'profile was not anonymised';
  END IF;
  DELETE FROM auth.users WHERE id=v_uid;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=v_uid AND account_status='deleted') THEN
    RAISE EXCEPTION 'anonymised profile anchor was deleted with Auth identity';
  END IF;
  RAISE NOTICE 'PASS: migration 0015 preserves anonymised profile and retained history';
END $$;
