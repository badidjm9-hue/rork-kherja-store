-- Behavioural tests over migrations 0001-0010 on a THROWAWAY local Postgres (see local_stack_stub.sql).
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

-- ===== 0010: saved places, notifications, vehicles, settings, reports, receipt =====
-- saved places
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000003',false);
SELECT t.works($$INSERT INTO public.saved_places(user_id,kind,label,address,lat,lng) VALUES (auth.uid(),'home','Maison','Hydra, Alger',36.74,3.04)$$,'passenger saves home');
SELECT t.fails($$INSERT INTO public.saved_places(user_id,kind,label,address,lat,lng) VALUES (auth.uid(),'home','Maison 2','Autre',36.7,3.0)$$,'uq_saved_places_home_work','second home refused');
SELECT t.works($$INSERT INTO public.saved_places(user_id,kind,label,address,lat,lng) VALUES (auth.uid(),'favorite','Café','Didouche',36.77,3.05)$$,'passenger saves favourite');
SELECT t.fails($$INSERT INTO public.saved_places(user_id,kind,label,address,lat,lng) VALUES (auth.uid(),'favorite','Bad','x',91,3.0)$$,'saved_places_lat_check','invalid latitude refused');
SELECT t.fails($$INSERT INTO public.saved_places(user_id,kind,label,address,lat,lng) VALUES ('aaaaaaaa-0000-0000-0000-000000000004','favorite','Spoof','x',36,3)$$,'row-level security','cannot save a place for someone else');
RESET ROLE;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000004',false);
SELECT t.eq((SELECT count(*) FROM public.saved_places)::text,'0','other passenger cannot read saved places');
SELECT t.works($$DELETE FROM public.saved_places$$,'delete by other passenger is a no-op');
RESET ROLE;
SELECT t.eq((SELECT count(*) FROM public.saved_places WHERE user_id='aaaaaaaa-0000-0000-0000-000000000003')::text,'2','original places survive other passenger delete');
-- limit of 20
INSERT INTO public.saved_places(user_id,kind,label,address,lat,lng)
  SELECT 'aaaaaaaa-0000-0000-0000-000000000004','favorite','F'||g,'addr',36,3 FROM generate_series(1,20) g;
SELECT t.fails($$INSERT INTO public.saved_places(user_id,kind,label,address,lat,lng) VALUES ('aaaaaaaa-0000-0000-0000-000000000004','favorite','F21','addr',36,3)$$,'Too many saved places','21st place refused');
DELETE FROM public.saved_places WHERE user_id='aaaaaaaa-0000-0000-0000-000000000004';

-- ride -> notification (+ prefs) and receipt
INSERT INTO public.ride_requests(id,passenger_id,pickup_label,pickup_lat,pickup_lng,dest_label,dest_lat,dest_lng,distance_km,vehicle,proposed_fare,status)
 VALUES ('bbbbbbbb-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000003','Hydra',36.74,3.04,'Bab Ezzouar',36.72,3.18,13,'car',900,'accepted');
INSERT INTO public.rides(id,request_id,passenger_id,driver_id,vehicle,fare,pickup_label,pickup_lat,pickup_lng,dest_label,dest_lat,dest_lng)
 VALUES ('cccccccc-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000002','car',900,'Hydra',36.74,3.04,'Bab Ezzouar',36.72,3.18);
SELECT t.eq((SELECT count(*) FROM public.notifications WHERE user_id='aaaaaaaa-0000-0000-0000-000000000003' AND kind='ride')::text,'1','ride creation notifies passenger');
SELECT t.fails($$SELECT public.ride_receipt('cccccccc-0000-0000-0000-000000000001')$$,'Receipt','no receipt before completion (as superuser, no participant)');
UPDATE public.rides SET status='completed', completed_at=now() WHERE id='cccccccc-0000-0000-0000-000000000001';
SELECT t.eq((SELECT count(*) FROM public.notifications WHERE user_id='aaaaaaaa-0000-0000-0000-000000000003' AND title='Course terminée')::text,'1','completion notifies passenger (fr)');
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000003',false);
SELECT t.eq((public.ride_receipt('cccccccc-0000-0000-0000-000000000001')->>'fare'),'900','passenger gets receipt fare');
SELECT t.eq((public.ride_receipt('cccccccc-0000-0000-0000-000000000001')->>'reference'),'CCCCCCCC','receipt reference');
SELECT t.eq(public.unread_notification_count()::text,'2','unread count is 2');
SELECT t.works($$SELECT public.mark_notification_read((SELECT id FROM public.notifications ORDER BY created_at LIMIT 1))$$,'mark one read');
SELECT t.eq(public.unread_notification_count()::text,'1','unread count is 1');
SELECT t.eq(public.mark_all_notifications_read()::text,'1','mark all read returns 1');
SELECT t.fails($$UPDATE public.notifications SET title='x'$$,'permission denied','client cannot edit notifications directly');
SELECT t.fails($$INSERT INTO public.notifications(user_id,kind,title) VALUES (auth.uid(),'system','forged')$$,'permission denied','client cannot forge notifications');
SELECT t.works($$INSERT INTO public.notification_prefs(user_id,rides,promotions) VALUES (auth.uid(),false,true)$$,'passenger turns ride notifications off');
RESET ROLE;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000004',false);
SELECT t.fails($$SELECT public.ride_receipt('cccccccc-0000-0000-0000-000000000001')$$,'Receipt not found','non-participant cannot read receipt');
RESET ROLE;
UPDATE public.rides SET status='cancelled' WHERE id='cccccccc-0000-0000-0000-000000000001';
SELECT t.eq((SELECT count(*) FROM public.notifications WHERE user_id='aaaaaaaa-0000-0000-0000-000000000002' AND kind='ride')::text,'1','cancellation notifies driver');
-- ride notifications now off for passenger: a new ride status must not notify them
INSERT INTO public.ride_requests(id,passenger_id,pickup_label,pickup_lat,pickup_lng,dest_label,dest_lat,dest_lng,distance_km,vehicle,proposed_fare,status)
 VALUES ('bbbbbbbb-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000003','A',36.74,3.04,'B',36.72,3.18,5,'car',500,'accepted');
INSERT INTO public.rides(request_id,passenger_id,driver_id,vehicle,fare,pickup_label,pickup_lat,pickup_lng,dest_label,dest_lat,dest_lng)
 VALUES ('bbbbbbbb-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000002','car',500,'A',36.74,3.04,'B',36.72,3.18);
SELECT t.eq((SELECT count(*) FROM public.notifications WHERE user_id='aaaaaaaa-0000-0000-0000-000000000003' AND kind='ride')::text,'2','prefs: no new ride notification when rides=false');

-- broadcast
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000006',false);
SELECT t.fails($$SELECT public.admin_send_broadcast('all','system','Hello','Body')$$,'Permission denied','support agent cannot broadcast');
RESET ROLE;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000005',false);
SELECT t.fails($$SELECT public.admin_send_broadcast('everyone','system','Hello','Body')$$,'Invalid audience','invalid audience refused');
SELECT t.fails($$SELECT public.admin_send_broadcast('all','system','','Body')$$,'Invalid title','empty title refused');
SELECT t.works($$SELECT public.admin_send_broadcast('passengers','promo','Promo','-20% cette semaine')$$,'admin sends promo to passengers');
SELECT t.eq((SELECT recipients::text FROM public.notification_broadcasts ORDER BY created_at DESC LIMIT 1),
            (SELECT (count(*))::text FROM public.profiles p WHERE p.role='passenger' AND p.account_status<>'deleted' AND NOT EXISTS (SELECT 1 FROM public.admin_users a WHERE a.user_id=p.id) AND NOT EXISTS (SELECT 1 FROM public.notification_prefs n WHERE n.user_id=p.id AND NOT n.promotions)),'promo recipients = non-staff, non-deleted passengers who allow promotions (0018)');
SELECT t.eq((SELECT count(*) FROM public.audit_logs WHERE action='notification.broadcast')::text,'1','broadcast is audited');
RESET ROLE;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000006',false);
SELECT t.eq((SELECT count(*) FROM public.notification_broadcasts)::text,'1','support agent can read broadcast history (notifications.read)');
RESET ROLE;

-- document review notification
INSERT INTO public.driver_documents(driver_id,doc_type,storage_path,mime_type,status)
 VALUES ('aaaaaaaa-0000-0000-0000-000000000002','license','aaaaaaaa-0000-0000-0000-000000000002/license.jpg','image/jpeg','pending');
UPDATE public.driver_documents SET status='rejected', reason='Illisible (0010)' WHERE driver_id='aaaaaaaa-0000-0000-0000-000000000002' AND doc_type='license';
SELECT t.eq((SELECT count(*) FROM public.notifications WHERE user_id='aaaaaaaa-0000-0000-0000-000000000002' AND kind='document' AND title='Document refusé' AND body='Illisible (0010)')::text,'1','document rejection notifies driver with reason');

-- vehicles
INSERT INTO auth.users(id,email) VALUES ('aaaaaaaa-0000-0000-0000-000000000007','nophone@gmail.com');
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000007',false);
SELECT t.fails($$INSERT INTO public.vehicles(driver_id,category,make,model,plate) VALUES (auth.uid(),'car','Renault','Symbol','123456-116-16')$$,'PHONE_NOT_VERIFIED','unverified social account cannot add a vehicle');
RESET ROLE;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000002',false);
SELECT t.works($$INSERT INTO public.vehicles(driver_id,category,make,model,year,plate,color,seats) VALUES (auth.uid(),'car','Renault','Symbol',2019,'123456-116-16','Blanc',4)$$,'driver adds first vehicle');
SELECT t.eq((SELECT is_primary::text FROM public.vehicles LIMIT 1),'true','first vehicle becomes primary');
SELECT t.eq((SELECT vehicle_plate FROM public.profiles WHERE id=auth.uid()),'123456-116-16','profile.vehicle_plate mirrored');
SELECT t.fails($$INSERT INTO public.vehicles(driver_id,category,make,model,plate) VALUES (auth.uid(),'car','Dacia','Logan','123456 116 16')$$,'uq_vehicles_plate','duplicate plate (normalised) refused');
SELECT t.fails($$INSERT INTO public.vehicles(driver_id,category,make,model,plate) VALUES (auth.uid(),'truck','X','Y','AAA111')$$,'vehicles_category_check','invalid category refused');
SELECT t.works($$INSERT INTO public.vehicles(driver_id,category,make,model,plate,status) VALUES (auth.uid(),'moto','Yamaha','NMax','777-777','suspended')$$,'insert with status=suspended is accepted but neutralised');
SELECT t.eq((SELECT status FROM public.vehicles WHERE plate='777-777'),'active','client cannot pre-set suspended status');
SELECT t.works($$SELECT public.set_primary_vehicle((SELECT id FROM public.vehicles WHERE plate='777-777'))$$,'switch primary vehicle');
SELECT t.eq((SELECT vehicle_make FROM public.profiles WHERE id=auth.uid()),'Yamaha','profile mirrors new primary');
RESET ROLE;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000003',false);
SELECT t.eq((SELECT count(*) FROM public.vehicles)::text,'0','passenger cannot read vehicles');
RESET ROLE;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000006',false);
SELECT t.eq((SELECT count(*) FROM public.vehicles)::text,'2','support agent reads vehicles (vehicles.read)');
SELECT t.fails($$SELECT public.admin_set_vehicle_status((SELECT id FROM public.vehicles LIMIT 1),'suspended','x')$$,'Permission denied','support agent cannot suspend');
RESET ROLE;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000005',false);
SELECT t.fails($$SELECT public.admin_set_vehicle_status((SELECT id FROM public.vehicles WHERE plate='777-777'),'suspended','')$$,'Reason required','suspension requires a reason');
SELECT t.works($$SELECT public.admin_set_vehicle_status((SELECT id FROM public.vehicles WHERE plate='777-777'),'suspended','Documents expirés')$$,'admin suspends vehicle');
RESET ROLE;
SELECT t.eq((SELECT is_primary::text FROM public.vehicles WHERE plate='777-777'),'false','suspended vehicle loses primary');
SELECT t.eq((SELECT vehicle_make FROM public.profiles WHERE id='aaaaaaaa-0000-0000-0000-000000000002'),NULL,'profile vehicle cleared when no primary');
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000002',false);
SELECT t.works($$UPDATE public.vehicles SET status='active', suspended_reason=NULL WHERE plate='777-777'$$,'driver tries to self-reactivate (neutralised)');
SELECT t.eq((SELECT status FROM public.vehicles WHERE plate='777-777'),'suspended','driver cannot lift admin suspension');
SELECT t.fails($$SELECT public.set_primary_vehicle((SELECT id FROM public.vehicles WHERE plate='777-777'))$$,'Vehicle suspended','suspended vehicle cannot be primary');
SELECT t.works($$SELECT public.set_primary_vehicle((SELECT id FROM public.vehicles WHERE plate='123456-116-16'))$$,'driver sets active vehicle primary');
SELECT t.works($$UPDATE public.vehicles SET color='Noir' WHERE plate='123456-116-16'$$,'driver edits own vehicle');
RESET ROLE;
SELECT t.eq((SELECT vehicle_color FROM public.profiles WHERE id='aaaaaaaa-0000-0000-0000-000000000002'),'Noir','edit is mirrored to profile');

-- settings
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000006',false);
SELECT t.eq((SELECT count(*) FROM public.app_settings)::text,'0','support agent has no settings.read');
SELECT t.fails($$SELECT public.admin_set_setting('support.phone','"0550000000"')$$,'Permission denied','support agent cannot change settings');
RESET ROLE;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000005',false);
SELECT t.works($$SELECT public.admin_set_setting('support.phone','"0550000000"')$$,'admin sets support phone');
SELECT t.fails($$SELECT public.admin_set_setting('evil.key','"x"')$$,'Unknown setting','unknown key refused');
SELECT t.fails($$SELECT public.admin_set_setting('ride.offer_ttl_minutes','"ten"')$$,'Invalid value','wrong type refused');
SELECT t.fails($$SELECT public.admin_set_setting('ride.offer_ttl_minutes','500')$$,'Invalid value','out of range refused');
SELECT t.works($$SELECT public.admin_set_setting('ride.offer_ttl_minutes','15')$$,'valid ttl accepted');
SELECT t.fails($$INSERT INTO public.app_settings(key,value) VALUES ('x','1')$$,'permission denied','direct settings write refused');
SELECT t.eq((SELECT value #>> '{}' FROM public.app_settings WHERE key='support.phone'),'0550000000','setting persisted');
RESET ROLE;

-- reports
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000006',false);
SELECT t.fails($$SELECT public.admin_report_summary(current_date-7,current_date)$$,'Permission denied','support agent has no reports.read');
RESET ROLE;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000005',false);
SELECT t.fails($$SELECT public.admin_report_summary(current_date,current_date-1)$$,'Invalid range','inverted range refused');
SELECT t.fails($$SELECT public.admin_report_summary(current_date-400,current_date)$$,'Range too large','range > 366 days refused');
SELECT t.eq((public.admin_report_summary(current_date-1,current_date)->'rides_by_status'->>'cancelled'),'1','report counts the cancelled ride');
SELECT t.eq((public.admin_report_summary(current_date-1,current_date)->>'rides_revenue'),'0','revenue only counts completed rides (one is cancelled now)');
SELECT t.eq(jsonb_array_length(public.admin_report_summary(current_date-1,current_date)->'daily')::text,'2','daily series has one point per day');
SELECT t.eq((public.admin_report_summary(current_date-1,current_date)->'deliveries_by_status'->>'delivered'),'1','report counts the delivered delivery');
RESET ROLE;

SELECT 'ALL CHECKS PASSED' AS result;
