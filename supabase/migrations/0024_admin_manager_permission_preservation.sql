-- 0024: managers may preserve an existing admin-management grant but cannot create one.
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
  IF NOT v_actor_super AND p_use_custom
     AND coalesce(p_permission_codes,'{}'::text[]) @> ARRAY['admins.manage']::text[]
     AND NOT EXISTS (
       SELECT 1 FROM public.admin_user_permissions
       WHERE user_id=p_user_id AND permission_code='admins.manage'
     ) THEN
    RAISE EXCEPTION 'Only a super admin can grant admin management';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(coalesce(p_permission_codes,'{}'::text[])) x
    WHERE NOT EXISTS(SELECT 1 FROM public.admin_permissions p WHERE p.code=x)) THEN
    RAISE EXCEPTION 'Unknown permission code';
  END IF;
  SELECT jsonb_build_object('custom',v_target.custom_permissions_enabled,
    'permissions',(SELECT coalesce(jsonb_agg(permission_code),'[]'::jsonb) FROM public.admin_user_permissions WHERE user_id=p_user_id))
  INTO v_before;
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
