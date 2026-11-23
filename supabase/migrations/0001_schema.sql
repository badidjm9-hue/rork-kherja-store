-- KHERJA — schema (native Supabase Auth, auth.uid() RLS)

-- ============ profiles ============
CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'passenger' CHECK (role IN ('passenger','driver')),
  name text NOT NULL DEFAULT '',
  city text NOT NULL DEFAULT 'Alger',
  language text NOT NULL DEFAULT 'fr',
  vehicle_make text,
  vehicle_model text,
  vehicle_plate text,
  vehicle_color text,
  is_online boolean NOT NULL DEFAULT false,
  current_lat double precision,
  current_lng double precision,
  rating_avg numeric(3,2) NOT NULL DEFAULT 5.00,
  rating_count integer NOT NULL DEFAULT 0,
  trips_count integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can read profiles"
  ON public.profiles FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Users insert own profile"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Users update own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Auto-create a profile row on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id) VALUES (new.id) ON CONFLICT (id) DO NOTHING;
  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============ otp_codes (service-role only) ============
CREATE TABLE IF NOT EXISTS public.otp_codes (
  phone text PRIMARY KEY,
  code text NOT NULL,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.otp_codes ENABLE ROW LEVEL SECURITY;
-- No policies: only the service role (edge function) touches this table.

-- ============ ride_requests ============
CREATE TABLE IF NOT EXISTS public.ride_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  passenger_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  pickup_label text NOT NULL,
  pickup_lat double precision NOT NULL,
  pickup_lng double precision NOT NULL,
  dest_label text NOT NULL,
  dest_lat double precision NOT NULL,
  dest_lng double precision NOT NULL,
  city text NOT NULL DEFAULT 'Alger',
  distance_km numeric(6,2) NOT NULL,
  vehicle text NOT NULL CHECK (vehicle IN ('car','moto')),
  proposed_fare integer NOT NULL,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','negotiating','accepted','cancelled','expired')),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT now() + interval '10 minutes'
);

CREATE INDEX IF NOT EXISTS idx_requests_status ON public.ride_requests (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_requests_passenger ON public.ride_requests (passenger_id, created_at DESC);

ALTER TABLE public.ride_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Passengers read own requests"
  ON public.ride_requests FOR SELECT
  USING (passenger_id = auth.uid());

CREATE POLICY "Drivers see open requests"
  ON public.ride_requests FOR SELECT
  USING (
    status IN ('open','negotiating')
    AND expires_at > now()
    AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = 'driver')
  );

CREATE POLICY "Passengers create own requests"
  ON public.ride_requests FOR INSERT
  WITH CHECK (
    passenger_id = auth.uid()
    AND status = 'open'
    AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = 'passenger')
  );

-- Cancellation goes through the cancel_request() RPC; no UPDATE policy.

-- ============ offers ============
CREATE TABLE IF NOT EXISTS public.offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.ride_requests(id) ON DELETE CASCADE,
  driver_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  price integer NOT NULL CHECK (price > 0),
  kind text NOT NULL DEFAULT 'initial' CHECK (kind IN ('initial','counter','quick_reply')),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','declined','expired')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_offers_request ON public.offers (request_id, created_at);

ALTER TABLE public.offers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Request owner and offering driver read offers"
  ON public.offers FOR SELECT
  USING (
    driver_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.ride_requests r WHERE r.id = request_id AND r.passenger_id = auth.uid())
  );

CREATE POLICY "Drivers create offers on live requests"
  ON public.offers FOR INSERT
  WITH CHECK (
    driver_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.ride_requests r
      WHERE r.id = request_id AND r.status IN ('open','negotiating') AND r.expires_at > now()
    )
  );

-- Accept/decline goes through RPCs; no UPDATE policy.

-- ============ rides ============
CREATE TABLE IF NOT EXISTS public.rides (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.ride_requests(id),
  passenger_id uuid NOT NULL REFERENCES public.profiles(id),
  driver_id uuid NOT NULL REFERENCES public.profiles(id),
  vehicle text NOT NULL,
  fare integer NOT NULL CHECK (fare > 0),
  status text NOT NULL DEFAULT 'en_route' CHECK (status IN ('en_route','arrived','started','completed','cancelled')),
  pickup_label text NOT NULL,
  pickup_lat double precision NOT NULL,
  pickup_lng double precision NOT NULL,
  dest_label text NOT NULL,
  dest_lat double precision NOT NULL,
  dest_lng double precision NOT NULL,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rides_passenger ON public.rides (passenger_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_rides_driver ON public.rides (driver_id, created_at DESC);

ALTER TABLE public.rides ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Ride participants read rides"
  ON public.rides FOR SELECT
  USING (passenger_id = auth.uid() OR driver_id = auth.uid());

-- Status transitions and inserts go through RPCs (SECURITY DEFINER).

-- ============ ride_messages (negotiation chat) ============
CREATE TABLE IF NOT EXISTS public.ride_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.ride_requests(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES public.profiles(id),
  body text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 500),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_messages_request ON public.ride_messages (request_id, created_at);

ALTER TABLE public.ride_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Participants read negotiation messages"
  ON public.ride_messages FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.ride_requests r WHERE r.id = request_id AND r.passenger_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.offers o WHERE o.request_id = request_id AND o.driver_id = auth.uid())
  );

CREATE POLICY "Participants write negotiation messages"
  ON public.ride_messages FOR INSERT
  WITH CHECK (
    sender_id = auth.uid()
    AND (
      EXISTS (SELECT 1 FROM public.ride_requests r WHERE r.id = request_id AND r.passenger_id = auth.uid())
      OR EXISTS (SELECT 1 FROM public.offers o WHERE o.request_id = request_id AND o.driver_id = auth.uid())
    )
  );

-- ============ transactions ============
CREATE TABLE IF NOT EXISTS public.transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  ride_id uuid REFERENCES public.rides(id),
  kind text NOT NULL CHECK (kind IN ('payment','earning','topup','bonus')),
  amount integer NOT NULL,
  method text NOT NULL DEFAULT 'cash',
  label text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_transactions_user ON public.transactions (user_id, created_at DESC);

ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own transactions"
  ON public.transactions FOR SELECT
  USING (user_id = auth.uid());

-- Writes go through RPCs (SECURITY DEFINER).

-- ============ ratings ============
CREATE TABLE IF NOT EXISTS public.ratings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id uuid NOT NULL REFERENCES public.rides(id) ON DELETE CASCADE,
  rater_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  ratee_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  stars integer NOT NULL CHECK (stars BETWEEN 1 AND 5),
  comment text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (ride_id, rater_id)
);

ALTER TABLE public.ratings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Ride participants read ratings of their rides"
  ON public.ratings FOR SELECT
  USING (rater_id = auth.uid() OR ratee_id = auth.uid());

-- Writes go through submit_rating RPC.

-- ==================== RPCs ====================

-- Passenger creates a ride request.
CREATE OR REPLACE FUNCTION public.create_request(
  p_pickup_label text, p_pickup_lat double precision, p_pickup_lng double precision,
  p_dest_label text, p_dest_lat double precision, p_dest_lng double precision,
  p_distance_km numeric, p_vehicle text, p_proposed_fare integer
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_role text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  SELECT role INTO v_role FROM profiles WHERE id = auth.uid();
  IF v_role <> 'passenger' THEN RAISE EXCEPTION 'Passenger role required'; END IF;
  IF p_vehicle NOT IN ('car','moto') THEN RAISE EXCEPTION 'Invalid vehicle'; END IF;
  IF p_proposed_fare < 100 OR p_proposed_fare > 10000 THEN RAISE EXCEPTION 'Fare out of range'; END IF;
  IF p_distance_km < 0.3 OR p_distance_km > 120 THEN RAISE EXCEPTION 'Distance out of range'; END IF;

  INSERT INTO ride_requests (
    passenger_id, pickup_label, pickup_lat, pickup_lng,
    dest_label, dest_lat, dest_lng, distance_km, vehicle, proposed_fare
  ) VALUES (
    auth.uid(), p_pickup_label, p_pickup_lat, p_pickup_lng,
    p_dest_label, p_dest_lat, p_dest_lng, p_distance_km, p_vehicle, p_proposed_fare
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- Driver makes (or counters) an offer on a request.
CREATE OR REPLACE FUNCTION public.make_offer(
  p_request_id uuid, p_price integer, p_kind text DEFAULT 'initial'
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_status text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'driver') THEN
    RAISE EXCEPTION 'Driver role required';
  END IF;
  SELECT status INTO v_status FROM ride_requests WHERE id = p_request_id;
  IF v_status IS NULL THEN RAISE EXCEPTION 'Request not found'; END IF;
  IF v_status NOT IN ('open','negotiating') THEN RAISE EXCEPTION 'Request no longer available'; END IF;
  IF p_price < 50 OR p_price > 10000 THEN RAISE EXCEPTION 'Price out of range'; END IF;
  IF p_kind NOT IN ('initial','counter','quick_reply') THEN RAISE EXCEPTION 'Invalid kind'; END IF;

  INSERT INTO offers (request_id, driver_id, price, kind)
  VALUES (p_request_id, auth.uid(), p_price, p_kind)
  RETURNING id INTO v_id;

  UPDATE ride_requests SET status = 'negotiating' WHERE id = p_request_id AND status = 'open';

  RETURN v_id;
END;
$$;

-- Passenger accepts an offer: the price is locked into a ride (server-side).
CREATE OR REPLACE FUNCTION public.accept_offer(p_offer_id uuid) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_offer offers;
  v_request ride_requests;
  v_ride_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;

  SELECT * INTO v_offer FROM offers WHERE id = p_offer_id FOR UPDATE;
  IF v_offer.id IS NULL THEN RAISE EXCEPTION 'Offer not found'; END IF;
  IF v_offer.status <> 'pending' THEN RAISE EXCEPTION 'Offer no longer available'; END IF;

  SELECT * INTO v_request FROM ride_requests WHERE id = v_offer.request_id FOR UPDATE;
  IF v_request.passenger_id <> auth.uid() THEN RAISE EXCEPTION 'Only the request owner can accept'; END IF;
  IF v_request.status NOT IN ('open','negotiating') THEN RAISE EXCEPTION 'Request no longer available'; END IF;

  -- Price lock: create the ride at the negotiated fare.
  INSERT INTO rides (request_id, passenger_id, driver_id, vehicle, fare,
                     pickup_label, pickup_lat, pickup_lng, dest_label, dest_lat, dest_lng)
  VALUES (v_request.id, v_request.passenger_id, v_offer.driver_id, v_request.vehicle, v_offer.price,
          v_request.pickup_label, v_request.pickup_lat, v_request.pickup_lng,
          v_request.dest_label, v_request.dest_lat, v_request.dest_lng)
  RETURNING id INTO v_ride_id;

  UPDATE offers SET status = 'accepted' WHERE id = p_offer_id;
  UPDATE offers SET status = 'declined' WHERE request_id = v_request.id AND id <> p_offer_id AND status = 'pending';
  UPDATE ride_requests SET status = 'accepted' WHERE id = v_request.id;

  INSERT INTO ride_messages (request_id, sender_id, body)
  VALUES (v_request.id, auth.uid(), 'OFFRE_ACCEPTEE:' || v_offer.price::text);

  RETURN v_ride_id;
END;
$$;

-- Passenger cancels a live request.
CREATE OR REPLACE FUNCTION public.cancel_request(p_request_id uuid) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  UPDATE ride_requests
  SET status = 'cancelled'
  WHERE id = p_request_id AND passenger_id = auth.uid() AND status IN ('open','negotiating');
  UPDATE offers SET status = 'declined'
  WHERE request_id = p_request_id AND status = 'pending';
END;
$$;

-- Driver advances ride status (en_route -> arrived -> started -> completed, or cancelled).
CREATE OR REPLACE FUNCTION public.update_ride(p_ride_id uuid, p_status text) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_ride rides;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  SELECT * INTO v_ride FROM rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;
  IF v_ride.driver_id <> auth.uid() THEN RAISE EXCEPTION 'Only the driver can update the ride'; END IF;
  IF p_status NOT IN ('en_route','arrived','started','completed','cancelled') THEN RAISE EXCEPTION 'Invalid status'; END IF;

  UPDATE rides SET
    status = p_status,
    started_at = CASE WHEN p_status = 'started' THEN now() ELSE started_at END,
    completed_at = CASE WHEN p_status = 'completed' THEN now() ELSE completed_at END
  WHERE id = p_ride_id;

  IF p_status = 'completed' THEN
    INSERT INTO transactions (user_id, ride_id, kind, amount, method, label)
    VALUES (v_ride.passenger_id, v_ride.id, 'payment', -v_ride.fare, 'cash', 'Course ' || v_ride.pickup_label || ' → ' || v_ride.dest_label);
    INSERT INTO transactions (user_id, ride_id, kind, amount, method, label)
    VALUES (v_ride.driver_id, v_ride.id, 'earning', v_ride.fare, 'cash', 'Course ' || v_ride.pickup_label || ' → ' || v_ride.dest_label);
    UPDATE profiles SET trips_count = trips_count + 1, updated_at = now() WHERE id = v_ride.passenger_id;
    UPDATE profiles SET trips_count = trips_count + 1, updated_at = now() WHERE id = v_ride.driver_id;
  END IF;

  IF p_status = 'cancelled' THEN
    UPDATE ride_requests SET status = 'cancelled' WHERE id = v_ride.request_id AND status = 'accepted';
  END IF;
END;
$$;

-- Submit a rating for a completed ride.
CREATE OR REPLACE FUNCTION public.submit_rating(p_ride_id uuid, p_stars integer, p_comment text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_ride rides;
  v_ratee uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  IF p_stars < 1 OR p_stars > 5 THEN RAISE EXCEPTION 'Invalid rating'; END IF;
  SELECT * INTO v_ride FROM rides WHERE id = p_ride_id;
  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;
  IF v_ride.status <> 'completed' THEN RAISE EXCEPTION 'Ride not completed'; END IF;
  IF v_ride.passenger_id = auth.uid() THEN v_ratee := v_ride.driver_id;
  ELSIF v_ride.driver_id = auth.uid() THEN v_ratee := v_ride.passenger_id;
  ELSE RAISE EXCEPTION 'Not a ride participant'; END IF;

  INSERT INTO ratings (ride_id, rater_id, ratee_id, stars, comment)
  VALUES (p_ride_id, auth.uid(), v_ratee, p_stars, p_comment)
  ON CONFLICT (ride_id, rater_id) DO NOTHING;

  UPDATE profiles SET
    rating_avg = ROUND(
      (SELECT avg(stars) FROM ratings WHERE ratee_id = v_ratee)::numeric, 2),
    rating_count = (SELECT count(*) FROM ratings WHERE ratee_id = v_ratee),
    updated_at = now()
  WHERE id = v_ratee;
END;
$$;

-- Expire stale requests and their pending offers (called by cron or on read).
CREATE OR REPLACE FUNCTION public.expire_stale_requests() RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  UPDATE ride_requests SET status = 'expired'
  WHERE status IN ('open','negotiating') AND expires_at < now();
  UPDATE offers SET status = 'expired'
  WHERE status = 'pending' AND request_id IN (
    SELECT id FROM ride_requests WHERE status IN ('expired','cancelled')
  );
END;
$$;
