-- 0026: enforce employee read permissions on profile records, including direct REST queries.
-- Ordinary app users retain the existing app-facing profile visibility for compatibility.
DROP POLICY IF EXISTS "Authenticated can read profiles" ON public.profiles;
CREATE POLICY "Authenticated can read profiles"
  ON public.profiles FOR SELECT TO authenticated
  USING (
    id = auth.uid()
    OR NOT EXISTS (
      SELECT 1 FROM public.admin_users au WHERE au.user_id = auth.uid()
    )
    OR (
      role = 'driver'
      AND (
        public.has_perm('drivers.read')
        OR public.has_perm('rides.read')
        OR public.has_perm('deliveries.read')
        OR public.has_perm('support.read')
      )
    )
    OR (
      role = 'passenger'
      AND (
        public.has_perm('users.read')
        OR public.has_perm('rides.read')
        OR public.has_perm('deliveries.read')
        OR public.has_perm('support.read')
      )
    )
  );
