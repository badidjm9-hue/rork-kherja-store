-- 0020_admin_custom_permissions.sql
-- Per-staff permission sets. Super admins always receive every registered permission.
ALTER TABLE public.admin_users
  ADD COLUMN IF NOT EXISTS custom_permissions_enabled boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS public.admin_user_permissions (
  user_id uuid NOT NULL REFERENCES public.admin_users(user_id) ON DELETE CASCADE,
  permission_code text NOT NULL REFERENCES public.admin_permissions(code) ON DELETE CASCADE,
  granted_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, permission_code)
);
ALTER TABLE public.admin_user_permissions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins read individual permissions" ON public.admin_user_permissions;
CREATE POLICY "Admins read individual permissions"
  ON public.admin_user_permissions FOR SELECT
  USING (public.has_perm('admins.manage'));

CREATE OR REPLACE FUNCTION public.has_perm(p_perm text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users au
    WHERE au.user_id = auth.uid() AND au.active
      AND (
        au.role_code = 'super_admin'
        OR (au.custom_permissions_enabled AND EXISTS (
          SELECT 1 FROM public.admin_user_permissions up
          WHERE up.user_id = au.user_id AND up.permission_code = p_perm
        ))
        OR (NOT au.custom_permissions_enabled AND EXISTS (
          SELECT 1 FROM public.admin_role_permissions rp
          WHERE rp.role_code = au.role_code AND rp.permission_code = p_perm
        ))
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.admin_me() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v public.admin_users;
BEGIN
  SELECT * INTO v FROM public.admin_users WHERE user_id = auth.uid() AND active;
  IF v.user_id IS NULL THEN RETURN NULL; END IF;
  RETURN jsonb_build_object(
    'user_id', v.user_id, 'role', v.role_code, 'display_name', v.display_name, 'email', v.email,
    'permissions', (
      SELECT coalesce(jsonb_agg(p.code ORDER BY p.code), '[]'::jsonb)
      FROM public.admin_permissions p
      WHERE v.role_code = 'super_admin'
         OR (v.custom_permissions_enabled AND EXISTS (
           SELECT 1 FROM public.admin_user_permissions up WHERE up.user_id=v.user_id AND up.permission_code=p.code
         ))
         OR (NOT v.custom_permissions_enabled AND EXISTS (
           SELECT 1 FROM public.admin_role_permissions rp WHERE rp.role_code=v.role_code AND rp.permission_code=p.code
         ))
    )
  );
END;
$$;

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
    custom_permissions_enabled=CASE WHEN excluded.role_code='super_admin' THEN false ELSE public.admin_users.custom_permissions_enabled END;
  IF p_role='super_admin' THEN DELETE FROM public.admin_user_permissions WHERE user_id=v_uid; END IF;
  PERFORM public.write_audit('admin.set','admin_user',v_uid::text,to_jsonb(v_before),
    jsonb_build_object('role',p_role,'active',p_active),NULL);
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
  IF NOT v_actor_super AND coalesce(p_permission_codes,'{}'::text[]) @> ARRAY['admins.manage']::text[] THEN
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
REVOKE ALL ON FUNCTION public.admin_set_user_permissions(uuid,text[],boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_user_permissions(uuid,text[],boolean) TO authenticated;
