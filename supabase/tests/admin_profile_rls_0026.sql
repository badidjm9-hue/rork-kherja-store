-- 0026: admin employee profile reads are filtered by their effective permissions.
INSERT INTO auth.users(id,email) VALUES
 ('eeeeeeee-0000-0000-0000-000000000040','profile-admin@kherja.test'),
 ('eeeeeeee-0000-0000-0000-000000000041','profile-driver@kherja.test'),
 ('eeeeeeee-0000-0000-0000-000000000042','profile-passenger@kherja.test'),
 ('eeeeeeee-0000-0000-0000-000000000043','profile-normal@kherja.test')
ON CONFLICT(id) DO NOTHING;
-- Migration 0006 requires a verified phone for the passenger->driver role change.
INSERT INTO public.verified_phones(phone,user_id) VALUES ('+213550000041','eeeeeeee-0000-0000-0000-000000000041') ON CONFLICT DO NOTHING;
UPDATE public.profiles SET role='driver' WHERE id='eeeeeeee-0000-0000-0000-000000000041';
UPDATE public.profiles SET role='passenger' WHERE id='eeeeeeee-0000-0000-0000-000000000042';
INSERT INTO public.admin_users(user_id,role_code,display_name,email,active,custom_permissions_enabled)
VALUES('eeeeeeee-0000-0000-0000-000000000040','support_agent','Profile Admin','profile-admin@kherja.test',true,true)
ON CONFLICT(user_id) DO UPDATE SET active=true,custom_permissions_enabled=true;
INSERT INTO public.admin_user_permissions(user_id,permission_code,granted_by)
VALUES('eeeeeeee-0000-0000-0000-000000000040','drivers.read','eeeeeeee-0000-0000-0000-000000000020')
ON CONFLICT DO NOTHING;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','eeeeeeee-0000-0000-0000-000000000040',true);
DO $$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id='eeeeeeee-0000-0000-0000-000000000041') THEN
    RAISE EXCEPTION 'driver profile should be visible to drivers.read';
  END IF;
  IF EXISTS(SELECT 1 FROM public.profiles WHERE id='eeeeeeee-0000-0000-0000-000000000042') THEN
    RAISE EXCEPTION 'passenger profile leaked to an employee without users.read';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id='eeeeeeee-0000-0000-0000-000000000040') THEN
    RAISE EXCEPTION 'employee must be able to read own profile';
  END IF;
END $$;
COMMIT;

UPDATE public.admin_users SET active=false WHERE user_id='eeeeeeee-0000-0000-0000-000000000040';
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','eeeeeeee-0000-0000-0000-000000000040',true);
DO $$
BEGIN
  IF EXISTS(SELECT 1 FROM public.profiles WHERE id='eeeeeeee-0000-0000-0000-000000000041') THEN
    RAISE EXCEPTION 'deactivated employee retained access to other profiles';
  END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','eeeeeeee-0000-0000-0000-000000000043',true);
DO $$
BEGIN
  IF (SELECT count(*) FROM public.profiles WHERE id IN (
    'eeeeeeee-0000-0000-0000-000000000040',
    'eeeeeeee-0000-0000-0000-000000000041',
    'eeeeeeee-0000-0000-0000-000000000042'
  )) <> 3 THEN
    RAISE EXCEPTION 'ordinary app profile visibility changed unexpectedly';
  END IF;
END $$;
COMMIT;
DO $$ BEGIN
  RAISE NOTICE 'PASS: employee profile reads follow permissions, deactivated staff are restricted, normal app users remain compatible';
END $$;
