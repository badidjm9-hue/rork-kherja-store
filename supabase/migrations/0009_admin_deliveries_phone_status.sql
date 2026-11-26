-- 0009_admin_deliveries_phone_status.sql
-- Additive only. NOT applied to any project; review and test on a disposable project first.
-- Depends on 0002 (permissions), 0006 (is_phone_verified), 0008 (delivery_orders).
--
-- Admin console support:
--  1. permission `deliveries.read` + staff SELECT on delivery_orders (admins see full rows,
--     including recipient contact, which is needed for support; passengers/drivers keep the
--     existing participant-only policy).
--  2. admin_driver_phone_status(): lets staff with drivers.read see whether drivers have a
--     verified phone (the social sign-in gate from 0006) without exposing verified_phones.

INSERT INTO public.admin_permissions (code, description) VALUES
  ('deliveries.read', 'Voir les livraisons')
ON CONFLICT (code) DO NOTHING;

INSERT INTO public.admin_role_permissions (role_code, permission_code) VALUES
  ('super_admin', 'deliveries.read'),
  ('operations_manager', 'deliveries.read'),
  ('support_agent', 'deliveries.read'),
  ('financial_manager', 'deliveries.read')
ON CONFLICT DO NOTHING;

DROP POLICY IF EXISTS "Staff read deliveries" ON public.delivery_orders;
CREATE POLICY "Staff read deliveries"
  ON public.delivery_orders FOR SELECT
  USING (public.has_perm('deliveries.read'));

CREATE OR REPLACE FUNCTION public.admin_driver_phone_status(p_ids uuid[])
RETURNS TABLE (user_id uuid, phone_verified boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public.require_perm('drivers.read');
  IF coalesce(array_length(p_ids, 1), 0) > 500 THEN RAISE EXCEPTION 'Too many ids'; END IF;
  RETURN QUERY SELECT i, public.is_phone_verified(i) FROM unnest(p_ids) AS i;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_driver_phone_status(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_driver_phone_status(uuid[]) TO authenticated;
