-- 0027: write permissions cannot be assigned without their read capability.
DO $$
DECLARE
  v_super uuid := 'eeeeeeee-0000-0000-0000-000000000020';
  v_staff uuid := 'eeeeeeee-0000-0000-0000-000000000021';
  v_failed boolean := false;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',v_super::text,false);

  BEGIN
    PERFORM public.admin_set_user_permissions(v_staff,ARRAY['drivers.approve']::text[],true);
  EXCEPTION WHEN OTHERS THEN v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'drivers.approve was accepted without drivers.read'; END IF;

  v_failed := false;
  BEGIN
    PERFORM public.admin_set_user_permissions(v_staff,ARRAY['finance.read','finance.adjust']::text[],true);
  EXCEPTION WHEN OTHERS THEN v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'finance.adjust was accepted without rides.read'; END IF;

  PERFORM public.admin_set_user_permissions(v_staff,ARRAY['drivers.read','drivers.approve']::text[],true);
  PERFORM set_config('request.jwt.claim.sub',v_staff::text,false);
  IF NOT public.has_perm('drivers.read') OR NOT public.has_perm('drivers.approve') THEN
    RAISE EXCEPTION 'valid read plus management permissions were not granted';
  END IF;
  RAISE NOTICE 'PASS: permission dependency enforcement for custom admin roles';
END $$;
