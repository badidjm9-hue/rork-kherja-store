-- 0025: delegated admin managers cannot assign privileges beyond their own.
DO $$
DECLARE
  v_super uuid := 'eeeeeeee-0000-0000-0000-000000000020';
  v_manager uuid := 'eeeeeeee-0000-0000-0000-000000000021';
  v_target uuid := 'eeeeeeee-0000-0000-0000-000000000022';
  v_failed boolean := false;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',v_super::text,false);
  PERFORM public.admin_set_user_permissions(v_manager,ARRAY['admins.manage','support.read']::text[],true);
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
  PERFORM public.admin_set_admin('staff30020@kherja.test','financial_manager',true,'Staff Three');
  IF NOT (SELECT custom_permissions_enabled FROM public.admin_users WHERE user_id='eeeeeeee-0000-0000-0000-000000000024') THEN
    RAISE EXCEPTION 'new employee was not created with custom permissions enabled';
  END IF;
  IF public.has_perm('finance.adjust') THEN RAISE EXCEPTION 'manager context unexpectedly has finance.adjust'; END IF;
  RAISE NOTICE 'PASS: delegated managers cannot escalate permissions or assign elevated roles; new invitations start least-privilege';
END $$;
