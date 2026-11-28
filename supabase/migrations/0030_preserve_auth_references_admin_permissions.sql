-- 0030_preserve_auth_references_admin_permissions.sql
-- Migration 0020 added admin_user_permissions.granted_by REFERENCES auth.users(id) (NO ACTION), which would
-- block deleting the Auth identity of any admin who granted permissions, and breaks the invariant set by 0016.
-- Re-apply the 0016 rule (idempotent): nullable Auth references become ON DELETE SET NULL.
-- Not applied to any Supabase project; apply only with explicit approval.

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
