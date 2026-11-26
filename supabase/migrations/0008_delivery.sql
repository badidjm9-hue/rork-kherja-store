-- KHERJA Phase 3: parcel delivery MVP.
-- Additive only. Passenger ride tables and existing production data are untouched.
-- Delivery prices follow the approved project decision: car 90 DZD/km,
-- motorcycle 60 DZD/km, with a 350 DZD motorcycle minimum.
-- Passenger payment is cash on delivery; no commission is charged in this phase.

CREATE TABLE IF NOT EXISTS public.delivery_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  passenger_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  driver_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  pickup_label text NOT NULL CHECK (char_length(btrim(pickup_label)) BETWEEN 1 AND 200),
  pickup_lat double precision NOT NULL CHECK (pickup_lat BETWEEN -90 AND 90),
  pickup_lng double precision NOT NULL CHECK (pickup_lng BETWEEN -180 AND 180),
  dest_label text NOT NULL CHECK (char_length(btrim(dest_label)) BETWEEN 1 AND 200),
  dest_lat double precision NOT NULL CHECK (dest_lat BETWEEN -90 AND 90),
  dest_lng double precision NOT NULL CHECK (dest_lng BETWEEN -180 AND 180),
  city text NOT NULL DEFAULT 'Alger',
  distance_km numeric(6,2) NOT NULL CHECK (distance_km > 0 AND distance_km <= 150),
  vehicle text NOT NULL CHECK (vehicle IN ('car','moto')),
  package_description text NOT NULL CHECK (char_length(btrim(package_description)) BETWEEN 2 AND 300),
  recipient_name text NOT NULL CHECK (char_length(btrim(recipient_name)) BETWEEN 2 AND 100),
  recipient_phone text NOT NULL CHECK (char_length(btrim(recipient_phone)) BETWEEN 8 AND 20),
  sender_note text CHECK (sender_note IS NULL OR char_length(sender_note) <= 300),
  delivery_fee integer NOT NULL CHECK (delivery_fee > 0),
  payment_method text NOT NULL DEFAULT 'cash' CHECK (payment_method = 'cash'),
  status text NOT NULL DEFAULT 'open'
    CHECK (status IN ('open','accepted','picked_up','delivered','cancelled','expired')),
  expires_at timestamptz NOT NULL DEFAULT now() + interval '15 minutes',
  accepted_at timestamptz,
  picked_up_at timestamptz,
  delivered_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_delivery_orders_open
  ON public.delivery_orders (status, created_at DESC) WHERE status = 'open';
CREATE INDEX IF NOT EXISTS idx_delivery_orders_passenger
  ON public.delivery_orders (passenger_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_delivery_orders_driver
  ON public.delivery_orders (driver_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uq_delivery_active_passenger
  ON public.delivery_orders (passenger_id)
  WHERE status IN ('open','accepted','picked_up');
CREATE UNIQUE INDEX IF NOT EXISTS uq_delivery_active_driver
  ON public.delivery_orders (driver_id)
  WHERE driver_id IS NOT NULL AND status IN ('accepted','picked_up');

ALTER TABLE public.delivery_orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Delivery participants read orders" ON public.delivery_orders;
CREATE POLICY "Delivery participants read orders"
  ON public.delivery_orders FOR SELECT
  USING (passenger_id = auth.uid() OR driver_id = auth.uid());

-- Drivers receive a deliberately redacted feed. Recipient contact details are
-- visible only after the order has been atomically claimed and assigned.
CREATE OR REPLACE FUNCTION public.open_delivery_feed()
RETURNS TABLE (
  id uuid, passenger_id uuid, pickup_label text, pickup_lat double precision,
  pickup_lng double precision, dest_label text, dest_lat double precision,
  dest_lng double precision, city text, distance_km numeric, vehicle text,
  package_description text, delivery_fee integer, payment_method text, status text, created_at timestamptz
)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_me public.profiles;
BEGIN
  v_me := public.assert_active_user();
  IF v_me.role <> 'driver' OR v_me.driver_status <> 'approved' OR NOT v_me.is_online THEN
    RAISE EXCEPTION 'Approved online driver required';
  END IF;
  UPDATE public.delivery_orders SET status = 'expired', updated_at = now()
  WHERE status = 'open' AND expires_at <= now();
  RETURN QUERY
    SELECT d.id, d.passenger_id, d.pickup_label, d.pickup_lat, d.pickup_lng,
           d.dest_label, d.dest_lat, d.dest_lng, d.city, d.distance_km, d.vehicle,
           d.package_description, d.delivery_fee, d.payment_method, d.status, d.created_at
    FROM public.delivery_orders d
    WHERE d.status = 'open' AND d.expires_at > now()
    ORDER BY d.created_at DESC
    LIMIT 50;
END;
$$;

CREATE OR REPLACE FUNCTION public.quote_delivery(
  p_pickup_lat double precision, p_pickup_lng double precision,
  p_dest_lat double precision, p_dest_lng double precision,
  p_distance_km numeric, p_vehicle text
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_me public.profiles;
  v_km numeric;
  v_rate integer;
  v_fee integer;
BEGIN
  v_me := public.assert_active_user();
  IF v_me.role <> 'passenger' THEN RAISE EXCEPTION 'Passenger role required'; END IF;
  IF p_vehicle NOT IN ('car','moto') THEN RAISE EXCEPTION 'Invalid vehicle'; END IF;
  v_km := public.trusted_distance(p_distance_km, p_pickup_lat, p_pickup_lng, p_dest_lat, p_dest_lng);
  IF v_km < 0.3 OR v_km > 150 THEN RAISE EXCEPTION 'Delivery distance out of range'; END IF;
  v_rate := CASE WHEN p_vehicle = 'car' THEN 90 ELSE 60 END;
  v_fee := greatest(CASE WHEN p_vehicle = 'moto' THEN 350 ELSE 0 END, round(v_km * v_rate / 10.0)::integer * 10);
  RETURN jsonb_build_object(
    'distance_km', round(v_km, 2),
    'vehicle', p_vehicle,
    'rate_per_km', v_rate,
    'minimum_fee', CASE WHEN p_vehicle = 'moto' THEN 350 ELSE 0 END,
    'delivery_fee', v_fee,
    'currency', 'DZD',
    'payment_method', 'cash'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_delivery_order(
  p_pickup_label text, p_pickup_lat double precision, p_pickup_lng double precision,
  p_dest_label text, p_dest_lat double precision, p_dest_lng double precision,
  p_distance_km numeric, p_vehicle text, p_package_description text,
  p_recipient_name text, p_recipient_phone text, p_sender_note text DEFAULT NULL,
  p_city text DEFAULT 'Alger'
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_me public.profiles;
  v_km numeric;
  v_rate integer;
  v_fee integer;
  v_id uuid;
BEGIN
  v_me := public.assert_active_user();
  IF v_me.role <> 'passenger' THEN RAISE EXCEPTION 'Passenger role required'; END IF;
  IF p_vehicle NOT IN ('car','moto') THEN RAISE EXCEPTION 'Invalid vehicle'; END IF;
  IF char_length(btrim(coalesce(p_pickup_label,''))) NOT BETWEEN 1 AND 200
     OR char_length(btrim(coalesce(p_dest_label,''))) NOT BETWEEN 1 AND 200 THEN
    RAISE EXCEPTION 'Invalid delivery address';
  END IF;
  IF char_length(btrim(coalesce(p_package_description,''))) NOT BETWEEN 2 AND 300 THEN
    RAISE EXCEPTION 'Invalid package description';
  END IF;
  IF char_length(btrim(coalesce(p_recipient_name,''))) NOT BETWEEN 2 AND 100
     OR char_length(btrim(coalesce(p_recipient_phone,''))) NOT BETWEEN 8 AND 20 THEN
    RAISE EXCEPTION 'Invalid recipient details';
  END IF;
  UPDATE public.delivery_orders SET status = 'expired', updated_at = now()
  WHERE passenger_id = auth.uid() AND status = 'open' AND expires_at <= now();
  IF EXISTS (
    SELECT 1 FROM public.delivery_orders
    WHERE passenger_id = auth.uid() AND status IN ('open','accepted','picked_up')
  ) THEN RAISE EXCEPTION 'You already have an active delivery'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.rides
    WHERE passenger_id = auth.uid() AND status IN ('en_route','arrived','started')
  ) THEN RAISE EXCEPTION 'Finish your active ride first'; END IF;

  v_km := public.trusted_distance(p_distance_km, p_pickup_lat, p_pickup_lng, p_dest_lat, p_dest_lng);
  IF v_km < 0.3 OR v_km > 150 THEN RAISE EXCEPTION 'Delivery distance out of range'; END IF;
  v_rate := CASE WHEN p_vehicle = 'car' THEN 90 ELSE 60 END;
  v_fee := greatest(CASE WHEN p_vehicle = 'moto' THEN 350 ELSE 0 END, round(v_km * v_rate / 10.0)::integer * 10);

  INSERT INTO public.delivery_orders (
    passenger_id, pickup_label, pickup_lat, pickup_lng,
    dest_label, dest_lat, dest_lng, city, distance_km, vehicle,
    package_description, recipient_name, recipient_phone, sender_note, delivery_fee
  ) VALUES (
    auth.uid(), btrim(p_pickup_label), p_pickup_lat, p_pickup_lng,
    btrim(p_dest_label), p_dest_lat, p_dest_lng, coalesce(nullif(btrim(p_city),''),'Alger'), v_km, p_vehicle,
    btrim(p_package_description), btrim(p_recipient_name), btrim(p_recipient_phone),
    nullif(btrim(coalesce(p_sender_note,'')),''), v_fee
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_delivery_order(p_order_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_me public.profiles;
  v_order public.delivery_orders;
BEGIN
  v_me := public.assert_active_user();
  IF v_me.role <> 'driver' OR v_me.driver_status <> 'approved' OR NOT v_me.is_online THEN
    RAISE EXCEPTION 'Approved online driver required';
  END IF;
  IF EXISTS (SELECT 1 FROM public.rides WHERE driver_id = auth.uid() AND status IN ('en_route','arrived','started'))
     OR EXISTS (SELECT 1 FROM public.delivery_orders WHERE driver_id = auth.uid() AND status IN ('accepted','picked_up')) THEN
    RAISE EXCEPTION 'Finish your active job first';
  END IF;
  SELECT * INTO v_order FROM public.delivery_orders WHERE id = p_order_id FOR UPDATE;
  IF v_order.id IS NULL OR v_order.status <> 'open' OR v_order.expires_at <= now() THEN RAISE EXCEPTION 'Delivery no longer available'; END IF;
  UPDATE public.delivery_orders
  SET driver_id = auth.uid(), status = 'accepted', accepted_at = now(), updated_at = now()
  WHERE id = p_order_id AND status = 'open';
  IF NOT FOUND THEN RAISE EXCEPTION 'Delivery no longer available'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_delivery_status(p_order_id uuid, p_status text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_order public.delivery_orders;
  v_me public.profiles;
BEGIN
  v_me := public.assert_active_user();
  IF v_me.role <> 'driver' THEN RAISE EXCEPTION 'Driver role required'; END IF;
  SELECT * INTO v_order FROM public.delivery_orders WHERE id = p_order_id FOR UPDATE;
  IF v_order.id IS NULL THEN RAISE EXCEPTION 'Delivery not found'; END IF;
  IF v_order.driver_id <> auth.uid() THEN RAISE EXCEPTION 'Only the assigned driver can update delivery'; END IF;
  IF p_status = 'picked_up' AND v_order.status = 'accepted' THEN
    UPDATE public.delivery_orders SET status = 'picked_up', picked_up_at = now(), updated_at = now() WHERE id = p_order_id;
  ELSIF p_status = 'delivered' AND v_order.status = 'picked_up' THEN
    UPDATE public.delivery_orders SET status = 'delivered', delivered_at = now(), updated_at = now() WHERE id = p_order_id;
  ELSE
    RAISE EXCEPTION 'Invalid delivery status transition';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.expire_delivery_orders() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_me public.profiles;
BEGIN
  v_me := public.assert_active_user();
  UPDATE public.delivery_orders SET status = 'expired', updated_at = now()
  WHERE passenger_id = auth.uid() AND status = 'open' AND expires_at <= now();
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_delivery_order(p_order_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_order public.delivery_orders;
  v_me public.profiles;
BEGIN
  v_me := public.assert_active_user();
  IF v_me.role <> 'passenger' THEN RAISE EXCEPTION 'Passenger role required'; END IF;
  SELECT * INTO v_order FROM public.delivery_orders WHERE id = p_order_id FOR UPDATE;
  IF v_order.id IS NULL OR v_order.passenger_id <> auth.uid() THEN RAISE EXCEPTION 'Delivery not found'; END IF;
  IF v_order.status <> 'open' THEN RAISE EXCEPTION 'Only an unassigned delivery can be cancelled'; END IF;
  UPDATE public.delivery_orders SET status = 'cancelled', updated_at = now() WHERE id = p_order_id;
END;
$$;

REVOKE ALL ON public.delivery_orders FROM anon, authenticated;
GRANT SELECT ON public.delivery_orders TO authenticated;
REVOKE EXECUTE ON FUNCTION public.open_delivery_feed() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.quote_delivery(double precision,double precision,double precision,double precision,numeric,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.create_delivery_order(text,double precision,double precision,text,double precision,double precision,numeric,text,text,text,text,text,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.claim_delivery_order(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.update_delivery_status(uuid,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.cancel_delivery_order(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.expire_delivery_orders() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.open_delivery_feed() TO authenticated;
GRANT EXECUTE ON FUNCTION public.quote_delivery(double precision,double precision,double precision,double precision,numeric,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_delivery_order(text,double precision,double precision,text,double precision,double precision,numeric,text,text,text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_delivery_order(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_delivery_status(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_delivery_order(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.expire_delivery_orders() TO authenticated;
