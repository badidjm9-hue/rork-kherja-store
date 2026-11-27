-- Disposable PostgreSQL test for migration 0016 only.
SET client_min_messages = notice;
DO $$
DECLARE
  v_uid uuid := 'eeeeeeee-0000-0000-0000-000000000016';
  v_bad integer;
BEGIN
  SELECT count(*) INTO v_bad
  FROM pg_constraint c
  WHERE c.contype='f'
    AND c.confrelid='auth.users'::regclass
    AND c.confdeltype IN ('a','r');
  IF v_bad <> 0 THEN
    RAISE EXCEPTION 'nullable Auth references still use NO ACTION/RESTRICT (% constraints)', v_bad;
  END IF;

  INSERT INTO auth.users(id,email) VALUES(v_uid,'u213555900016@phone.kherja.app');
  UPDATE public.profiles SET name='Delete Test' WHERE id=v_uid;
  DELETE FROM auth.users WHERE id=v_uid;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=v_uid) THEN
    RAISE EXCEPTION 'profile anchor did not survive Auth deletion';
  END IF;
  RAISE NOTICE 'PASS: migration 0016 makes Auth deletion safe for nullable audit references';
END $$;
