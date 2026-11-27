-- 0020: effective per-user permissions and super-admin invariants.
DO $$
DECLARE
  v_super uuid := 'eeeeeeee-0000-0000-0000-000000000020';
  v_staff uuid := 'eeeeeeee-0000-0000-0000-000000000021';
  v_staff2 uuid := 'eeeeeeee-0000-0000-0000-000000000022';
  v_me jsonb;
  v_failed boolean := false;
BEGIN
  INSERT INTO auth.users(id,email) VALUES
    (v_super,'super0020@kherja.test'),
    (v_staff,'staff0020@kherja.test'),
    (v_staff2,'staff20020@kherja.test');
  INSERT INTO public.admin_users(user_id,role_code,display_name,email,active) VALUES
    (v_super,'super_admin','Super Test','super0020@kherja.test',true),
    (v_staff,'support_agent','Staff Test','staff0020@kherja.test',true),
    (v_staff2,'support_agent','Staff Two','staff20020@kherja.test',true);

  PERFORM set_config('request.jwt.claim.sub',v_super::text,false);
  IF NOT public.has_perm('settings.manage') OR NOT public.has_perm('support.manage') OR NOT public.has_perm('deliveries.read') THEN
    RAISE EXCEPTION 'super admin does not have every registered permission';
  END IF;
  v_me := public.admin_me();
  IF jsonb_array_length(v_me->'permissions') <> (SELECT count(*) FROM public.admin_permissions) THEN
    RAISE EXCEPTION 'admin_me does not return the complete super-admin permission set';
  END IF;

  PERFORM public.admin_set_user_permissions(v_staff,ARRAY['drivers.read','pricing.read']::text[],true);
  PERFORM set_config('request.jwt.claim.sub',v_staff::text,false);
  IF NOT public.has_perm('drivers.read') OR NOT public.has_perm('pricing.read') THEN
    RAISE EXCEPTION 'custom permissions were not granted';
  END IF;
  IF public.has_perm('support.manage') OR public.has_perm('finance.adjust') OR public.has_perm('admins.manage') THEN
    RAISE EXCEPTION 'custom permissions leaked role permissions';
  END IF;
  v_me := public.admin_me();
  IF jsonb_array_length(v_me->'permissions') <> 2
     OR NOT (v_me->'permissions' @> '["drivers.read","pricing.read"]'::jsonb) THEN
    RAISE EXCEPTION 'admin_me does not return exact custom permissions';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',v_super::text,false);
  PERFORM public.admin_set_user_permissions(v_staff,ARRAY['admins.manage','drivers.read']::text[],true);
  PERFORM set_config('request.jwt.claim.sub',v_staff::text,false);
  v_failed := false;
  BEGIN
    PERFORM public.admin_set_user_permissions(v_staff2,ARRAY['admins.manage']::text[],true);
  EXCEPTION WHEN OTHERS THEN v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'non-super admin was able to grant admins.manage'; END IF;

  v_failed := false;
  BEGIN
    PERFORM public.admin_set_admin('staff20020@kherja.test','super_admin',true,'Staff Two');
  EXCEPTION WHEN OTHERS THEN v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'non-super admin was able to promote a super admin'; END IF;

  PERFORM set_config('request.jwt.claim.sub',v_super::text,false);
  PERFORM public.admin_set_user_permissions(v_staff,ARRAY['drivers.read']::text[],false);
  PERFORM set_config('request.jwt.claim.sub',v_staff::text,false);
  IF NOT public.has_perm('support.manage') THEN
    RAISE EXCEPTION 'disabling custom permissions did not restore role permissions';
  END IF;
  IF public.has_perm('pricing.manage') THEN
    RAISE EXCEPTION 'support role unexpectedly received pricing.manage';
  END IF;
  RAISE NOTICE 'PASS: custom permissions, exact overrides, role fallback, super-admin completeness and escalation guards';
END $$;

-- Changing an employee's role clears old custom overrides and restores role defaults.
DO $$
DECLARE v_super uuid := 'eeeeeeee-0000-0000-0000-000000000020';
        v_staff uuid := 'eeeeeeee-0000-0000-0000-000000000021';
BEGIN
  PERFORM set_config('request.jwt.claim.sub',v_super::text,false);
  PERFORM public.admin_set_user_permissions(v_staff,ARRAY['pricing.manage']::text[],true);
  PERFORM public.admin_set_admin('staff0020@kherja.test','operations_manager',true,'Staff Test');
  PERFORM set_config('request.jwt.claim.sub',v_staff::text,false);
  IF (SELECT custom_permissions_enabled FROM public.admin_users WHERE user_id=v_staff) THEN
    RAISE EXCEPTION 'role change did not disable custom permission mode';
  END IF;
  IF NOT public.has_perm('drivers.approve') OR public.has_perm('pricing.manage') THEN
    RAISE EXCEPTION 'role change did not restore the new role permission set';
  END IF;
  RAISE NOTICE 'PASS: changing an employee role clears custom overrides';
END $$;
