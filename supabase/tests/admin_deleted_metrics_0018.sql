-- Disposable PostgreSQL checks for deleted-account visibility in admin metrics and broadcasts.
SET client_min_messages = notice;
\set ON_ERROR_STOP on
DO $$
DECLARE
  v_admin uuid := 'eeeeeeee-0000-0000-0000-000000000028';
  v_deleted_passenger uuid := 'eeeeeeee-0000-0000-0000-000000000029';
  v_deleted_driver uuid := 'eeeeeeee-0000-0000-0000-000000000030';
  v_data jsonb;
  v_recipients integer;
  v_broadcast uuid;
  v_expected integer;
BEGIN
  INSERT INTO auth.users(id,email) VALUES
    (v_admin,'admin0018@example.test'),
    (v_deleted_passenger,'deleted-passenger0018@example.test'),
    (v_deleted_driver,'deleted-driver0018@example.test');
  INSERT INTO public.admin_users(user_id,role_code,display_name,email)
  VALUES(v_admin,'super_admin','Admin 0018','admin0018@example.test');
  UPDATE public.profiles SET account_status='deleted', name='Compte supprimé', phone=NULL
    WHERE id=v_deleted_passenger;
  -- Migration 0006 gates the passenger->driver role change on a verified phone; give the fixture one.
  INSERT INTO public.verified_phones(phone,user_id) VALUES ('+213550000030',v_deleted_driver);
  UPDATE public.profiles SET role='driver', driver_status='pending', account_status='deleted', name='Compte supprimé', phone=NULL
    WHERE id=v_deleted_driver;

  PERFORM set_config('request.jwt.claim.sub',v_admin::text,false);
  PERFORM set_config('request.jwt.claim.role','authenticated',false);
  v_data := public.admin_overview(now() - interval '1 day', now());
  IF (v_data->>'passengers')::integer <> (
    SELECT count(*) FROM public.profiles p
    WHERE p.role='passenger' AND p.account_status <> 'deleted'
      AND NOT EXISTS (SELECT 1 FROM public.admin_users a WHERE a.user_id=p.id)
  ) THEN RAISE EXCEPTION 'overview passenger count includes deleted/staff profiles'; END IF;
  IF (v_data->>'drivers')::integer <> (
    SELECT count(*) FROM public.profiles p
    WHERE p.role='driver' AND p.account_status <> 'deleted'
      AND NOT EXISTS (SELECT 1 FROM public.admin_users a WHERE a.user_id=p.id)
  ) THEN RAISE EXCEPTION 'overview driver count includes deleted/staff profiles'; END IF;
  IF (v_data->>'drivers_pending')::integer <> (
    SELECT count(*) FROM public.profiles p
    WHERE p.role='driver' AND p.driver_status='pending' AND p.account_status <> 'deleted'
      AND NOT EXISTS (SELECT 1 FROM public.admin_users a WHERE a.user_id=p.id)
  ) THEN RAISE EXCEPTION 'overview pending driver count includes deleted/staff profiles'; END IF;
  IF (v_data->>'drivers_online')::integer <> (
    SELECT count(*) FROM public.profiles p
    WHERE p.role='driver' AND p.is_online AND p.account_status='active'
      AND NOT EXISTS (SELECT 1 FROM public.admin_users a WHERE a.user_id=p.id)
  ) THEN RAISE EXCEPTION 'overview online driver count includes inactive/staff profiles'; END IF;
  IF (v_data->>'deleted')::integer <> (SELECT count(*) FROM public.profiles WHERE account_status='deleted') THEN
    RAISE EXCEPTION 'overview deleted count is incorrect';
  END IF;

  SELECT count(*) INTO v_expected FROM public.profiles p
  WHERE p.account_status <> 'deleted'
    AND NOT EXISTS (SELECT 1 FROM public.admin_users a WHERE a.user_id=p.id);
  IF public.push_notification(v_deleted_passenger,'system','Must not send','Deleted account', '{}'::jsonb) THEN
    RAISE EXCEPTION 'push_notification accepted a deleted profile';
  END IF;
  IF EXISTS (SELECT 1 FROM public.notifications WHERE user_id=v_deleted_passenger AND title='Must not send') THEN
    RAISE EXCEPTION 'push_notification created an in-app notification for a deleted profile';
  END IF;

  v_recipients := public.admin_send_broadcast('all','system','TEST 0018','Visibility check');
  SELECT id INTO v_broadcast FROM public.notification_broadcasts ORDER BY created_at DESC LIMIT 1;
  IF v_recipients <> v_expected THEN
    RAISE EXCEPTION 'broadcast recipient count %, expected %',v_recipients,v_expected;
  END IF;
  IF EXISTS (SELECT 1 FROM public.notifications WHERE user_id IN (v_deleted_passenger,v_deleted_driver) AND broadcast_id=v_broadcast) THEN
    RAISE EXCEPTION 'deleted account received a broadcast';
  END IF;
  IF EXISTS (SELECT 1 FROM public.notifications WHERE user_id=v_admin AND broadcast_id=v_broadcast) THEN
    RAISE EXCEPTION 'admin account received a customer broadcast';
  END IF;
  RAISE NOTICE 'PASS: admin metrics exclude deleted/staff accounts and broadcasts skip deleted/staff profiles';
END $$;
