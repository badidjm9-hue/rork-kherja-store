-- Behavioural tests for migration 0013 (account deletion). Runs after stack_behavior.sql; reuses its t.* helpers.
\set ON_ERROR_STOP on
SET client_min_messages = notice;
INSERT INTO auth.users(id,email) VALUES
 ('eeeeeeee-0000-0000-0000-000000000001','u213555900001@phone.kherja.app'),
 ('eeeeeeee-0000-0000-0000-000000000002','u213555900002@phone.kherja.app');
UPDATE public.profiles SET name='Rider One', phone='0555900001' WHERE id='eeeeeeee-0000-0000-0000-000000000001';
INSERT INTO public.saved_places(user_id,kind,label,address,lat,lng) VALUES ('eeeeeeee-0000-0000-0000-000000000001','home','Maison','Rue 1',36.7,3.0);
INSERT INTO public.notifications(user_id,kind,title) VALUES ('eeeeeeee-0000-0000-0000-000000000001','system','Bienvenue');
INSERT INTO public.ride_requests(id,passenger_id,pickup_label,pickup_lat,pickup_lng,dest_label,dest_lat,dest_lng,distance_km,vehicle,proposed_fare)
 VALUES ('ffffffff-0000-0000-0000-000000000001','eeeeeeee-0000-0000-0000-000000000001','A',36.7,3.0,'B',36.8,3.1,10,'car',800);

SET ROLE anon;
SELECT t.fails($$SELECT public.delete_my_account()$$,'permission denied','anonymous cannot delete accounts');
RESET ROLE;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','eeeeeeee-0000-0000-0000-000000000001',false);
SELECT t.fails($$SELECT public.delete_my_account()$$,'active ride','open request blocks deletion');
SELECT t.works($$SELECT public.cancel_request('ffffffff-0000-0000-0000-000000000001')$$,'user cancels the open request');
SELECT t.works($$SELECT public.delete_my_account()$$,'account deletion succeeds once nothing is active');
SELECT t.works($$SELECT public.delete_my_account()$$,'deletion is idempotent');
SELECT t.eq((SELECT account_status FROM public.profiles WHERE id=auth.uid()),'deleted','profile is closed');
SELECT t.eq((SELECT name FROM public.profiles WHERE id=auth.uid()),'Compte supprimé','name anonymised');
SELECT t.eq((SELECT coalesce(phone,'NULL') FROM public.profiles WHERE id=auth.uid()),'NULL','phone removed');
SELECT t.eq((SELECT count(*) FROM public.saved_places)::text,'0','saved places removed');
SELECT t.eq((SELECT count(*) FROM public.notifications)::text,'0','notifications removed');
SELECT t.fails($$SELECT public.ping_location(36.7,3.0)$$,'suspended','closed account cannot use the API');
RESET ROLE;
SELECT t.eq((SELECT count(*) FROM public.ride_requests WHERE id='ffffffff-0000-0000-0000-000000000001')::text,'1','request history is kept');
SELECT t.eq((SELECT account_status FROM public.profiles WHERE id='eeeeeeee-0000-0000-0000-000000000002'),'active','other users untouched');
SELECT 'DELETE ACCOUNT 0013 PASSED' AS result;
