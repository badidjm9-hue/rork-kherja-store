-- Verify Android's default production environment and explicit iOS APNs environment.
SET client_min_messages = notice;
DO $$
DECLARE
  u uuid := 'eeeeeeee-0000-0000-0000-000000000019';
  android_id uuid;
  ios_id uuid;
BEGIN
  INSERT INTO auth.users(id,email) VALUES(u,'u213555900019@phone.kherja.app');
  PERFORM set_config('request.jwt.claim.sub',u::text,false);
  android_id := public.register_push_device(repeat('A',64),'android');
  ios_id := public.register_push_device(repeat('B',64),'ios',NULL,'development');
  IF (SELECT environment FROM public.push_devices WHERE id=android_id) <> 'production' THEN
    RAISE EXCEPTION 'Android default environment must be production';
  END IF;
  IF (SELECT environment FROM public.push_devices WHERE id=ios_id) <> 'development' THEN
    RAISE EXCEPTION 'iOS Debug environment was not stored';
  END IF;
  RAISE NOTICE 'PASS: APNs environment stored per device and Android defaults to production';
END $$;
