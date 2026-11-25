-- 0006_social_phone_gate.sql
-- Additive only. NOT applied to any project; review before running.
-- Google/Apple accounts have no phone. Driver-related services require a VERIFIED phone, enforced
-- here in the database (clients can change their own profile.role / is_online through RLS, so a
-- client-side check alone is not a gate).
--
-- Verified phone = a row in verified_phones (written only by the auth-otp edge function after the
-- SMS code is proven) OR a legacy phone-identity account created by the SMS flow
-- (u213XXXXXXXXX@phone.kherja.app). Keep "Confirm email" enabled in Supabase Auth so nobody can
-- move an account onto that synthetic domain.

CREATE TABLE IF NOT EXISTS public.verified_phones (
  phone text PRIMARY KEY,
  user_id uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  verified_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.verified_phones ENABLE ROW LEVEL SECURITY;
-- No policies: service role (edge function) only.
REVOKE ALL ON public.verified_phones FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.is_phone_verified(p_user uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth
AS $$
  SELECT EXISTS (SELECT 1 FROM public.verified_phones v WHERE v.user_id = p_user)
      OR EXISTS (SELECT 1 FROM auth.users u
                 WHERE u.id = p_user AND u.email ~ '^u213[5-7][0-9]{8}@phone\.kherja\.app$');
$$;
REVOKE ALL ON FUNCTION public.is_phone_verified(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.require_phone_for_driver() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_subject uuid;
  v_gated boolean := false;
BEGIN
  IF TG_TABLE_NAME = 'profiles' THEN
    v_subject := NEW.id;
    IF TG_OP = 'INSERT' THEN
      v_gated := NEW.role = 'driver' OR NEW.is_online;
    ELSE
      v_gated := (NEW.role = 'driver' AND OLD.role IS DISTINCT FROM 'driver')
              OR (NEW.is_online AND NOT OLD.is_online);
    END IF;
  ELSE -- offers, driver_documents
    v_subject := NEW.driver_id;
    v_gated := true;
  END IF;
  IF v_gated AND NOT public.is_phone_verified(v_subject) THEN
    RAISE EXCEPTION 'PHONE_NOT_VERIFIED: a verified phone number is required for driver services'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.require_phone_for_driver() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_driver_phone_profiles ON public.profiles;
CREATE TRIGGER trg_driver_phone_profiles BEFORE INSERT OR UPDATE OF role, is_online ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.require_phone_for_driver();

DROP TRIGGER IF EXISTS trg_driver_phone_offers ON public.offers;
CREATE TRIGGER trg_driver_phone_offers BEFORE INSERT ON public.offers
  FOR EACH ROW EXECUTE FUNCTION public.require_phone_for_driver();

DROP TRIGGER IF EXISTS trg_driver_phone_documents ON public.driver_documents;
CREATE TRIGGER trg_driver_phone_documents BEFORE INSERT OR UPDATE ON public.driver_documents
  FOR EACH ROW EXECUTE FUNCTION public.require_phone_for_driver();
