-- 0025: delegated admin managers cannot assign privileges beyond their own.
DO $$
DECLARE
  v_super uuid := 'eeeeeeee-0000-0000-0000-000000000020';
  v_manager uuid := 'eeeeeeee-0000-0000-0000-000000000021';
  v_target uuid := 'eeeeeeee-0000-0000-0000-000000000022';
  v_new uuid := 'eeeeeeee-0000-0000-0000-000000000025';
  v_peer uuid := 'eeeeeeee-0000-0000-0000-000000000026';
  v_failed boolean := false;
BEGIN
  INSERT INTO auth.users(id,email) VALUES
    (v_new,'newstaff0025@kherja.test'),
    (v_peer,'superpeer0025@kherja.test');

  PERFORM set_config('request.jwt.claim.sub',v_super::text,false);
  PERFORM public.admin_set_admin('staff20020@kherja.test','pricing_manager',true,'Staff Two');
  PERFORM public.admin_set_user_permissions(v_target,ARRAY['pricing.read','pricing.manage']::text[],true);
  PERFORM public.admin_set_user_permissions(v_manager,
    ARRAY['admins.manage','support.read','overview.read','users.read','drivers.read','rides.read']::text[],true);

  PERFORM set_config('request.jwt.claim.sub',v_manager::text,false);
  -- The manager may preserve an existing elevated permission, but cannot create a new grant.
  PERFORM public.admin_set_user_permissions(v_target,ARRAY['pricing.manage','drivers.read']::text[],true);
  PERFORM set_config('request.jwt.claim.sub',v_target::text,false);
  IF NOT public.has_perm('pricing.manage') OR NOT public.has_perm('drivers.read') THEN
    RAISE EXCEPTION 'existing permission preservation or manager-held permission failed';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',v_manager::text,false);
  v_failed := false;
  BEGIN
    PERFORM public.admin_set_user_permissions('eeeeeeee-0000-0000-0000-000000000044',
      ARRAY['pricing.read','pricing.manage']::text[],true);
  EXCEPTION WHEN OTHERS THEN v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'manager granted a permission they do not hold to a new target'; END IF;

  v_failed := false;
  BEGIN
    PERFORM public.admin_set_admin('staff20020@kherja.test','financial_manager',true,'Staff Two');
  EXCEPTION WHEN OTHERS THEN v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'manager assigned a role with permissions they do not hold'; END IF;

  -- A role whose permissions are all held by the manager may be assigned safely.
  PERFORM public.admin_set_admin('staff20020@kherja.test','support_agent',true,'Staff Two');
  IF (SELECT custom_permissions_enabled FROM public.admin_users WHERE user_id=v_target) THEN
    RAISE EXCEPTION 'role change did not clear the previous custom permission set';
  END IF;

  -- New employee records start with custom mode enabled and no inherited role permissions.
  PERFORM public.admin_set_admin('newstaff0025@kherja.test','support_agent',true,'New Staff');
  IF NOT (SELECT custom_permissions_enabled FROM public.admin_users WHERE user_id=v_new) THEN
    RAISE EXCEPTION 'new employee was not created with custom permissions enabled';
  END IF;
  PERFORM set_config('request.jwt.claim.sub',v_new::text,false);
  IF public.has_perm('overview.read') THEN
    RAISE EXCEPTION 'new employee inherited role permissions before explicit selection';
  END IF;

  -- A super admin may invite/promote a peer super admin; that account receives every permission.
  PERFORM set_config('request.jwt.claim.sub',v_super::text,false);
  PERFORM public.admin_set_admin('superpeer0025@kherja.test','super_admin',true,'Peer Super');
  PERFORM set_config('request.jwt.claim.sub',v_peer::text,false);
  IF NOT public.has_perm('settings.manage') OR NOT public.has_perm('admins.manage') THEN
    RAISE EXCEPTION 'peer super admin did not receive full privileges';
  END IF;
  IF (SELECT count(*) FROM public.admin_permissions) <>
     (SELECT count(*) FROM public.admin_role_permissions WHERE role_code='super_admin') THEN
    RAISE EXCEPTION 'super admin role permission map is incomplete';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',v_manager::text,false);
  IF public.has_perm('finance.adjust') THEN RAISE EXCEPTION 'manager context unexpectedly has finance.adjust'; END IF;
  RAISE NOTICE 'PASS: delegated managers cannot escalate privileges; super admins retain full access; new employees start with zero permissions';
END $$;
