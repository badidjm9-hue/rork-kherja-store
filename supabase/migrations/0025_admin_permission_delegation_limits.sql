-- 0025: delegated managers cannot grant permissions beyond their own.
CREATE OR REPLACE FUNCTION public.admin_set_admin(
  p_email text, p_role text, p_active boolean DEFAULT true, p_display_name text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_uid uuid; v_before public.admin_users; v_actor_super boolean;
BEGIN
  PERFORM public.require_perm('admins.manage');
  SELECT EXISTS(SELECT 1 FROM public.admin_users WHERE user_id=auth.uid() AND active AND role_code='super_admin') INTO v_actor_super;
  IF NOT EXISTS (SELECT 1 FROM public.admin_roles WHERE code=p_role) THEN RAISE EXCEPTION 'Unknown role'; END IF;
  SELECT id INTO v_uid FROM auth.users WHERE lower(email)=lower(trim(p_email));
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No account with this email'; END IF;
  SELECT * INTO v_before FROM public.admin_users WHERE user_id=v_uid;
  IF p_role='super_admin' AND NOT v_actor_super THEN RAISE EXCEPTION 'Only a super admin can grant super admin access'; END IF;
  IF v_before.role_code='super_admin' AND (p_role<>'super_admin' OR NOT p_active) AND NOT v_actor_super THEN RAISE EXCEPTION 'Only a super admin can change a super admin'; END IF;
  IF v_uid=auth.uid() AND (NOT p_active OR p_role<>'super_admin') THEN RAISE EXCEPTION 'You cannot demote or deactivate yourself'; END IF;
  IF v_before.role_code='super_admin' AND (p_role<>'super_admin' OR NOT p_active)
     AND (SELECT count(*) FROM public.admin_users WHERE active AND role_code='super_admin')<=1 THEN
    RAISE EXCEPTION 'At least one active super admin must remain';
  END IF;
  IF NOT v_actor_super AND v_before.user_id IS NOT NULL AND v_before.role_code IS DISTINCT FROM p_role
     AND EXISTS (SELECT 1 FROM public.admin_role_permissions rp WHERE rp.role_code=p_role AND NOT public.has_perm(rp.permission_code)) THEN
    RAISE EXCEPTION 'The selected role contains permissions you do not hold';
  END IF;
  INSERT INTO public.admin_users(user_id,role_code,display_name,email,active,created_by,custom_permissions_enabled)
  VALUES(v_uid,p_role,coalesce(p_display_name,split_part(p_email,'@',1)),lower(trim(p_email)),p_active,auth.uid(),CASE WHEN p_role='super_admin' THEN false ELSE true END)
  ON CONFLICT(user_id) DO UPDATE SET role_code=excluded.role_code,active=excluded.active,
    display_name=coalesce(p_display_name,public.admin_users.display_name),email=excluded.email,
    custom_permissions_enabled=CASE WHEN excluded.role_code='super_admin' OR excluded.role_code IS DISTINCT FROM public.admin_users.role_code THEN false ELSE public.admin_users.custom_permissions_enabled END;
  IF p_role='super_admin' OR (v_before.user_id IS NOT NULL AND v_before.role_code IS DISTINCT FROM p_role) THEN
    DELETE FROM public.admin_user_permissions WHERE user_id=v_uid;
  END IF;
  PERFORM public.write_audit('admin.set','admin_user',v_uid::text,to_jsonb(v_before),jsonb_build_object('role',p_role,'active',p_active),NULL);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_user_permissions(
  p_user_id uuid, p_permission_codes text[], p_use_custom boolean DEFAULT true
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_target public.admin_users; v_before jsonb; v_actor_super boolean;
BEGIN
  PERFORM public.require_perm('admins.manage');
  SELECT EXISTS(SELECT 1 FROM public.admin_users WHERE user_id=auth.uid() AND active AND role_code='super_admin') INTO v_actor_super;
  SELECT * INTO v_target FROM public.admin_users WHERE user_id=p_user_id FOR UPDATE;
  IF v_target.user_id IS NULL THEN RAISE EXCEPTION 'Admin user not found'; END IF;
  IF v_target.role_code='super_admin' THEN RAISE EXCEPTION 'Super admin permissions are always complete'; END IF;
  IF v_target.user_id=auth.uid() THEN RAISE EXCEPTION 'You cannot edit your own permissions'; END IF;
  IF coalesce(array_length(p_permission_codes,1),0)>100 THEN RAISE EXCEPTION 'Too many permissions'; END IF;
  IF EXISTS (SELECT 1 FROM unnest(coalesce(p_permission_codes,'{}'::text[])) x WHERE NOT EXISTS(SELECT 1 FROM public.admin_permissions p WHERE p.code=x)) THEN
    RAISE EXCEPTION 'Unknown permission code';
  END IF;
  IF NOT v_actor_super AND p_use_custom AND EXISTS (
    SELECT 1 FROM unnest(coalesce(p_permission_codes,'{}'::text[])) x
    WHERE NOT public.has_perm(x)
      AND NOT EXISTS (
        SELECT 1 FROM public.admin_user_permissions current_grant
        WHERE current_grant.user_id=p_user_id AND current_grant.permission_code=x
      )
  ) THEN RAISE EXCEPTION 'You cannot grant a permission you do not hold'; END IF;
  IF NOT v_actor_super AND NOT p_use_custom AND EXISTS (
    SELECT 1 FROM public.admin_role_permissions rp WHERE rp.role_code=v_target.role_code AND NOT public.has_perm(rp.permission_code)
  ) THEN RAISE EXCEPTION 'The employee role contains permissions you do not hold'; END IF;
  IF NOT v_actor_super AND p_use_custom AND coalesce(p_permission_codes,'{}'::text[]) @> ARRAY['admins.manage']::text[]
     AND NOT EXISTS (SELECT 1 FROM public.admin_user_permissions WHERE user_id=p_user_id AND permission_code='admins.manage') THEN
    RAISE EXCEPTION 'Only a super admin can grant admin management';
  END IF;
  SELECT jsonb_build_object('custom',v_target.custom_permissions_enabled,
    'permissions',(SELECT coalesce(jsonb_agg(permission_code),'[]'::jsonb) FROM public.admin_user_permissions WHERE user_id=p_user_id)) INTO v_before;
  DELETE FROM public.admin_user_permissions WHERE user_id=p_user_id;
  IF p_use_custom THEN
    INSERT INTO public.admin_user_permissions(user_id,permission_code,granted_by)
    SELECT p_user_id,x,auth.uid() FROM (SELECT DISTINCT unnest(coalesce(p_permission_codes,'{}'::text[])) x) q;
  END IF;
  UPDATE public.admin_users SET custom_permissions_enabled=p_use_custom WHERE user_id=p_user_id;
  PERFORM public.write_audit('admin.permissions','admin_user',p_user_id::text,v_before,
    jsonb_build_object('custom',p_use_custom,'permissions',CASE WHEN p_use_custom THEN to_jsonb(coalesce(p_permission_codes,'{}'::text[])) ELSE '[]'::jsonb END),NULL);
END;
$$;
