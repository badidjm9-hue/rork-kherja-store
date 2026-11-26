-- Behavioural tests over migrations 0001-0009 on a THROWAWAY local Postgres (see local_stack_stub.sql).
-- Each check prints "PASS <label>" or aborts with "FAIL <label>". Never run against a real project.
\set ON_ERROR_STOP on
SET client_min_messages = notice;
CREATE SCHEMA IF NOT EXISTS t;
GRANT USAGE ON SCHEMA t TO authenticated;
CREATE OR REPLACE FUNCTION t.works(q text, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN EXECUTE q; RAISE NOTICE 'PASS %', label;
EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'FAIL % : %', label, sqlerrm; END $$;
CREATE OR REPLACE FUNCTION t.fails(q text, needle text, label text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE m text;
BEGIN
  BEGIN EXECUTE q;
  EXCEPTION WHEN OTHERS THEN
    m := sqlerrm;
    IF position(lower(needle) in lower(m)) > 0 THEN RAISE NOTICE 'PASS %', label; RETURN; END IF;
    RAISE EXCEPTION 'FAIL % : wrong error: %', label, m;
  END;
  RAISE EXCEPTION 'FAIL % : succeeded but should have failed', label;
END $$;
CREATE OR REPLACE FUNCTION t.eq(actual text, expected text, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF actual IS NOT DISTINCT FROM expected THEN RAISE NOTICE 'PASS %', label;
  ELSE RAISE EXCEPTION 'FAIL % : got [%] expected [%]', label, actual, expected; END IF;
END $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA t TO authenticated;

-- users: G social (no phone), D phone-identity driver, P/P2 passengers, ADM super admin, SUP support agent
INSERT INTO auth.users(id,email) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000001','g@gmail.com'),
 ('aaaaaaaa-0000-0000-0000-000000000002','u213555111222@phone.kherja.app'),
 ('aaaaaaaa-0000-0000-0000-000000000003','u213555333444@phone.kherja.app'),
 ('aaaaaaaa-0000-0000-0000-000000000004','u213555555666@phone.kherja.app'),
 ('aaaaaaaa-0000-0000-0000-000000000005','admin@example.com'),
 ('aaaaaaaa-0000-0000-0000-000000000006','support@example.com');
INSERT INTO public.admin_users(user_id, role_code, display_name, email) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000005','super_admin','Admin','admin@example.com'),
 ('aaaaaaaa-0000-0000-0000-000000000006','support_agent','Support','support@example.com');

-- ===== 1. phone gate (0006) =====
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000001',false);
SELECT t.eq(public.my_phone_verified()::text,'false','social account reports phone not verified (0007)');
SELECT t.fails($$UPDATE public.profiles SET role='driver' WHERE id=auth.uid()$$,'PHONE_NOT_VERIFIED','social account cannot become a driver');
SELECT t.works($$UPDATE public.profiles SET is_online=true WHERE id=auth.uid()$$,'passenger-role update to online is accepted but neutralised');
SELECT t.eq((SELECT is_online::text FROM public.profiles WHERE id=auth.uid()),'false','social/passenger account stays offline');
RESET ROLE;
INSERT INTO public.verified_phones(phone,user_id) VALUES ('+213666000111','aaaaaaaa-0000-0000-0000-000000000001');
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000001',false);
SELECT t.eq(public.my_phone_verified()::text,'true','linked phone is reflected by my_phone_verified');
SELECT t.works($$UPDATE public.profiles SET role='driver' WHERE id=auth.uid()$$,'social account may become a driver after phone verification');
SELECT t.eq((SELECT driver_status FROM public.profiles WHERE id=auth.uid()),'pending','new driver starts in pending review');
RESET ROLE;
SELECT t.eq((SELECT has_table_privilege('authenticated','public.verified_phones','SELECT'))::text,'false','clients cannot read verified_phones');

-- phone-identity driver D
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000002',false);
SELECT t.works($$UPDATE public.profiles SET role='driver', vehicle_make='Dacia', vehicle_model='Logan', vehicle_plate='123-456' WHERE id=auth.uid()$$,'phone-identity driver can switch role');

-- ===== 2. documents: storage policy + submit RPC =====
SELECT t.works($$INSERT INTO storage.objects(bucket_id,name,owner) VALUES ('driver-documents', auth.uid()||'/id_card_1.jpg', auth.uid())$$,'driver can upload into own folder');
SELECT t.fails($$INSERT INTO storage.objects(bucket_id,name,owner) VALUES ('driver-documents','aaaaaaaa-0000-0000-0000-000000000009/id_card.jpg', auth.uid())$$,'row-level security','driver cannot upload into another folder');
SELECT t.works($$SELECT public.submit_driver_document('id_card', auth.uid()||'/id_card_1.jpg','image/jpeg')$$,'submit_driver_document registers own file');
SELECT t.fails($$SELECT public.submit_driver_document('id_card','aaaaaaaa-0000-0000-0000-000000000009/x.jpg','image/jpeg')$$,'Invalid document path','submit rejects a path in another folder');
SELECT t.fails($$SELECT public.submit_driver_document('id_card', auth.uid()||'/missing.jpg','image/jpeg')$$,'file not found','submit rejects a file that was never uploaded');
SELECT t.fails($$SELECT public.submit_driver_document('selfie', auth.uid()||'/id_card_1.jpg','image/jpeg')$$,'Invalid document type','submit rejects unknown document type');
SELECT t.fails($$SELECT public.admin_review_document((SELECT id FROM public.driver_documents LIMIT 1),'approved')$$,'Permission denied','a driver cannot review documents');
RESET ROLE;

-- ===== 3. admin review (0003 + admin UI) =====
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000005',false);
SELECT t.eq((SELECT count(*) FROM public.driver_documents)::text,'1','admin sees driver documents');
SELECT t.eq((SELECT count(*) FROM storage.objects WHERE bucket_id='driver-documents')::text,'1','admin can read private bucket objects (signed-link review)');
SELECT t.fails($$SELECT public.admin_review_document((SELECT id FROM public.driver_documents LIMIT 1),'rejected','')$$,'reason is required','rejection requires a reason');
SELECT t.works($$SELECT public.admin_review_document((SELECT id FROM public.driver_documents LIMIT 1),'rejected','Photo floue')$$,'admin rejects with a reason');
SELECT t.eq((SELECT status||':'||reason FROM public.driver_documents LIMIT 1),'rejected:Photo floue','rejection stored with reason');
SELECT t.works($$SELECT public.admin_review_document((SELECT id FROM public.driver_documents LIMIT 1),'approved')$$,'admin approves');
SELECT t.eq((SELECT count(*) FROM public.audit_logs WHERE action LIKE 'document.%')::text,'2','both reviews are audited');
RESET ROLE;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000006',false);
SELECT t.fails($$SELECT public.admin_review_document((SELECT id FROM public.driver_documents LIMIT 1),'approved')$$,'Permission denied','support agent (read-only) cannot review');
SELECT t.eq((SELECT count(*) FROM public.driver_documents)::text,'1','support agent can read documents');
RESET ROLE;

-- ===== 4. 0009 admin RPC / permissions =====
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000005',false);
SELECT t.eq((SELECT bool_and(phone_verified)::text FROM public.admin_driver_phone_status(ARRAY['aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000002']::uuid[])),'true','admin phone status: linked + phone-identity both verified');
RESET ROLE;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000003',false);
SELECT t.fails($$SELECT * FROM public.admin_driver_phone_status(ARRAY['aaaaaaaa-0000-0000-0000-000000000001']::uuid[])$$,'Permission denied','passenger cannot call admin_driver_phone_status');
RESET ROLE;

-- ===== 5. delivery lifecycle + privacy =====
-- approve D and bring online (admin approves; 0004 makes documents optional for approval)
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000005',false);
SELECT t.works($$SELECT public.admin_set_driver_status('aaaaaaaa-0000-0000-0000-000000000002','approved')$$,'admin approves driver');
RESET ROLE;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000002',false);
SELECT t.works($$UPDATE public.profiles SET is_online=true WHERE id=auth.uid()$$,'approved phone-identity driver goes online');
SELECT t.eq((SELECT is_online::text FROM public.profiles WHERE id=auth.uid()),'true','driver is online');
RESET ROLE;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000003',false);
SELECT t.works($$SELECT public.create_delivery_order('Hydra','36.7450','3.0400','Bab Ezzouar','36.7200','3.1800',13,'car','Colis de documents','Karim B','0555123456',NULL,'Alger')$$,'passenger creates a delivery order');
SELECT t.fails($$SELECT public.create_delivery_order('Hydra',36.745,3.04,'Bab Ezzouar',36.72,3.18,13,'car','Autre colis','Karim B','0555123456',NULL,'Alger')$$,'already have an active','second active delivery is refused');
RESET ROLE;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000004',false);
SELECT t.eq((SELECT count(*) FROM public.delivery_orders)::text,'0','other passenger cannot see the order');
RESET ROLE;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000006',false);
SELECT t.eq((SELECT count(*) FROM public.delivery_orders)::text,'1','support agent sees the order via deliveries.read (0009)');
RESET ROLE;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000002',false);
SELECT t.eq((SELECT count(*) FROM public.open_delivery_feed())::text,'1','online driver sees the open order in the feed');
SELECT t.eq((SELECT count(*) FROM public.delivery_orders)::text,'0','driver cannot read the raw row before claiming (recipient data protected)');
SELECT t.works($$SELECT public.claim_delivery_order((SELECT id FROM public.open_delivery_feed() LIMIT 1))$$,'driver claims the order');
SELECT t.eq((SELECT recipient_phone FROM public.delivery_orders LIMIT 1),'0555123456','assigned driver can now read recipient phone');
SELECT t.fails($$SELECT public.update_delivery_status((SELECT id FROM public.delivery_orders LIMIT 1),'delivered')$$,'Invalid delivery status transition','cannot skip pickup');
SELECT t.works($$SELECT public.update_delivery_status((SELECT id FROM public.delivery_orders LIMIT 1),'picked_up')$$,'driver marks picked up');
SELECT t.works($$SELECT public.update_delivery_status((SELECT id FROM public.delivery_orders LIMIT 1),'delivered')$$,'driver marks delivered');
RESET ROLE;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000006',false);
SELECT t.eq((SELECT status FROM public.delivery_orders LIMIT 1),'delivered','support agent sees final status');
RESET ROLE;
SELECT 'ALL CHECKS PASSED' AS result;
