-- 0027: vehicle managers need driver profile names to operate the vehicle register.
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
        OR public.has_perm('vehicles.read')
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
