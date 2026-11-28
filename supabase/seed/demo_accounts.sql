-- KHERJA demo accounts — TEST PROJECTS ONLY. Never run this against production.
--
-- No password is stored in this repository (it is public). Pass them at run time:
--
--   psql "$TEST_DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -v confirm=THIS_IS_A_TEST_PROJECT \
--     -v passenger_password="$DEMO_PASSENGER_PASSWORD" \
--     -v driver_password="$DEMO_DRIVER_PASSWORD" \
--     -f supabase/seed/demo_accounts.sql
--
-- Idempotent: running it again resets the two passwords and re-approves the demo driver.
-- Passwords: 8-72 characters with letters and digits (same rule as the auth-otp function).

BEGIN;

SELECT set_config('kherja.confirm', :'confirm', true),
       set_config('kherja.pw_passenger', :'passenger_password', true),
       set_config('kherja.pw_driver', :'driver_password', true) \g /dev/null

DO $$
DECLARE
  a record;
  v_id uuid;
BEGIN
  IF current_setting('kherja.confirm') <> 'THIS_IS_A_TEST_PROJECT' THEN
    RAISE EXCEPTION 'Refusing to seed demo accounts without confirm=THIS_IS_A_TEST_PROJECT';
  END IF;
  -- Second guard: a database that already has real users is not a disposable test project.
  IF (SELECT count(*) FROM auth.users
      WHERE email NOT IN ('u213500000001@phone.kherja.app', 'u213500000002@phone.kherja.app')) > 20 THEN
    RAISE EXCEPTION 'Refusing: this database has real-looking users';
  END IF;

  FOR a IN SELECT * FROM (VALUES
    ('+213500000001', 'u213500000001@phone.kherja.app', 'Demo Passager', 'passenger', current_setting('kherja.pw_passenger')),
    ('+213500000002', 'u213500000002@phone.kherja.app', 'Demo Chauffeur', 'driver', current_setting('kherja.pw_driver'))
  ) AS t(phone, email, name, role, pw)
  LOOP
    IF length(a.pw) < 8 OR a.pw !~ '[A-Za-z]' OR a.pw !~ '[0-9]' THEN
      RAISE EXCEPTION 'Weak password for %', a.role;
    END IF;
    SELECT id INTO v_id FROM auth.users WHERE email = a.email;
    IF v_id IS NULL THEN
      v_id := gen_random_uuid();
      INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
        confirmation_token, recovery_token, email_change, email_change_token_new)
      VALUES ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', a.email,
        extensions.crypt(a.pw, extensions.gen_salt('bf')), now(),
        '{"provider":"email","providers":["email"]}', jsonb_build_object('phone', a.phone, 'demo', true),
        now(), now(), '', '', '', '');
      INSERT INTO auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at)
      VALUES (v_id::text, v_id, jsonb_build_object('sub', v_id::text, 'email', a.email, 'email_verified', true),
        'email', now(), now());
    ELSE
      UPDATE auth.users SET encrypted_password = extensions.crypt(a.pw, extensions.gen_salt('bf')), updated_at = now()
      WHERE id = v_id;
    END IF;

    UPDATE public.profiles SET name = a.name, city = 'Alger', language = 'ar', role = a.role,
      driver_status = CASE WHEN a.role = 'driver' THEN 'approved' ELSE 'none' END,
      account_status = 'active'
    WHERE id = v_id;

    IF a.role = 'driver' AND NOT EXISTS (SELECT 1 FROM public.vehicles WHERE driver_id = v_id) THEN
      INSERT INTO public.vehicles (driver_id, category, make, model, year, plate, color, seats)
      VALUES (v_id, 'car', 'Demo', 'Berline', 2022, 'DEMO-016', 'Bleu', 4);
    END IF;
  END LOOP;
END $$;

COMMIT;
