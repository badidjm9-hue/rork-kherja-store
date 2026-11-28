-- 0027: a permission that mutates a resource also requires its read capability.
-- Ensure every predefined role also contains the read capability required by its management actions.
INSERT INTO public.admin_role_permissions(role_code,permission_code)
SELECT DISTINCT rp.role_code,d.required_code
FROM public.admin_role_permissions rp
JOIN (VALUES
  ('users.manage','users.read'),
  ('drivers.approve','drivers.read'),
  ('drivers.manage','drivers.read'),
  ('rides.manage','rides.read'),
  ('finance.adjust','finance.read'),
  ('finance.adjust','rides.read'),
  ('pricing.manage','pricing.read'),
  ('deliveries.manage','deliveries.read'),
  ('vehicles.manage','vehicles.read'),
  ('notifications.manage','notifications.read'),
  ('settings.manage','settings.read'),
  ('support.manage','support.read')
) AS d(permission_code,required_code) ON d.permission_code=rp.permission_code
WHERE NOT EXISTS (
  SELECT 1 FROM public.admin_role_permissions existing
  WHERE existing.role_code=rp.role_code AND existing.permission_code=d.required_code
)
ON CONFLICT DO NOTHING;

-- Preserve existing management access while making its read dependency explicit.
INSERT INTO public.admin_user_permissions(user_id,permission_code,granted_by)
SELECT DISTINCT up.user_id, d.required_code, NULL::uuid
FROM public.admin_user_permissions up
JOIN (VALUES
  ('users.manage','users.read'),
  ('drivers.approve','drivers.read'),
  ('drivers.manage','drivers.read'),
  ('rides.manage','rides.read'),
  ('finance.adjust','finance.read'),
  ('finance.adjust','rides.read'),
  ('pricing.manage','pricing.read'),
  ('deliveries.manage','deliveries.read'),
  ('vehicles.manage','vehicles.read'),
  ('notifications.manage','notifications.read'),
  ('settings.manage','settings.read'),
  ('support.manage','support.read')
) AS d(permission_code,required_code)
  ON d.permission_code=up.permission_code
WHERE NOT EXISTS (
  SELECT 1 FROM public.admin_user_permissions existing
  WHERE existing.user_id=up.user_id AND existing.permission_code=d.required_code
)
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.validate_admin_permission_dependencies(p_codes text[])
RETURNS void
LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_codes text[] := coalesce(p_codes,'{}'::text[]);
BEGIN
  IF EXISTS (
    SELECT 1 FROM (VALUES
      ('users.manage','users.read'),
      ('drivers.approve','drivers.read'),
      ('drivers.manage','drivers.read'),
      ('rides.manage','rides.read'),
      ('finance.adjust','finance.read'),
      ('finance.adjust','rides.read'),
      ('pricing.manage','pricing.read'),
      ('deliveries.manage','deliveries.read'),
      ('vehicles.manage','vehicles.read'),
      ('notifications.manage','notifications.read'),
      ('settings.manage','settings.read'),
      ('support.manage','support.read')
    ) AS d(permission_code, required_code)
    WHERE d.permission_code = ANY(v_codes)
      AND NOT d.required_code = ANY(v_codes)
  ) THEN
    RAISE EXCEPTION 'Each management permission requires its matching read permission';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.validate_admin_permission_dependencies(text[]) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_user_permissions(
  p_user_id uuid, p_permission_codes text[], p_use_custom boolean DEFAULT true
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_target public.admin_users;
  v_before jsonb;
  v_actor_super boolean;
  v_effective_codes text[];
BEGIN
  PERFORM public.require_perm('admins.manage');
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE user_id=auth.uid() AND active AND role_code='super_admin'
  ) INTO v_actor_super;

  SELECT * INTO v_target FROM public.admin_users WHERE user_id=p_user_id FOR UPDATE;
  IF v_target.user_id IS NULL THEN RAISE EXCEPTION 'Admin user not found'; END IF;
  IF v_target.role_code='super_admin' THEN RAISE EXCEPTION 'Super admin permissions are always complete'; END IF;
  IF v_target.user_id=auth.uid() THEN RAISE EXCEPTION 'You cannot edit your own permissions'; END IF;
  IF coalesce(array_length(p_permission_codes,1),0)>100 THEN RAISE EXCEPTION 'Too many permissions'; END IF;

  IF EXISTS (
    SELECT 1 FROM unnest(coalesce(p_permission_codes,'{}'::text[])) x
    WHERE NOT EXISTS (SELECT 1 FROM public.admin_permissions p WHERE p.code=x)
  ) THEN RAISE EXCEPTION 'Unknown permission code'; END IF;

  IF p_use_custom THEN
    v_effective_codes := coalesce(p_permission_codes,'{}'::text[]);
  ELSE
    SELECT coalesce(array_agg(rp.permission_code),'{}'::text[])
    INTO v_effective_codes
    FROM public.admin_role_permissions rp
    WHERE rp.role_code=v_target.role_code;
  END IF;
  PERFORM public.validate_admin_permission_dependencies(v_effective_codes);

  IF NOT v_actor_super AND p_use_custom AND EXISTS (
    SELECT 1 FROM unnest(coalesce(p_permission_codes,'{}'::text[])) x
    WHERE NOT public.has_perm(x)
      AND NOT EXISTS (
        SELECT 1 FROM public.admin_user_permissions current_grant
        WHERE current_grant.user_id=p_user_id AND current_grant.permission_code=x
      )
  ) THEN RAISE EXCEPTION 'You cannot grant a permission you do not hold'; END IF;

  IF NOT v_actor_super AND NOT p_use_custom AND EXISTS (
    SELECT 1 FROM public.admin_role_permissions rp
    WHERE rp.role_code=v_target.role_code AND NOT public.has_perm(rp.permission_code)
  ) THEN RAISE EXCEPTION 'The employee role contains permissions you do not hold'; END IF;

  IF NOT v_actor_super AND p_use_custom
     AND coalesce(p_permission_codes,'{}'::text[]) @> ARRAY['admins.manage']::text[]
     AND NOT EXISTS (
       SELECT 1 FROM public.admin_user_permissions
       WHERE user_id=p_user_id AND permission_code='admins.manage'
     ) THEN
    RAISE EXCEPTION 'Only a super admin can grant admin management';
  END IF;

  SELECT jsonb_build_object(
    'custom',v_target.custom_permissions_enabled,
    'permissions',(SELECT coalesce(jsonb_agg(permission_code),'[]'::jsonb)
                   FROM public.admin_user_permissions WHERE user_id=p_user_id)
  ) INTO v_before;

  DELETE FROM public.admin_user_permissions WHERE user_id=p_user_id;
  IF p_use_custom THEN
    INSERT INTO public.admin_user_permissions(user_id,permission_code,granted_by)
    SELECT p_user_id,x,auth.uid()
    FROM (SELECT DISTINCT unnest(coalesce(p_permission_codes,'{}'::text[])) x) q;
  END IF;
  UPDATE public.admin_users SET custom_permissions_enabled=p_use_custom WHERE user_id=p_user_id;

  PERFORM public.write_audit(
    'admin.permissions','admin_user',p_user_id::text,v_before,
    jsonb_build_object(
      'custom',p_use_custom,
      'permissions',CASE WHEN p_use_custom THEN to_jsonb(coalesce(p_permission_codes,'{}'::text[])) ELSE '[]'::jsonb END
    ),NULL
  );
END;
$$;
