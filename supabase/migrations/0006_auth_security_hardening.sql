-- KHERJA auth hardening: atomic phone + IP attempt reservation and finalization.
-- Apply only after reviewing this migration; it is not deployed by this commit.

ALTER TABLE public.auth_login_attempts
  ADD COLUMN IF NOT EXISTS ip_hash text;

CREATE INDEX IF NOT EXISTS idx_auth_login_attempts_ip_kind_time
  ON public.auth_login_attempts (ip_hash, kind, attempted_at DESC)
  WHERE ip_hash IS NOT NULL;

CREATE OR REPLACE FUNCTION public.reserve_auth_attempt(
  p_phone text,
  p_kind text,
  p_window_seconds integer,
  p_phone_limit integer,
  p_failures_only boolean,
  p_ip_hash text,
  p_ip_limit integer
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_phone_lock bigint;
  v_ip_lock bigint;
  v_count bigint;
  v_attempt_id bigint;
BEGIN
  IF p_phone IS NULL OR p_phone = ''
     OR p_ip_hash IS NULL OR p_ip_hash = ''
     OR p_kind NOT IN ('password', 'otp_verify', 'otp_request')
     OR p_window_seconds < 1 OR p_phone_limit < 1 OR p_ip_limit < 1 THEN
    RAISE EXCEPTION 'invalid auth rate-limit arguments';
  END IF;

  v_phone_lock := hashtextextended('phone:' || p_phone || ':' || p_kind, 0);
  v_ip_lock := hashtextextended('ip:' || p_ip_hash || ':' || p_kind, 0);

  -- Acquire both locks in a stable order to avoid deadlocks between concurrent requests.
  IF v_phone_lock <= v_ip_lock THEN
    PERFORM pg_advisory_xact_lock(v_phone_lock);
    PERFORM pg_advisory_xact_lock(v_ip_lock);
  ELSE
    PERFORM pg_advisory_xact_lock(v_ip_lock);
    PERFORM pg_advisory_xact_lock(v_phone_lock);
  END IF;

  SELECT count(*) INTO v_count
  FROM public.auth_login_attempts
  WHERE phone = p_phone
    AND kind = p_kind
    AND attempted_at >= now() - make_interval(secs => p_window_seconds)
    AND (NOT p_failures_only OR success = false);

  IF v_count >= p_phone_limit THEN
    RETURN NULL;
  END IF;

  SELECT count(*) INTO v_count
  FROM public.auth_login_attempts
  WHERE ip_hash = p_ip_hash
    AND kind = p_kind
    AND attempted_at >= now() - make_interval(secs => p_window_seconds);

  IF v_count >= p_ip_limit THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.auth_login_attempts (phone, kind, success, ip_hash)
  VALUES (p_phone, p_kind, false, p_ip_hash)
  RETURNING id INTO v_attempt_id;

  RETURN v_attempt_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.finish_auth_attempt(
  p_attempt_id bigint,
  p_success boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE public.auth_login_attempts
  SET success = p_success
  WHERE id = p_attempt_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'auth attempt reservation not found';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.reserve_auth_attempt(text, text, integer, integer, boolean, text, integer)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.finish_auth_attempt(bigint, boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_auth_attempt(text, text, integer, integer, boolean, text, integer)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.finish_auth_attempt(bigint, boolean)
  TO service_role;
