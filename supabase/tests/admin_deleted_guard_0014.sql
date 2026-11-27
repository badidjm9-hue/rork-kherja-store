-- Verify migration 0014 prevents privileged Admin reactivation of deleted profiles.
SET client_min_messages = notice;
INSERT INTO auth.users(id,email) VALUES
 ('eeeeeeee-0000-0000-0000-000000000014','admin-guard@example.test'),
 ('eeeeeeee-0000-0000-0000-000000000024','deleted-user@example.test');
INSERT INTO public.admin_users(user_id,role_code,display_name,email)
 VALUES('eeeeeeee-0000-0000-0000-000000000014','super_admin','Guard Test Admin','admin-guard@example.test');
UPDATE public.profiles SET account_status='deleted',status_reason='deleted_by_user'
 WHERE id='eeeeeeee-0000-0000-0000-000000000024';

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','eeeeeeee-0000-0000-0000-000000000014',false);
SELECT t.fails(
  $$SELECT public.admin_set_account_status('eeeeeeee-0000-0000-0000-000000000024','active',NULL)$$,
  'Deleted accounts cannot be reactivated',
  'admin cannot reactivate a deleted account'
);
RESET ROLE;
SELECT t.eq(
  (SELECT account_status FROM public.profiles WHERE id='eeeeeeee-0000-0000-0000-000000000024'),
  'deleted',
  'deleted status remains terminal after blocked admin action'
);
