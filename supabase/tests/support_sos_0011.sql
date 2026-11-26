-- Behavioural tests for migration 0011 (support tickets + SOS). Runs after stack_behavior.sql; reuses its t.* helpers.
\set ON_ERROR_STOP on
SET client_min_messages = notice;
INSERT INTO auth.users(id,email) VALUES
 ('bbbbbbbb-0000-0000-0000-000000000001','u213555000001@phone.kherja.app'),
 ('bbbbbbbb-0000-0000-0000-000000000003','u213555000003@phone.kherja.app'),
 ('bbbbbbbb-0000-0000-0000-000000000002','u213555000002@phone.kherja.app'),
 ('bbbbbbbb-0000-0000-0000-000000000004','sup2@example.com');
INSERT INTO public.admin_users(user_id, role_code, display_name, email) VALUES ('bbbbbbbb-0000-0000-0000-000000000004','support_agent','Sup2','sup2@example.com');
INSERT INTO public.ride_requests(id,passenger_id,pickup_label,pickup_lat,pickup_lng,dest_label,dest_lat,dest_lng,distance_km,vehicle,proposed_fare)
 VALUES ('cccccccc-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','A',36.7,3.0,'B',36.8,3.1,10,'car',800);
UPDATE public.profiles SET role='driver', driver_status='approved' WHERE id='bbbbbbbb-0000-0000-0000-000000000002';
INSERT INTO public.rides(id,request_id,passenger_id,driver_id,vehicle,fare,status,pickup_label,pickup_lat,pickup_lng,dest_label,dest_lat,dest_lng)
 VALUES ('dddddddd-0000-0000-0000-000000000001','cccccccc-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000002','car',800,'en_route','A',36.7,3.0,'B',36.8,3.1);
-- support + SOS
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','bbbbbbbb-0000-0000-0000-000000000001',false);
SELECT t.works($$INSERT INTO public.support_tickets(user_id,ride_id,category,message) VALUES (auth.uid(),'dddddddd-0000-0000-0000-000000000001','ride','Le chauffeur a pris un détour')$$,'ticket on own ride');
SELECT set_config('request.jwt.claim.sub','bbbbbbbb-0000-0000-0000-000000000003',false);
SELECT t.fails($$INSERT INTO public.support_tickets(user_id,ride_id,category,message) VALUES (auth.uid(),'dddddddd-0000-0000-0000-000000000001','ride','ticket on foreign ride')$$,'row-level security','ticket on foreign ride refused');
SELECT t.fails($$SELECT public.raise_sos('dddddddd-0000-0000-0000-000000000001',36.7,3.0)$$,'RIDE_NOT_FOUND','SOS on foreign ride refused');
SELECT t.fails($$SELECT public.raise_sos(NULL,200,3.0)$$,'sos_alerts_lat_check','SOS latitude validated');
SELECT t.works($$SELECT public.raise_sos(NULL,36.7,3.0)$$,'SOS 1');
SELECT t.works($$SELECT public.raise_sos(NULL,36.7,3.0)$$,'SOS 2');
SELECT t.works($$SELECT public.raise_sos(NULL,36.7,3.0)$$,'SOS 3');
SELECT t.fails($$SELECT public.raise_sos(NULL,36.7,3.0)$$,'SOS_RATE_LIMIT','SOS 4 rate limited');
RESET ROLE;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','bbbbbbbb-0000-0000-0000-000000000004',false);
SELECT t.eq((SELECT count(*) FROM public.sos_alerts)::text,'3','support agent sees SOS alerts');
SELECT t.eq((SELECT count(*) FROM public.support_tickets)::text,'1','support agent sees tickets');
SELECT t.works($$SELECT public.admin_set_sos_status((SELECT id FROM public.sos_alerts LIMIT 1),'acknowledged')$$,'support acknowledges SOS');
SELECT t.works($$SELECT public.admin_set_ticket_status((SELECT id FROM public.support_tickets LIMIT 1),'resolved')$$,'support resolves ticket');
SELECT t.fails($$SELECT public.admin_send_broadcast('all','promo','Hello','x')$$,'permission','support agent cannot broadcast');
SELECT t.fails($$SELECT public.admin_report_summary(current_date-7,current_date)$$,'permission','support agent cannot read reports');
SELECT set_config('request.jwt.claim.sub','bbbbbbbb-0000-0000-0000-000000000001',false);
SELECT t.fails($$SELECT public.admin_set_ticket_status((SELECT id FROM public.support_tickets LIMIT 1),'open')$$,'permission','passenger cannot change ticket status');
RESET ROLE;


SELECT t.fails($$SELECT public.get_support_contact()$$,'x','placeholder') WHERE false;
UPDATE public.app_settings SET value='"0555 00 00 00"'::jsonb WHERE key='support.phone';
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','bbbbbbbb-0000-0000-0000-000000000001',false);
SELECT t.eq((SELECT public.get_support_contact()->>'phone'),'0555 00 00 00','clients read the support phone entered by admins');

RESET ROLE; GRANT USAGE ON SCHEMA t TO anon; GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA t TO anon; SET ROLE anon;
SELECT t.fails($$SELECT public.raise_sos(NULL,1,1)$$,'permission denied','anon cannot raise SOS');
RESET ROLE;
SELECT 'SUPPORT/SOS 0011 PASSED' AS result;


-- Migration 0012: support/SOS event notifications and notification privacy.
-- New ticket -> authorized support staff; status changes -> ticket owner.
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','bbbbbbbb-0000-0000-0000-000000000001',false);
INSERT INTO public.support_tickets(id,user_id,category,message)
VALUES ('eeeeeeee-0000-0000-0000-000000000001',auth.uid(),'account','Notification status lifecycle test');
RESET ROLE;

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','bbbbbbbb-0000-0000-0000-000000000004',false);
SELECT t.eq(
  (SELECT count(*)::text FROM public.notifications
   WHERE user_id=auth.uid() AND data->>'entity_type'='support_ticket'
     AND data->>'entity_id'='eeeeeeee-0000-0000-0000-000000000001' AND data->>'event'='created'),
  '1','support staff receive new ticket notification');
SELECT public.admin_set_ticket_status('eeeeeeee-0000-0000-0000-000000000001','in_progress');
RESET ROLE;

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','bbbbbbbb-0000-0000-0000-000000000001',false);
SELECT t.eq(
  (SELECT count(*)::text FROM public.notifications
   WHERE user_id=auth.uid() AND data->>'entity_type'='support_ticket'
     AND data->>'entity_id'='eeeeeeee-0000-0000-0000-000000000001' AND data->>'event'='status_changed'),
  '1','ticket owner receives status notification');
SELECT public.raise_sos(NULL,36.7,3.0);
RESET ROLE;

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','bbbbbbbb-0000-0000-0000-000000000004',false);
SELECT t.eq(
  (SELECT count(*)::text FROM public.notifications
   WHERE user_id=auth.uid() AND data->>'entity_type'='sos_alert' AND data->>'event'='created'),
  '1','support staff receive SOS notification');
SELECT public.admin_set_sos_status(
  (SELECT id FROM public.sos_alerts WHERE user_id='bbbbbbbb-0000-0000-0000-000000000001' ORDER BY created_at DESC LIMIT 1),
  'acknowledged');
RESET ROLE;

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','bbbbbbbb-0000-0000-0000-000000000001',false);
SELECT t.eq(
  (SELECT count(*)::text FROM public.notifications
   WHERE user_id=auth.uid() AND data->>'entity_type'='sos_alert' AND data->>'event'='status_changed'),
  '1','SOS owner receives acknowledgement notification');
RESET ROLE;
SELECT 'SUPPORT/SOS 0012 NOTIFICATION CHECKS FINISHED' AS result;
