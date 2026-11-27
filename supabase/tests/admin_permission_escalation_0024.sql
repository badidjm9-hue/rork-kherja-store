-- A custom admin manager may preserve an existing admins.manage grant but cannot grant it.
DO $$
DECLARE
  v_super uuid := 'eeeeeeee-0000-0000-0000-000000000020';
  v_staff uuid := 'eeeeeeee-0000-0000-0000-000000000021';
  v_staff2 uuid := 'eeeeeeee-0000-0000-0000-000000000022';
  v_staff3 uuid := 'eeeeeeee-0000-0000-0000-000000000044';
  v_failed boolean := false;
BEGIN
  INSERT INTO auth.users(id,email) VALUES(v_staff3,'staff30020@kherja.test');
  INSERT INTO public.admin_users(user_id,role_code,display_name,email,active)
  VALUES(v_staff3,'support_agent','Staff Three','staff30020@kherja.test',true);

  PERFORM set_config('request.jwt.claim.sub',v_super::text,false);
  PERFORM public.admin_set_user_permissions(v_staff,ARRAY['admins.manage','drivers.read','users.read']::text[],true);
  PERFORM public.admin_set_user_permissions(v_staff2,ARRAY['admins.manage','drivers.read']::text[],true);

  PERFORM set_config('request.jwt.claim.sub',v_staff::text,false);
  PERFORM public.admin_set_user_permissions(v_staff2,ARRAY['admins.manage','drivers.read','users.read']::text[],true);
  IF NOT public.has_perm('admins.manage') THEN RAISE EXCEPTION 'manager lost own admin-management permission'; END IF;

  v_failed := false;
  BEGIN
    PERFORM public.admin_set_user_permissions(v_staff3,ARRAY['admins.manage']::text[],true);
  EXCEPTION WHEN OTHERS THEN v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'non-super manager granted admins.manage to a new employee'; END IF;

  v_failed := false;
  BEGIN
    PERFORM public.admin_set_admin('staff30020@kherja.test','super_admin',true,'Staff Three');
  EXCEPTION WHEN OTHERS THEN v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'non-super manager promoted a new super admin'; END IF;
  RAISE NOTICE 'PASS: admin managers can preserve but cannot create elevated admin grants';
END $$;
