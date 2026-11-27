-- 0025: delegated admin managers cannot assign privileges beyond their own.
DO $$
DECLARE
  v_super uuid := 'eeeeeeee-0000-0000-0000-000000000020';
  v_manager uuid := 'eeeeeeee-0000-0000-0000-000000000021';
  v_target uuid := 'eeeeeeee-0000-0000-0000-000000000022';
  v_new uuid := 'eeeeeeee-0000-0000-0000-000000000025';
  v_failed boolean := false;
BEGIN
  INSERT INTO auth.users(id,email) VALUES(v_new,'newstaff0025@kherja.test');

  PERFORM set_config('request.jwt.claim.sub',v_super::text,false);
  PERFORM public.admin_set_admin('staff20020@kherja.test','pricing_manager',true,'Staff Two');
  PERFORM public.admin_set_user_permissions(v_manager,
    ARRAY['admins.manage','support.read','overview.read','users.read','drivers.read','rides.read']::text[],true);

  PERFORM set_config('request.jwt.claim.sub',v_manager::text,false);
  BEGIN
    PERFORM public.admin_set_user_permissions(v_target,ARRAY['pricing.manage']::text[],true);
  EXCEPTION WHEN OTHERS THEN v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'manager granted a permission they do not hold'; END IF;

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

  PERFORM set_config('request.jwt.claim.sub',v_manager::text,false);
  IF public.has_perm('finance.adjust') THEN RAISE EXCEPTION 'manager context unexpectedly has finance.adjust'; END IF;
  RAISE NOTICE 'PASS: delegated managers cannot escalate privileges, role changes are bounded, and new employees start with zero permissions';
END $$;
