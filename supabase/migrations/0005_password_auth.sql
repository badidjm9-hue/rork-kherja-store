-- 0005_password_auth.sql
-- Additive only. Supports phone + password login, registration and password reset
-- (edge function `auth-otp`, actions `login` and `verify` with a purpose).
--
-- Passwords themselves live in Supabase Auth (auth.users.encrypted_password, hashed by
-- GoTrue with bcrypt). This schema never stores or sees a password.
-- This table only records failed/successful attempts so the edge function can rate-limit
-- brute-force attempts per phone number: password logins, SMS-code checks, and SMS-code
-- requests (the previous request limit counted rows of a one-row-per-phone table, so it
-- could never trigger).
-- Service-role access only.

CREATE TABLE IF NOT EXISTS public.auth_login_attempts (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  phone text NOT NULL,
  kind text NOT NULL DEFAULT 'password' CHECK (kind IN ('password', 'otp_verify', 'otp_request')),
  success boolean NOT NULL,
  attempted_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_auth_login_attempts_phone_kind_time
  ON public.auth_login_attempts (phone, kind, attempted_at DESC);

ALTER TABLE public.auth_login_attempts ENABLE ROW LEVEL SECURITY;
-- No policies on purpose: only the service role (edge function) reads or writes it.

REVOKE ALL ON public.auth_login_attempts FROM PUBLIC, anon, authenticated;
