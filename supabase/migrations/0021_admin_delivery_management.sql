-- 0021: controlled admin cancellation of deliveries.
ALTER TABLE public.delivery_orders
  ADD COLUMN IF NOT EXISTS admin_cancel_reason text;

INSERT INTO public.admin_permissions(code,description)
VALUES ('deliveries.manage','Annuler les livraisons avec motif')
ON CONFLICT(code) DO NOTHING;
INSERT INTO public.admin_role_permissions(role_code,permission_code)
VALUES ('super_admin','deliveries.manage'),('operations_manager','deliveries.manage')
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.admin_cancel_delivery(p_order_id uuid,p_reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_order public.delivery_orders;
BEGIN
  PERFORM public.require_perm('deliveries.manage');
  IF char_length(btrim(coalesce(p_reason,''))) NOT BETWEEN 3 AND 300 THEN
    RAISE EXCEPTION 'A cancellation reason between 3 and 300 characters is required';
  END IF;
  SELECT * INTO v_order FROM public.delivery_orders WHERE id=p_order_id FOR UPDATE;
  IF v_order.id IS NULL THEN RAISE EXCEPTION 'Delivery not found'; END IF;
  IF v_order.status NOT IN ('open','accepted','picked_up') THEN
    RAISE EXCEPTION 'This delivery can no longer be cancelled';
  END IF;
  UPDATE public.delivery_orders
  SET status='cancelled',admin_cancel_reason=btrim(p_reason),updated_at=now()
  WHERE id=p_order_id;
  PERFORM public.write_audit('delivery.cancel','delivery_order',p_order_id::text,
    jsonb_build_object('status',v_order.status,'driver_id',v_order.driver_id),
    jsonb_build_object('status','cancelled','reason',btrim(p_reason)),btrim(p_reason));
  PERFORM public.push_notification(v_order.passenger_id,'delivery','Livraison annulée',
    'Votre livraison a été annulée par le support.',jsonb_build_object('delivery_id',p_order_id,'status','cancelled'));
  IF v_order.driver_id IS NOT NULL THEN
    PERFORM public.push_notification(v_order.driver_id,'delivery','Livraison annulée',
      'Cette livraison a été annulée par le support.',jsonb_build_object('delivery_id',p_order_id,'status','cancelled'));
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_cancel_delivery(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admin_cancel_delivery(uuid,text) TO authenticated;
