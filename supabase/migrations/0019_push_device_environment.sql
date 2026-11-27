-- 0019_push_device_environment.sql
-- Store the APNs environment per device so development and TestFlight/App Store tokens
-- are routed to the correct APNs host independently.

ALTER TABLE public.push_devices
  ADD COLUMN IF NOT EXISTS environment text NOT NULL DEFAULT 'production'
  CHECK (environment IN ('development','production'));

DROP FUNCTION IF EXISTS public.register_push_device(text,text,text);
CREATE FUNCTION public.register_push_device(
  p_token text,
  p_platform text,
  p_device_id text DEFAULT NULL,
  p_environment text DEFAULT 'production'
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_uid uuid := auth.uid(); v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF p_platform NOT IN ('android','ios') THEN RAISE EXCEPTION 'INVALID_PLATFORM'; END IF;
  IF p_environment NOT IN ('development','production') THEN RAISE EXCEPTION 'INVALID_PUSH_ENVIRONMENT'; END IF;
  IF p_token IS NULL OR char_length(btrim(p_token)) < 32 OR char_length(p_token) > 4096 THEN
    RAISE EXCEPTION 'INVALID_PUSH_TOKEN';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id=v_uid AND account_status='active') THEN
    RAISE EXCEPTION 'ACCOUNT_NOT_ACTIVE';
  END IF;

  INSERT INTO push_devices(user_id,platform,token,device_id,environment)
  VALUES(v_uid,p_platform,btrim(p_token),nullif(btrim(p_device_id),''),p_environment)
  ON CONFLICT(token) DO UPDATE SET
    user_id=EXCLUDED.user_id,
    platform=EXCLUDED.platform,
    device_id=EXCLUDED.device_id,
    environment=EXCLUDED.environment,
    updated_at=now()
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.register_push_device(text,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_push_device(text,text,text,text) TO authenticated;
