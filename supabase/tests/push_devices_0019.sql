-- Disposable PostgreSQL behavioural checks for per-device APNs environments.
SET client_min_messages = notice;
DO $$
DECLARE
  v_uid uuid := 'eeeeeeee-0000-0000-0000-000000000019';
  v_token text := repeat('E',64);
  v_id uuid;
BEGIN
  INSERT INTO auth.users(id,email) VALUES(v_uid,'u213555900019@phone.kherja.app');
  PERFORM set_config('request.jwt.claim.sub',v_uid::text,false);
  v_id := public.register_push_device(v_token,'ios','ios-debug','development');
  IF NOT EXISTS (SELECT 1 FROM public.push_devices WHERE id=v_id AND environment='development') THEN
    RAISE EXCEPTION 'development APNs environment was not persisted';
  END IF;
  PERFORM public.register_push_device(v_token,'ios','ios-release','production');
  IF NOT EXISTS (SELECT 1 FROM public.push_devices WHERE id=v_id AND environment='production' AND device_id='ios-release') THEN
    RAISE EXCEPTION 'APNs environment was not updated on token re-registration';
  END IF;
  RAISE NOTICE 'PASS: APNs environment is stored and updated per device token';
END $$;
