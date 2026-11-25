-- Run only against a local/development database after migrations 0001-0006.
-- This verifies grants and RPC behavior as the service_role caller. It does not
-- replace a multi-session concurrency test for PostgreSQL advisory locks.

BEGIN;

SELECT plan(1);

DO $permissions$
BEGIN
  IF has_function_privilege('anon', 'public.reserve_auth_attempt(text, text, integer, integer, boolean, text, integer)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.reserve_auth_attempt(text, text, integer, integer, boolean, text, integer)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.finish_auth_attempt(bigint, boolean)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.finish_auth_attempt(bigint, boolean)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.consume_auth_otp(text, text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.consume_auth_otp(text, text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'auth hardening RPC is executable by an untrusted role';
  END IF;

  IF NOT has_function_privilege('service_role', 'public.reserve_auth_attempt(text, text, integer, integer, boolean, text, integer)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.finish_auth_attempt(bigint, boolean)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.consume_auth_otp(text, text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'service_role is missing auth hardening RPC privileges';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_proc
    WHERE oid IN (
      'public.reserve_auth_attempt(text, text, integer, integer, boolean, text, integer)'::regprocedure,
      'public.finish_auth_attempt(bigint, boolean)'::regprocedure,
      'public.consume_auth_otp(text, text)'::regprocedure
    ) AND prosecdef
  ) THEN
    RAISE EXCEPTION 'auth hardening RPC must use invoker rights';
  END IF;
END;
$permissions$;

SET LOCAL ROLE service_role;

DO $behavior$
DECLARE
  v_phone text := '+2135' || lpad((floor(random() * 100000000))::bigint::text, 8, '0');
  v_ip_hash text := md5(random()::text || clock_timestamp()::text) || md5(clock_timestamp()::text || random()::text);
  v_other_ip_hash text := md5(clock_timestamp()::text || random()::text) || md5(random()::text || clock_timestamp()::text);
  v_code_hash text := repeat('b', 64);
  v_first bigint;
  v_second bigint;
  v_third bigint;
  v_consumed boolean;
  v_success boolean;
BEGIN
  v_first := public.reserve_auth_attempt(v_phone, 'otp_request', 300, 2, false, v_ip_hash, 10);
  v_second := public.reserve_auth_attempt(v_phone, 'otp_request', 300, 2, false, v_ip_hash, 10);
  v_third := public.reserve_auth_attempt(v_phone, 'otp_request', 300, 2, false, v_ip_hash, 10);
  IF v_first IS NULL OR v_second IS NULL OR v_third IS NOT NULL THEN
    RAISE EXCEPTION 'per-phone reservation limit behavior is incorrect';
  END IF;

  PERFORM public.finish_auth_attempt(v_first, true);
  PERFORM public.finish_auth_attempt(v_second, false);
  SELECT success INTO v_success FROM public.auth_login_attempts WHERE id = v_first;
  IF v_success IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'finish_auth_attempt did not persist success';
  END IF;

  v_first := public.reserve_auth_attempt(v_phone, 'password', 900, 10, false, v_other_ip_hash, 2);
  v_second := public.reserve_auth_attempt('+2136' || substr(v_phone, 6), 'password', 900, 10, false, v_other_ip_hash, 2);
  v_third := public.reserve_auth_attempt('+2137' || substr(v_phone, 6), 'password', 900, 10, false, v_other_ip_hash, 2);
  IF v_first IS NULL OR v_second IS NULL OR v_third IS NOT NULL THEN
    RAISE EXCEPTION 'per-IP reservation limit behavior is incorrect';
  END IF;

  INSERT INTO public.otp_codes (phone, code_hash, expires_at, created_at)
  VALUES (v_phone, v_code_hash, now() + interval '10 minutes', now());
  v_consumed := public.consume_auth_otp(v_phone, v_code_hash);
  IF v_consumed IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'valid OTP was not consumed';
  END IF;
  v_consumed := public.consume_auth_otp(v_phone, v_code_hash);
  IF v_consumed IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'OTP was consumed more than once';
  END IF;
END;
$behavior$;

RESET ROLE;
SELECT ok(true, 'auth hardening RPC permissions and behavior checks completed');
SELECT * FROM finish();

ROLLBACK;
