-- 0017_push_devices.sql
-- Private per-user device tokens and authenticated registration RPCs for real push delivery.

CREATE TABLE IF NOT EXISTS public.push_devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  platform text NOT NULL CHECK (platform IN ('android','ios')),
  token text NOT NULL UNIQUE CHECK (char_length(token) BETWEEN 32 AND 4096),
  device_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_push_devices_user ON public.push_devices(user_id);
ALTER TABLE public.push_devices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.push_devices FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.register_push_device(
  p_token text,
  p_platform text,
  p_device_id text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_uid uuid := auth.uid(); v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF p_platform NOT IN ('android','ios') THEN RAISE EXCEPTION 'INVALID_PLATFORM'; END IF;
  IF p_token IS NULL OR char_length(btrim(p_token)) < 32 OR char_length(p_token) > 4096 THEN
    RAISE EXCEPTION 'INVALID_PUSH_TOKEN';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id=v_uid AND account_status='active') THEN
    RAISE EXCEPTION 'ACCOUNT_NOT_ACTIVE';
  END IF;

  INSERT INTO push_devices(user_id,platform,token,device_id)
  VALUES(v_uid,p_platform,btrim(p_token),nullif(btrim(p_device_id),''))
  ON CONFLICT(token) DO UPDATE SET
    user_id=EXCLUDED.user_id,
    platform=EXCLUDED.platform,
    device_id=EXCLUDED.device_id,
    updated_at=now()
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.unregister_push_device(p_token text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  DELETE FROM push_devices WHERE user_id=auth.uid() AND token=p_token;
END;
$$;

CREATE OR REPLACE FUNCTION public.purge_deleted_profile_push_devices() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.account_status='deleted' AND OLD.account_status IS DISTINCT FROM NEW.account_status THEN
    DELETE FROM push_devices WHERE user_id=NEW.id;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.purge_deleted_profile_push_devices() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_purge_deleted_profile_push_devices ON public.profiles;
CREATE TRIGGER trg_purge_deleted_profile_push_devices
  AFTER UPDATE OF account_status ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.purge_deleted_profile_push_devices();

REVOKE ALL ON FUNCTION public.register_push_device(text,text,text), public.unregister_push_device(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_push_device(text,text,text), public.unregister_push_device(text) TO authenticated;
