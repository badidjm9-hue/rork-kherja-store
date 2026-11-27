-- Disposable PostgreSQL behavioural checks for push-device registration.
SET client_min_messages = notice;
DO $$
DECLARE
  u1 uuid := 'eeeeeeee-0000-0000-0000-000000000017';
  u2 uuid := 'eeeeeeee-0000-0000-0000-000000000018';
  token_value text := repeat('A',64);
  first_id uuid;
  second_id uuid;
BEGIN
  INSERT INTO auth.users(id,email) VALUES
    (u1,'u213555900017@phone.kherja.app'),
    (u2,'u213555900018@phone.kherja.app');
  PERFORM set_config('request.jwt.claim.sub',u1::text,false);
  first_id := public.register_push_device(token_value,'android','test-device');
  IF NOT EXISTS (SELECT 1 FROM public.push_devices WHERE id=first_id AND user_id=u1 AND platform='android') THEN
    RAISE EXCEPTION 'device token was not registered for user one';
  END IF;
  second_id := public.register_push_device(token_value,'ios','test-device');
  IF second_id <> first_id OR (SELECT user_id FROM public.push_devices WHERE id=first_id) <> u1 THEN
    RAISE EXCEPTION 'same-user upsert changed device ownership unexpectedly';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',u2::text,false);
  second_id := public.register_push_device(token_value,'ios','test-device');
  IF second_id <> first_id OR (SELECT user_id FROM public.push_devices WHERE id=first_id) <> u2 THEN
    RAISE EXCEPTION 'token did not transfer to the currently authenticated account';
  END IF;
  PERFORM public.unregister_push_device(token_value);
  IF EXISTS (SELECT 1 FROM public.push_devices WHERE token=token_value) THEN
    RAISE EXCEPTION 'owner could not unregister device';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',u1::text,false);
  PERFORM public.register_push_device(token_value,'android','test-device');
  UPDATE public.profiles SET account_status='deleted' WHERE id=u1;
  IF EXISTS (SELECT 1 FROM public.push_devices WHERE user_id=u1) THEN
    RAISE EXCEPTION 'deleted profile retained push tokens';
  END IF;
  RAISE NOTICE 'PASS: push token ownership, unregister and deleted-account cleanup';
END $$;
