-- 0023: role changes reset custom permission overrides to avoid confusing stale access.
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
  IF v_before.role_code='super_admin' AND (p_role<>'super_admin' OR NOT p_active) AND NOT v_actor_super THEN
    RAISE EXCEPTION 'Only a super admin can change a super admin';
  END IF;
  IF v_uid=auth.uid() AND (NOT p_active OR p_role<>'super_admin') THEN RAISE EXCEPTION 'You cannot demote or deactivate yourself'; END IF;
  IF v_before.role_code='super_admin' AND (p_role<>'super_admin' OR NOT p_active)
     AND (SELECT count(*) FROM public.admin_users WHERE active AND role_code='super_admin')<=1 THEN
    RAISE EXCEPTION 'At least one active super admin must remain';
  END IF;
  INSERT INTO public.admin_users(user_id,role_code,display_name,email,active,created_by)
  VALUES(v_uid,p_role,coalesce(p_display_name,split_part(p_email,'@',1)),lower(trim(p_email)),p_active,auth.uid())
  ON CONFLICT(user_id) DO UPDATE SET role_code=excluded.role_code,active=excluded.active,
    display_name=coalesce(p_display_name,public.admin_users.display_name),email=excluded.email,
    custom_permissions_enabled=CASE
      WHEN excluded.role_code='super_admin' OR excluded.role_code IS DISTINCT FROM public.admin_users.role_code THEN false
      ELSE public.admin_users.custom_permissions_enabled
    END;
  IF p_role='super_admin' OR (v_before.user_id IS NOT NULL AND v_before.role_code IS DISTINCT FROM p_role) THEN
    DELETE FROM public.admin_user_permissions WHERE user_id=v_uid;
  END IF;
  PERFORM public.write_audit('admin.set','admin_user',v_uid::text,to_jsonb(v_before),
    jsonb_build_object('role',p_role,'active',p_active),NULL);
END;
$$;
