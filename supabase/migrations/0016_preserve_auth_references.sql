-- 0016_preserve_auth_references.sql
-- Auth identity deletion must not be blocked by nullable audit/creator/reviewer references.
-- Keep the profile FK removal in 0015 and retain CASCADE only for disposable identity-owned rows
-- (admin membership and verified-phone ownership). Historical business/audit rows keep their
-- contents and simply lose the reference to the deleted Auth identity.

DO $$
DECLARE
  r record;
  v_definition text;
BEGIN
  FOR r IN
    SELECT c.oid, c.conrelid, c.conname
    FROM pg_constraint c
    WHERE c.contype='f'
      AND c.confrelid='auth.users'::regclass
      AND c.conrelid <> 'public.profiles'::regclass
      AND c.confdeltype NOT IN ('c','n')
  LOOP
    v_definition := pg_get_constraintdef(r.oid);
    v_definition := regexp_replace(
      v_definition,
      ' ON DELETE (NO ACTION|RESTRICT|CASCADE|SET NULL|SET DEFAULT)',
      '',
      'i'
    );
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', r.conrelid::regclass, r.conname);
    EXECUTE format(
      'ALTER TABLE %s ADD CONSTRAINT %I %s ON DELETE SET NULL',
      r.conrelid::regclass,
      r.conname,
      v_definition
    );
  END LOOP;
END $$;
