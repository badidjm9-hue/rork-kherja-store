-- Explicit least-privilege grants for individual admin permission records.
REVOKE ALL ON TABLE public.admin_user_permissions FROM anon;
GRANT SELECT ON TABLE public.admin_user_permissions TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.admin_user_permissions FROM anon, authenticated;
