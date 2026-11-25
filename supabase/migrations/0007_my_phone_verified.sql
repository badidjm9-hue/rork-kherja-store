-- 0007_my_phone_verified.sql
-- Additive. Lets a signed-in client ask "does MY account have a verified phone?" without being able
-- to read verified_phones (which stays service-role only). Used by the apps to show the
-- "verify your phone" screen to a driver account before the database would reject driver actions.
-- Depends on public.is_phone_verified (0006). Not applied to any project.

CREATE OR REPLACE FUNCTION public.my_phone_verified() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT CASE WHEN auth.uid() IS NULL THEN false ELSE public.is_phone_verified(auth.uid()) END;
$$;

REVOKE ALL ON FUNCTION public.my_phone_verified() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_phone_verified() TO authenticated;
