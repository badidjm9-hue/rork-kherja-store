-- 0027: profile RLS follows staff permissions; vehicle readers can see driver owners.
BEGIN;
INSERT INTO auth.users(id,email) VALUES
 ('eeeeeeee-0000-0000-0000-000000000034','driver0027@kherja.test'),
 ('eeeeeeee-0000-0000-0000-000000000035','passenger0027@kherja.test'),
 ('eeeeeeee-0000-0000-0000-000000000036','vehicleadmin0027@kherja.test');
-- Migration 0006 requires a verified phone for the passenger->driver role change.
INSERT INTO public.verified_phones(phone,user_id) VALUES ('+213550000034','eeeeeeee-0000-0000-0000-000000000034') ON CONFLICT DO NOTHING;
UPDATE public.profiles SET role='driver' WHERE id='eeeeeeee-0000-0000-0000-000000000034';
UPDATE public.profiles SET role='passenger' WHERE id='eeeeeeee-0000-0000-0000-000000000035';
INSERT INTO public.admin_users(user_id,role_code,display_name,email,active,custom_permissions_enabled)
VALUES ('eeeeeeee-0000-0000-0000-000000000036','support_agent','Vehicle Reader','vehicleadmin0027@kherja.test',true,true);
INSERT INTO public.admin_user_permissions(user_id,permission_code)
VALUES ('eeeeeeee-0000-0000-0000-000000000036','vehicles.read');

SELECT set_config('request.jwt.claim.sub','eeeeeeee-0000-0000-0000-000000000036',true);
SET LOCAL ROLE authenticated;
DO $$
DECLARE v_drivers integer; v_passengers integer;
BEGIN
  SELECT count(*) INTO v_drivers FROM public.profiles WHERE id='eeeeeeee-0000-0000-0000-000000000034';
  SELECT count(*) INTO v_passengers FROM public.profiles WHERE id='eeeeeeee-0000-0000-0000-000000000035';
  IF v_drivers <> 1 THEN RAISE EXCEPTION 'vehicles.read cannot see driver owner profiles'; END IF;
  IF v_passengers <> 0 THEN RAISE EXCEPTION 'vehicles.read can see passenger profiles without permission'; END IF;
  RAISE NOTICE 'PASS: vehicles.read can resolve driver owners without exposing passenger profiles';
END $$;
RESET ROLE;
ROLLBACK;
