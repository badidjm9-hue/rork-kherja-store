-- 0021: admin delivery cancellation is permission-gated, audited and not a driver transition.
DO $$
DECLARE
  v_admin uuid := 'eeeeeeee-0000-0000-0000-000000000031';
  v_staff uuid := 'eeeeeeee-0000-0000-0000-000000000032';
  v_passenger uuid := 'eeeeeeee-0000-0000-0000-000000000033';
  v_order uuid;
  v_failed boolean := false;
BEGIN
  INSERT INTO auth.users(id,email) VALUES
    (v_admin,'admin0021@kherja.test'),
    (v_staff,'staff0021@kherja.test'),
    (v_passenger,'passenger0021@kherja.test');
  INSERT INTO public.admin_users(user_id,role_code,display_name,email,active) VALUES
    (v_admin,'super_admin','Admin 21','admin0021@kherja.test',true),
    (v_staff,'support_agent','Staff 21','staff0021@kherja.test',true);
  INSERT INTO public.delivery_orders(
    passenger_id,pickup_label,pickup_lat,pickup_lng,dest_label,dest_lat,dest_lng,
    distance_km,vehicle,package_description,recipient_name,recipient_phone,delivery_fee
  ) VALUES (
    v_passenger,'A',36.75,3.05,'B',36.76,3.06,1.2,'car','Test parcel','Receiver','0550000031',200
  ) RETURNING id INTO v_order;

  PERFORM set_config('request.jwt.claim.sub',v_staff::text,false);
  v_failed := false;
  BEGIN
    PERFORM public.admin_cancel_delivery(v_order,'Support cancellation');
  EXCEPTION WHEN OTHERS THEN v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'staff without deliveries.manage cancelled a delivery'; END IF;

  PERFORM set_config('request.jwt.claim.sub',v_admin::text,false);
  PERFORM public.admin_cancel_delivery(v_order,'Duplicate delivery request');
  IF NOT EXISTS(SELECT 1 FROM public.delivery_orders WHERE id=v_order AND status='cancelled' AND admin_cancel_reason='Duplicate delivery request') THEN
    RAISE EXCEPTION 'admin cancellation was not persisted';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.audit_logs WHERE entity_type='delivery_order' AND entity_id=v_order::text AND action='delivery.cancel') THEN
    RAISE EXCEPTION 'admin cancellation was not audited';
  END IF;
  RAISE NOTICE 'PASS: delivery management permission gate, cancellation, reason and audit';
END $$;
