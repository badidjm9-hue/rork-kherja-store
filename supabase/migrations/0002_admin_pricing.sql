-- KHERJA — phase 1: centralized server-side pricing, commission, admin RBAC,
-- audit logs, driver approval, account suspension, ride status history.
-- Additive: no existing data is dropped.

-- ==================== profiles: status & phone ====================
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS phone text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS account_status text NOT NULL DEFAULT 'active';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS driver_status text NOT NULL DEFAULT 'none';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS status_reason text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS location_updated_at timestamptz;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'profiles_account_status_check') THEN
    ALTER TABLE public.profiles ADD CONSTRAINT profiles_account_status_check
      CHECK (account_status IN ('active','suspended'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'profiles_driver_status_check') THEN
    ALTER TABLE public.profiles ADD CONSTRAINT profiles_driver_status_check
      CHECK (driver_status IN ('none','pending','approved','rejected'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles (role, driver_status);
CREATE INDEX IF NOT EXISTS idx_profiles_online ON public.profiles (is_online) WHERE is_online;

-- Backfill phone from the synthetic auth email (u<digits>@phone.kherja.app).
UPDATE public.profiles p
SET phone = '+' || substring(u.email from '^u([0-9]+)@phone\.kherja\.app$')
FROM auth.users u
WHERE u.id = p.id AND p.phone IS NULL AND u.email ~ '^u[0-9]+@phone\.kherja\.app$';

-- Existing drivers enter the approval queue.
UPDATE public.profiles SET driver_status = 'pending' WHERE role = 'driver' AND driver_status = 'none';

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_phone text;
BEGIN
  IF new.email ~ '^u[0-9]+@phone\.kherja\.app$' THEN
    v_phone := '+' || substring(new.email from '^u([0-9]+)@phone\.kherja\.app$');
  END IF;
  INSERT INTO public.profiles (id, phone) VALUES (new.id, v_phone) ON CONFLICT (id) DO NOTHING;
  RETURN new;
END;
$$;

-- Users may edit their own profile, but never their moderation/rating fields.
CREATE OR REPLACE FUNCTION public.protect_profile_fields()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_user IN ('authenticated','anon') THEN
    IF new.account_status IS DISTINCT FROM old.account_status
       OR new.driver_status IS DISTINCT FROM old.driver_status
       OR new.status_reason IS DISTINCT FROM old.status_reason
       OR new.rating_avg IS DISTINCT FROM old.rating_avg
       OR new.rating_count IS DISTINCT FROM old.rating_count
       OR new.trips_count IS DISTINCT FROM old.trips_count
       OR new.phone IS DISTINCT FROM old.phone THEN
      RAISE EXCEPTION 'Protected profile fields cannot be changed';
    END IF;
    -- Becoming a driver always starts the approval workflow.
    IF new.role = 'driver' AND old.role <> 'driver' AND old.driver_status IN ('none','rejected') THEN
      new.driver_status := 'pending';
    END IF;
    IF new.role = 'driver' AND old.driver_status = 'none' THEN
      new.driver_status := 'pending';
    END IF;
    -- Unapproved or suspended drivers cannot go online.
    IF new.is_online AND (new.role <> 'driver' OR new.driver_status <> 'approved' OR new.account_status <> 'active') THEN
      new.is_online := false;
    END IF;
  END IF;
  new.updated_at := now();
  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS profiles_protect_fields ON public.profiles;
CREATE TRIGGER profiles_protect_fields
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.protect_profile_fields();

-- ==================== admin RBAC ====================
CREATE TABLE IF NOT EXISTS public.admin_roles (
  code text PRIMARY KEY,
  name_fr text NOT NULL,
  name_ar text NOT NULL,
  description text
);

CREATE TABLE IF NOT EXISTS public.admin_permissions (
  code text PRIMARY KEY,
  description text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.admin_role_permissions (
  role_code text NOT NULL REFERENCES public.admin_roles(code) ON DELETE CASCADE,
  permission_code text NOT NULL REFERENCES public.admin_permissions(code) ON DELETE CASCADE,
  PRIMARY KEY (role_code, permission_code)
);

CREATE TABLE IF NOT EXISTS public.admin_users (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role_code text NOT NULL REFERENCES public.admin_roles(code),
  display_name text NOT NULL DEFAULT '',
  email text,
  active boolean NOT NULL DEFAULT true,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz
);

ALTER TABLE public.admin_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

INSERT INTO public.admin_roles (code, name_fr, name_ar, description) VALUES
  ('super_admin', 'Super administrateur', 'مدير عام', 'Accès complet'),
  ('operations_manager', 'Responsable opérations', 'مسؤول العمليات', 'Chauffeurs, passagers, courses'),
  ('support_agent', 'Agent support', 'وكيل الدعم', 'Consultation et assistance'),
  ('financial_manager', 'Responsable financier', 'المسؤول المالي', 'Finances, remboursements'),
  ('pricing_manager', 'Responsable tarification', 'مسؤول التسعير', 'Tarifs et commissions')
ON CONFLICT (code) DO NOTHING;

INSERT INTO public.admin_permissions (code, description) VALUES
  ('overview.read', 'Voir le tableau de bord'),
  ('users.read', 'Voir les passagers'),
  ('users.manage', 'Suspendre / réactiver des comptes'),
  ('drivers.read', 'Voir les chauffeurs'),
  ('drivers.approve', 'Valider ou refuser les chauffeurs'),
  ('drivers.manage', 'Suspendre / réactiver des chauffeurs'),
  ('rides.read', 'Voir les courses et offres'),
  ('rides.manage', 'Annuler des courses'),
  ('finance.read', 'Voir les finances'),
  ('finance.adjust', 'Remboursements et ajustements'),
  ('pricing.read', 'Voir la tarification'),
  ('pricing.manage', 'Modifier et publier la tarification'),
  ('admins.manage', 'Gérer les administrateurs'),
  ('audit.read', 'Voir le journal d''audit')
ON CONFLICT (code) DO NOTHING;

INSERT INTO public.admin_role_permissions (role_code, permission_code)
SELECT 'super_admin', code FROM public.admin_permissions
ON CONFLICT DO NOTHING;

INSERT INTO public.admin_role_permissions (role_code, permission_code) VALUES
  ('operations_manager','overview.read'), ('operations_manager','users.read'), ('operations_manager','users.manage'),
  ('operations_manager','drivers.read'), ('operations_manager','drivers.approve'), ('operations_manager','drivers.manage'),
  ('operations_manager','rides.read'), ('operations_manager','rides.manage'), ('operations_manager','pricing.read'),
  ('support_agent','overview.read'), ('support_agent','users.read'), ('support_agent','drivers.read'), ('support_agent','rides.read'),
  ('financial_manager','overview.read'), ('financial_manager','finance.read'), ('financial_manager','finance.adjust'),
  ('financial_manager','rides.read'), ('financial_manager','pricing.read'), ('financial_manager','drivers.read'),
  ('financial_manager','users.read'),
  ('pricing_manager','overview.read'), ('pricing_manager','pricing.read'), ('pricing_manager','pricing.manage'),
  ('pricing_manager','rides.read'), ('pricing_manager','audit.read')
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.is_admin() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid() AND active);
$$;

CREATE OR REPLACE FUNCTION public.has_perm(p_perm text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM admin_users au
    JOIN admin_role_permissions rp ON rp.role_code = au.role_code
    WHERE au.user_id = auth.uid() AND au.active AND rp.permission_code = p_perm
  );
$$;

CREATE OR REPLACE FUNCTION public.require_perm(p_perm text) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_perm(p_perm) THEN
    RAISE EXCEPTION 'Permission denied: %', p_perm USING ERRCODE = '42501';
  END IF;
END;
$$;

CREATE POLICY "Admins read roles" ON public.admin_roles FOR SELECT USING (public.is_admin());
CREATE POLICY "Admins read permissions" ON public.admin_permissions FOR SELECT USING (public.is_admin());
CREATE POLICY "Admins read role permissions" ON public.admin_role_permissions FOR SELECT USING (public.is_admin());
CREATE POLICY "Admins read admin users" ON public.admin_users FOR SELECT
  USING (user_id = auth.uid() OR public.has_perm('admins.manage'));

-- ==================== audit logs ====================
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  actor_id uuid REFERENCES auth.users(id),
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id text,
  before_data jsonb,
  after_data jsonb,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_created ON public.audit_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_entity ON public.audit_logs (entity_type, entity_id);

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Auditors read audit logs" ON public.audit_logs FOR SELECT USING (public.has_perm('audit.read'));
-- Inserts only through SECURITY DEFINER functions (no INSERT policy).

CREATE OR REPLACE FUNCTION public.write_audit(
  p_action text, p_entity_type text, p_entity_id text,
  p_before jsonb, p_after jsonb, p_reason text
) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, before_data, after_data, reason)
  VALUES (auth.uid(), p_action, p_entity_type, p_entity_id, p_before, p_after, p_reason);
$$;
REVOKE EXECUTE ON FUNCTION public.write_audit(text, text, text, jsonb, jsonb, text) FROM PUBLIC, anon, authenticated;

-- ==================== pricing versions ====================
CREATE TABLE IF NOT EXISTS public.pricing_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version integer GENERATED ALWAYS AS IDENTITY,
  config jsonb NOT NULL,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','archived')),
  effective_at timestamptz,
  note text,
  restored_from uuid REFERENCES public.pricing_versions(id),
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  published_by uuid REFERENCES auth.users(id),
  published_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_pricing_active ON public.pricing_versions (status, effective_at DESC);

ALTER TABLE public.pricing_versions ENABLE ROW LEVEL SECURITY;
-- Internal pricing is NEVER readable by passengers or drivers.
CREATE POLICY "Pricing staff read pricing" ON public.pricing_versions FOR SELECT USING (public.has_perm('pricing.read'));

-- Validate a pricing configuration; raises on any invalid value.
CREATE OR REPLACE FUNCTION public.validate_pricing(c jsonb) RETURNS void
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  v text;
  n numeric;
  k text;
BEGIN
  IF c IS NULL OR jsonb_typeof(c) <> 'object' THEN RAISE EXCEPTION 'Configuration invalide'; END IF;
  FOREACH v IN ARRAY ARRAY['car','moto'] LOOP
    IF c->'vehicles'->v IS NULL THEN RAISE EXCEPTION 'Véhicule manquant: %', v; END IF;
    FOREACH k IN ARRAY ARRAY['base_fare','per_km','min_fare','max_fare','rounding','waiting_per_min','cancellation_fee'] LOOP
      n := (c->'vehicles'->v->>k)::numeric;
      IF n IS NULL OR n < 0 THEN RAISE EXCEPTION 'Valeur invalide %.%', v, k; END IF;
    END LOOP;
    IF (c->'vehicles'->v->>'per_km')::numeric > 1000 THEN RAISE EXCEPTION 'Prix/km trop élevé (%)', v; END IF;
    IF (c->'vehicles'->v->>'base_fare')::numeric > 5000 THEN RAISE EXCEPTION 'Prise en charge trop élevée (%)', v; END IF;
    IF (c->'vehicles'->v->>'rounding')::numeric NOT IN (1,5,10,50,100) THEN RAISE EXCEPTION 'Arrondi invalide (%)', v; END IF;
    IF (c->'vehicles'->v->>'max_fare')::numeric > 0
       AND (c->'vehicles'->v->>'max_fare')::numeric < (c->'vehicles'->v->>'min_fare')::numeric THEN
      RAISE EXCEPTION 'Tarif maximum inférieur au minimum (%)', v;
    END IF;
    n := (c->'commission'->'by_vehicle'->>v)::numeric;
    IF n IS NULL OR n < 0 OR n > 50 THEN RAISE EXCEPTION 'Commission invalide (%)', v; END IF;
  END LOOP;
  FOREACH k IN ARRAY ARRAY['peak','night','weekend'] LOOP
    n := (c->'modifiers'->k->>'pct')::numeric;
    IF n IS NULL OR n < 0 OR n > 100 THEN RAISE EXCEPTION 'Majoration invalide (%)', k; END IF;
  END LOOP;
  n := (c->'modifiers'->>'cap_pct')::numeric;
  IF n IS NULL OR n < 0 OR n > 200 THEN RAISE EXCEPTION 'Plafond de majoration invalide'; END IF;
  IF (c->'promo'->'daytime'->>'car_pct')::numeric NOT BETWEEN 0 AND 50
     OR (c->'promo'->'daytime'->>'moto_pct')::numeric NOT BETWEEN 0 AND 50 THEN
    RAISE EXCEPTION 'Remise invalide';
  END IF;
  IF c->'commission'->>'method' NOT IN ('percent','fixed') THEN RAISE EXCEPTION 'Méthode de commission invalide'; END IF;
  IF (c->'commission'->>'fixed_amount')::numeric < 0
     OR (c->'commission'->>'min_amount')::numeric < 0
     OR (c->'commission'->>'max_amount')::numeric < 0 THEN
    RAISE EXCEPTION 'Montants de commission invalides';
  END IF;
  IF (c->'negotiation'->>'driver_min_pct')::numeric NOT BETWEEN 10 AND 100
     OR (c->'negotiation'->>'driver_max_pct')::numeric NOT BETWEEN 100 AND 500
     OR (c->'negotiation'->>'passenger_min_pct')::numeric NOT BETWEEN 10 AND 100
     OR (c->'negotiation'->>'passenger_max_pct')::numeric NOT BETWEEN 100 AND 500 THEN
    RAISE EXCEPTION 'Limites de négociation invalides';
  END IF;
  FOREACH k IN ARRAY ARRAY['food','parcel'] LOOP
    IF (c->'delivery'->k->>'base_fare')::numeric < 0 OR (c->'delivery'->k->>'per_km')::numeric < 0
       OR (c->'delivery'->k->>'min_fare')::numeric < 0 THEN
      RAISE EXCEPTION 'Tarif livraison invalide (%)', k;
    END IF;
  END LOOP;
  IF jsonb_typeof(c->'cities') <> 'object' THEN RAISE EXCEPTION 'Villes invalides'; END IF;
  FOR k IN SELECT jsonb_object_keys(c->'cities') LOOP
    n := (c->'cities'->k->>'multiplier')::numeric;
    IF n IS NULL OR n < 0.5 OR n > 3 THEN RAISE EXCEPTION 'Coefficient ville invalide (%)', k; END IF;
  END LOOP;
END;
$$;

-- Commission on an agreed fare for a given configuration.
CREATE OR REPLACE FUNCTION public.commission_for(c jsonb, p_vehicle text, p_fare integer) RETURNS integer
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  v_amount numeric;
  v_min numeric := coalesce((c->'commission'->>'min_amount')::numeric, 0);
  v_max numeric := coalesce((c->'commission'->>'max_amount')::numeric, 0);
BEGIN
  IF c->'commission'->>'method' = 'fixed' THEN
    v_amount := coalesce((c->'commission'->>'fixed_amount')::numeric, 0);
  ELSE
    v_amount := p_fare * coalesce((c->'commission'->'by_vehicle'->>p_vehicle)::numeric, 0) / 100.0;
  END IF;
  v_amount := greatest(v_amount, v_min);
  IF v_max > 0 THEN v_amount := least(v_amount, v_max); END IF;
  v_amount := least(v_amount, p_fare);
  RETURN round(v_amount)::integer;
END;
$$;

-- The KHERJA fare engine (structure of the original engine, parameters from config):
-- raw = base + km × per_km, × city coefficient, × (1 + peak/night/weekend, capped),
-- minus daytime promo, rounded, clamped to [min, max].
CREATE OR REPLACE FUNCTION public.compute_fare(
  c jsonb, p_distance numeric, p_vehicle text, p_city text, p_at timestamptz,
  p_commission_override numeric DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  vc jsonb := c->'vehicles'->p_vehicle;
  v_local timestamp := p_at AT TIME ZONE 'Africa/Algiers';
  v_hour int := EXTRACT(hour FROM v_local)::int;
  v_dow int := EXTRACT(dow FROM v_local)::int;
  v_base numeric; v_rate numeric; v_min numeric; v_max numeric; v_round numeric;
  v_city_mult numeric := 1;
  v_adj numeric := 0;
  v_cap numeric;
  v_night boolean := false; v_peak boolean := false; v_weekend boolean := false;
  v_promo numeric := 0;
  v_raw numeric; v_sub numeric; v_before int; v_fare int;
  v_applied jsonb := '[]'::jsonb;
  w jsonb;
  s int; e int;
  v_commission int; v_cfg jsonb := c;
BEGIN
  IF vc IS NULL THEN RAISE EXCEPTION 'Véhicule inconnu'; END IF;
  IF coalesce((vc->>'enabled')::boolean, true) = false THEN RAISE EXCEPTION 'Véhicule indisponible'; END IF;
  v_base := (vc->>'base_fare')::numeric;
  v_rate := (vc->>'per_km')::numeric;
  v_min := (vc->>'min_fare')::numeric;
  v_max := (vc->>'max_fare')::numeric;
  v_round := greatest((vc->>'rounding')::numeric, 1);

  v_raw := v_base + p_distance * v_rate;
  v_applied := v_applied || jsonb_build_array(jsonb_build_object('rule','base','label','Prise en charge','value',v_base));
  v_applied := v_applied || jsonb_build_array(jsonb_build_object('rule','distance','label','Distance × prix/km','value',round(p_distance * v_rate)));

  IF c->'cities' ? p_city AND coalesce((c->'cities'->p_city->>'enabled')::boolean, true) THEN
    v_city_mult := coalesce((c->'cities'->p_city->>'multiplier')::numeric, 1);
    IF v_city_mult <> 1 THEN
      v_applied := v_applied || jsonb_build_array(jsonb_build_object('rule','city','label','Coefficient ' || p_city,'value',v_city_mult));
    END IF;
  END IF;

  -- Night window
  IF coalesce((c->'modifiers'->'night'->>'enabled')::boolean, false) THEN
    s := (c->'modifiers'->'night'->>'start_hour')::int;
    e := (c->'modifiers'->'night'->>'end_hour')::int;
    v_night := CASE WHEN s > e THEN v_hour >= s OR v_hour < e ELSE v_hour >= s AND v_hour < e END;
    IF v_night THEN
      v_adj := v_adj + (c->'modifiers'->'night'->>'pct')::numeric;
      v_applied := v_applied || jsonb_build_array(jsonb_build_object('rule','night','label','Majoration nuit','value',(c->'modifiers'->'night'->>'pct')::numeric));
    END IF;
  END IF;

  -- Peak windows
  IF coalesce((c->'modifiers'->'peak'->>'enabled')::boolean, false) THEN
    FOR w IN SELECT * FROM jsonb_array_elements(coalesce(c->'modifiers'->'peak'->'windows', '[]'::jsonb)) LOOP
      IF v_hour >= (w->>0)::int AND v_hour < (w->>1)::int THEN v_peak := true; END IF;
    END LOOP;
    IF v_peak THEN
      v_adj := v_adj + (c->'modifiers'->'peak'->>'pct')::numeric;
      v_applied := v_applied || jsonb_build_array(jsonb_build_object('rule','peak','label','Majoration heure de pointe','value',(c->'modifiers'->'peak'->>'pct')::numeric));
    END IF;
  END IF;

  -- Weekend days (0 = Sunday … 5 = Friday, 6 = Saturday)
  IF coalesce((c->'modifiers'->'weekend'->>'enabled')::boolean, false)
     AND coalesce(c->'modifiers'->'weekend'->'days', '[]'::jsonb) @> to_jsonb(v_dow) THEN
    v_weekend := true;
    v_adj := v_adj + (c->'modifiers'->'weekend'->>'pct')::numeric;
    v_applied := v_applied || jsonb_build_array(jsonb_build_object('rule','weekend','label','Majoration week-end','value',(c->'modifiers'->'weekend'->>'pct')::numeric));
  END IF;

  v_cap := coalesce((c->'modifiers'->>'cap_pct')::numeric, 30);
  IF v_adj > v_cap THEN
    v_adj := v_cap;
    v_applied := v_applied || jsonb_build_array(jsonb_build_object('rule','cap','label','Plafond de majoration','value',v_cap));
  END IF;

  -- Daytime promo (off-peak, daytime)
  IF coalesce((c->'promo'->'daytime'->>'enabled')::boolean, false) AND NOT v_night AND NOT v_peak THEN
    v_promo := coalesce((c->'promo'->'daytime'->>(p_vehicle || '_pct'))::numeric, 0);
    IF v_promo > 0 THEN
      v_applied := v_applied || jsonb_build_array(jsonb_build_object('rule','promo','label','Remise journée','value',v_promo));
    END IF;
  END IF;

  v_sub := v_raw * v_city_mult * (1 + v_adj / 100.0);
  v_before := (round(v_sub / v_round) * v_round)::int;
  v_fare := (round(v_sub * (1 - v_promo / 100.0) / v_round) * v_round)::int;

  IF v_fare < v_min THEN
    v_fare := v_min::int;
    v_applied := v_applied || jsonb_build_array(jsonb_build_object('rule','minimum','label','Tarif minimum','value',v_min));
  END IF;
  IF v_max > 0 AND v_fare > v_max THEN
    v_fare := v_max::int;
    v_applied := v_applied || jsonb_build_array(jsonb_build_object('rule','maximum','label','Tarif maximum','value',v_max));
  END IF;
  v_before := greatest(v_before, v_fare);

  IF p_commission_override IS NOT NULL THEN
    v_cfg := jsonb_set(jsonb_set(c, '{commission,method}', '"percent"'),
                       ARRAY['commission','by_vehicle',p_vehicle], to_jsonb(p_commission_override));
  END IF;
  v_commission := public.commission_for(v_cfg, p_vehicle, v_fare);

  RETURN jsonb_build_object(
    'fare', v_fare,
    'price_before_discount', v_before,
    'discount', v_before - v_fare,
    'distance_km', round(p_distance, 2),
    'vehicle', p_vehicle,
    'city', p_city,
    'hour', v_hour,
    'night', v_night, 'peak', v_peak, 'weekend', v_weekend,
    'adjustment_pct', v_adj,
    'promo_pct', v_promo,
    'commission', v_commission,
    'driver_net', v_fare - v_commission,
    'commission_method', v_cfg->'commission'->>'method',
    'applied', v_applied
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.compute_fare(jsonb, numeric, text, text, timestamptz, numeric) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.commission_for(jsonb, text, integer) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.active_pricing() RETURNS public.pricing_versions
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT * FROM pricing_versions
  WHERE status = 'published' AND effective_at <= now()
  ORDER BY effective_at DESC, version DESC
  LIMIT 1;
$$;
REVOKE EXECUTE ON FUNCTION public.active_pricing() FROM PUBLIC, anon, authenticated;

-- Seed the initial configuration (v1). Car follows the 60 DA/km default;
-- moto, peak/night/promo/cap keep the original KHERJA engine values.
INSERT INTO public.pricing_versions (config, status, effective_at, note, published_at)
SELECT '{
  "currency": "DZD",
  "vehicles": {
    "car":  {"enabled": true, "base_fare": 0,   "per_km": 60, "min_fare": 60,  "max_fare": 0, "rounding": 10, "waiting_per_min": 10, "cancellation_fee": 0},
    "moto": {"enabled": true, "base_fare": 200, "per_km": 20, "min_fare": 350, "max_fare": 0, "rounding": 50, "waiting_per_min": 5,  "cancellation_fee": 0}
  },
  "modifiers": {
    "peak":    {"enabled": true,  "pct": 10, "windows": [[7,10],[16,20]]},
    "night":   {"enabled": true,  "pct": 15, "start_hour": 22, "end_hour": 6},
    "weekend": {"enabled": false, "pct": 0,  "days": [5,6]},
    "cap_pct": 30
  },
  "promo": {"daytime": {"enabled": true, "car_pct": 5, "moto_pct": 10}},
  "cities": {
    "Alger": {"enabled": true, "multiplier": 1.0},
    "Oran": {"enabled": true, "multiplier": 1.0},
    "Constantine": {"enabled": true, "multiplier": 1.0},
    "Annaba": {"enabled": true, "multiplier": 1.0},
    "Blida": {"enabled": true, "multiplier": 1.0}
  },
  "commission": {"method": "percent", "by_vehicle": {"car": 15, "moto": 12}, "fixed_amount": 0, "min_amount": 0, "max_amount": 0},
  "negotiation": {"driver_min_pct": 70, "driver_max_pct": 200, "passenger_min_pct": 60, "passenger_max_pct": 150},
  "delivery": {
    "food":   {"base_fare": 100, "per_km": 40, "min_fare": 200},
    "parcel": {"base_fare": 150, "per_km": 50, "min_fare": 250}
  }
}'::jsonb, 'published', now(), 'Configuration initiale', now()
WHERE NOT EXISTS (SELECT 1 FROM public.pricing_versions);

-- ==================== distance guard ====================
CREATE OR REPLACE FUNCTION public.haversine_km(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
RETURNS numeric
LANGUAGE sql IMMUTABLE
AS $$
  SELECT (6371 * 2 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
  )))::numeric;
$$;

-- Never trust the client distance: clamp it to [straight line, 2.5 × straight line].
CREATE OR REPLACE FUNCTION public.trusted_distance(
  p_client numeric, p_lat1 double precision, p_lng1 double precision, p_lat2 double precision, p_lng2 double precision
) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  v_line numeric := public.haversine_km(p_lat1, p_lng1, p_lat2, p_lng2);
  v numeric := coalesce(p_client, v_line * 1.3);
BEGIN
  v := greatest(v, v_line);
  v := least(v, greatest(v_line * 2.5, 0.5));
  RETURN round(greatest(v, 0.3), 2);
END;
$$;

-- ==================== ride requests / rides: pricing snapshot ====================
ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS estimated_fare integer;
ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS price_before_discount integer;
ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS discount integer NOT NULL DEFAULT 0;
ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS pricing_version_id uuid REFERENCES public.pricing_versions(id);
ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS women_only boolean NOT NULL DEFAULT false;

ALTER TABLE public.rides ADD COLUMN IF NOT EXISTS estimated_fare integer;
ALTER TABLE public.rides ADD COLUMN IF NOT EXISTS commission integer;
ALTER TABLE public.rides ADD COLUMN IF NOT EXISTS driver_net integer;
ALTER TABLE public.rides ADD COLUMN IF NOT EXISTS distance_km numeric(6,2);
ALTER TABLE public.rides ADD COLUMN IF NOT EXISTS pricing_version_id uuid REFERENCES public.pricing_versions(id);
ALTER TABLE public.rides ADD COLUMN IF NOT EXISTS pricing_snapshot jsonb;
ALTER TABLE public.rides ADD COLUMN IF NOT EXISTS cancel_reason text;
ALTER TABLE public.rides ADD COLUMN IF NOT EXISTS cancelled_by uuid REFERENCES public.profiles(id);
ALTER TABLE public.rides ADD COLUMN IF NOT EXISTS city text NOT NULL DEFAULT 'Alger';

CREATE INDEX IF NOT EXISTS idx_rides_status ON public.rides (status, created_at DESC);

-- Transactions: allow commission / refund / adjustment / withdrawal kinds.
ALTER TABLE public.transactions DROP CONSTRAINT IF EXISTS transactions_kind_check;
ALTER TABLE public.transactions ADD CONSTRAINT transactions_kind_check
  CHECK (kind IN ('payment','earning','topup','bonus','commission','refund','adjustment','withdrawal'));
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES auth.users(id);
CREATE INDEX IF NOT EXISTS idx_transactions_kind ON public.transactions (kind, created_at DESC);

-- ==================== ride status history ====================
CREATE TABLE IF NOT EXISTS public.ride_status_history (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ride_id uuid NOT NULL REFERENCES public.rides(id) ON DELETE CASCADE,
  status text NOT NULL,
  actor_id uuid,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ride_history ON public.ride_status_history (ride_id, created_at);
ALTER TABLE public.ride_status_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Participants and staff read ride history" ON public.ride_status_history FOR SELECT
  USING (
    public.has_perm('rides.read')
    OR EXISTS (SELECT 1 FROM public.rides r WHERE r.id = ride_id AND (r.passenger_id = auth.uid() OR r.driver_id = auth.uid()))
  );

CREATE OR REPLACE FUNCTION public.log_ride_status() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' OR new.status IS DISTINCT FROM old.status THEN
    INSERT INTO ride_status_history (ride_id, status, actor_id, note)
    VALUES (new.id, new.status, auth.uid(), CASE WHEN new.status = 'cancelled' THEN new.cancel_reason END);
  END IF;
  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS rides_status_history ON public.rides;
CREATE TRIGGER rides_status_history
  AFTER INSERT OR UPDATE OF status ON public.rides
  FOR EACH ROW EXECUTE FUNCTION public.log_ride_status();

-- ==================== staff read access ====================
CREATE POLICY "Staff read ride requests" ON public.ride_requests FOR SELECT USING (public.has_perm('rides.read'));
CREATE POLICY "Staff read offers" ON public.offers FOR SELECT USING (public.has_perm('rides.read'));
CREATE POLICY "Staff read rides" ON public.rides FOR SELECT USING (public.has_perm('rides.read'));
CREATE POLICY "Staff read messages" ON public.ride_messages FOR SELECT USING (public.has_perm('rides.read'));
CREATE POLICY "Staff read transactions" ON public.transactions FOR SELECT USING (public.has_perm('finance.read'));
CREATE POLICY "Staff read ratings" ON public.ratings FOR SELECT USING (public.has_perm('rides.read'));

-- Only approved, active drivers see the live request feed.
DROP POLICY IF EXISTS "Drivers see open requests" ON public.ride_requests;
CREATE POLICY "Drivers see open requests"
  ON public.ride_requests FOR SELECT
  USING (
    status IN ('open','negotiating')
    AND expires_at > now()
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.role = 'driver' AND p.driver_status = 'approved' AND p.account_status = 'active'
    )
  );

-- Requests are created only through create_request (server-side pricing).
DROP POLICY IF EXISTS "Passengers create own requests" ON public.ride_requests;
-- Offers are created only through make_offer (negotiation limits).
DROP POLICY IF EXISTS "Drivers create offers on live requests" ON public.offers;

-- ==================== client RPCs ====================
CREATE OR REPLACE FUNCTION public.assert_active_user() RETURNS public.profiles
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v profiles;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  SELECT * INTO v FROM profiles WHERE id = auth.uid();
  IF v.id IS NULL THEN RAISE EXCEPTION 'Profile not found'; END IF;
  IF v.account_status <> 'active' THEN RAISE EXCEPTION 'Account suspended'; END IF;
  RETURN v;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.assert_active_user() FROM PUBLIC, anon;

-- Passenger-facing quote: only the estimated total, the discount and the total.
CREATE OR REPLACE FUNCTION public.quote_fare(
  p_pickup_lat double precision, p_pickup_lng double precision,
  p_dest_lat double precision, p_dest_lng double precision,
  p_distance_km numeric, p_vehicle text, p_city text DEFAULT 'Alger'
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_cfg pricing_versions;
  v_q jsonb;
  v_km numeric;
BEGIN
  PERFORM public.assert_active_user();
  IF p_vehicle NOT IN ('car','moto') THEN RAISE EXCEPTION 'Invalid vehicle'; END IF;
  v_cfg := public.active_pricing();
  IF v_cfg.id IS NULL THEN RAISE EXCEPTION 'Pricing unavailable'; END IF;
  v_km := public.trusted_distance(p_distance_km, p_pickup_lat, p_pickup_lng, p_dest_lat, p_dest_lng);
  v_q := public.compute_fare(v_cfg.config, v_km, p_vehicle, coalesce(p_city, 'Alger'), now());
  RETURN jsonb_build_object(
    'estimated_total', (v_q->>'price_before_discount')::int,
    'discount', (v_q->>'discount')::int,
    'total', (v_q->>'fare')::int,
    'min_proposal', ceil((v_q->>'fare')::numeric * (v_cfg.config->'negotiation'->>'passenger_min_pct')::numeric / 100 / 10) * 10,
    'max_proposal', floor((v_q->>'fare')::numeric * (v_cfg.config->'negotiation'->>'passenger_max_pct')::numeric / 100 / 10) * 10,
    'pricing_version', v_cfg.version
  );
END;
$$;

-- Old 9-argument create_request is replaced (server-side fare & limits).
DROP FUNCTION IF EXISTS public.create_request(text, double precision, double precision, text, double precision, double precision, numeric, text, integer);

CREATE OR REPLACE FUNCTION public.create_request(
  p_pickup_label text, p_pickup_lat double precision, p_pickup_lng double precision,
  p_dest_label text, p_dest_lat double precision, p_dest_lng double precision,
  p_distance_km numeric, p_vehicle text, p_proposed_fare integer,
  p_city text DEFAULT 'Alger', p_women_only boolean DEFAULT false
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_me profiles;
  v_cfg pricing_versions;
  v_q jsonb;
  v_km numeric;
  v_fare int;
  v_lo numeric; v_hi numeric;
  v_id uuid;
BEGIN
  v_me := public.assert_active_user();
  IF v_me.role <> 'passenger' THEN RAISE EXCEPTION 'Passenger role required'; END IF;
  IF p_vehicle NOT IN ('car','moto') THEN RAISE EXCEPTION 'Invalid vehicle'; END IF;
  IF char_length(coalesce(p_pickup_label,'')) NOT BETWEEN 1 AND 200 OR char_length(coalesce(p_dest_label,'')) NOT BETWEEN 1 AND 200 THEN
    RAISE EXCEPTION 'Invalid address';
  END IF;
  IF EXISTS (SELECT 1 FROM ride_requests WHERE passenger_id = auth.uid() AND status IN ('open','negotiating') AND expires_at > now()) THEN
    RAISE EXCEPTION 'You already have an active request';
  END IF;
  IF EXISTS (SELECT 1 FROM rides WHERE passenger_id = auth.uid() AND status IN ('en_route','arrived','started')) THEN
    RAISE EXCEPTION 'You already have an active ride';
  END IF;

  v_cfg := public.active_pricing();
  IF v_cfg.id IS NULL THEN RAISE EXCEPTION 'Pricing unavailable'; END IF;
  v_km := public.trusted_distance(p_distance_km, p_pickup_lat, p_pickup_lng, p_dest_lat, p_dest_lng);
  IF v_km > 150 THEN RAISE EXCEPTION 'Distance out of range'; END IF;
  v_q := public.compute_fare(v_cfg.config, v_km, p_vehicle, coalesce(p_city, 'Alger'), now());
  v_fare := (v_q->>'fare')::int;

  v_lo := v_fare * (v_cfg.config->'negotiation'->>'passenger_min_pct')::numeric / 100;
  v_hi := v_fare * (v_cfg.config->'negotiation'->>'passenger_max_pct')::numeric / 100;
  IF p_proposed_fare IS NULL OR p_proposed_fare < floor(v_lo / 10) * 10 OR p_proposed_fare > ceil(v_hi / 10) * 10 THEN
    RAISE EXCEPTION 'Proposed fare out of allowed range';
  END IF;

  INSERT INTO ride_requests (
    passenger_id, pickup_label, pickup_lat, pickup_lng,
    dest_label, dest_lat, dest_lng, city, distance_km, vehicle, proposed_fare,
    estimated_fare, price_before_discount, discount, pricing_version_id, women_only
  ) VALUES (
    auth.uid(), p_pickup_label, p_pickup_lat, p_pickup_lng,
    p_dest_label, p_dest_lat, p_dest_lng, coalesce(p_city, 'Alger'), v_km, p_vehicle, p_proposed_fare,
    v_fare, (v_q->>'price_before_discount')::int, (v_q->>'discount')::int, v_cfg.id, coalesce(p_women_only, false)
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- Driver offer (or counter): limited around the server estimate.
CREATE OR REPLACE FUNCTION public.make_offer(
  p_request_id uuid, p_price integer, p_kind text DEFAULT 'initial'
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_me profiles;
  v_req ride_requests;
  v_cfg jsonb;
  v_base int;
  v_id uuid;
BEGIN
  v_me := public.assert_active_user();
  IF v_me.role <> 'driver' THEN RAISE EXCEPTION 'Driver role required'; END IF;
  IF v_me.driver_status <> 'approved' THEN RAISE EXCEPTION 'Driver not approved'; END IF;
  IF p_kind NOT IN ('initial','counter','quick_reply') THEN RAISE EXCEPTION 'Invalid kind'; END IF;

  SELECT * INTO v_req FROM ride_requests WHERE id = p_request_id FOR UPDATE;
  IF v_req.id IS NULL THEN RAISE EXCEPTION 'Request not found'; END IF;
  IF v_req.status NOT IN ('open','negotiating') OR v_req.expires_at < now() THEN RAISE EXCEPTION 'Request no longer available'; END IF;
  IF EXISTS (SELECT 1 FROM rides WHERE driver_id = auth.uid() AND status IN ('en_route','arrived','started')) THEN
    RAISE EXCEPTION 'Finish your current ride first';
  END IF;

  SELECT config INTO v_cfg FROM pricing_versions WHERE id = v_req.pricing_version_id;
  IF v_cfg IS NULL THEN v_cfg := (public.active_pricing()).config; END IF;
  v_base := coalesce(v_req.estimated_fare, v_req.proposed_fare);
  IF p_price < floor(v_base * (v_cfg->'negotiation'->>'driver_min_pct')::numeric / 100 / 10) * 10
     OR p_price > ceil(v_base * (v_cfg->'negotiation'->>'driver_max_pct')::numeric / 100 / 10) * 10
     OR p_price < 50 THEN
    RAISE EXCEPTION 'Offer out of allowed range';
  END IF;

  -- One live offer per driver per request: a new one replaces the previous.
  UPDATE offers SET status = 'declined'
  WHERE request_id = p_request_id AND driver_id = auth.uid() AND status = 'pending';

  INSERT INTO offers (request_id, driver_id, price, kind)
  VALUES (p_request_id, auth.uid(), p_price, p_kind)
  RETURNING id INTO v_id;

  UPDATE ride_requests SET status = 'negotiating' WHERE id = p_request_id AND status = 'open';
  RETURN v_id;
END;
$$;

-- Driver-side preview of net earnings for a price (no rates exposed).
CREATE OR REPLACE FUNCTION public.driver_offer_preview(p_request_id uuid, p_price integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_me profiles;
  v_req ride_requests;
  v_cfg jsonb;
  v_base int;
  v_comm int;
BEGIN
  v_me := public.assert_active_user();
  IF v_me.role <> 'driver' THEN RAISE EXCEPTION 'Driver role required'; END IF;
  SELECT * INTO v_req FROM ride_requests WHERE id = p_request_id;
  IF v_req.id IS NULL THEN RAISE EXCEPTION 'Request not found'; END IF;
  SELECT config INTO v_cfg FROM pricing_versions WHERE id = v_req.pricing_version_id;
  IF v_cfg IS NULL THEN v_cfg := (public.active_pricing()).config; END IF;
  v_base := coalesce(v_req.estimated_fare, v_req.proposed_fare);
  v_comm := public.commission_for(v_cfg, v_req.vehicle, greatest(p_price, 0));
  RETURN jsonb_build_object(
    'suggested', v_base,
    'net', greatest(p_price, 0) - v_comm,
    'min_price', greatest(50, floor(v_base * (v_cfg->'negotiation'->>'driver_min_pct')::numeric / 100 / 10) * 10),
    'max_price', ceil(v_base * (v_cfg->'negotiation'->>'driver_max_pct')::numeric / 100 / 10) * 10
  );
END;
$$;

-- Accept an offer: lock the price and snapshot the pricing used.
CREATE OR REPLACE FUNCTION public.accept_offer(p_offer_id uuid) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_offer offers;
  v_request ride_requests;
  v_cfg pricing_versions;
  v_comm int;
  v_ride_id uuid;
BEGIN
  PERFORM public.assert_active_user();

  SELECT * INTO v_offer FROM offers WHERE id = p_offer_id FOR UPDATE;
  IF v_offer.id IS NULL THEN RAISE EXCEPTION 'Offer not found'; END IF;
  IF v_offer.status <> 'pending' THEN RAISE EXCEPTION 'Offer no longer available'; END IF;

  SELECT * INTO v_request FROM ride_requests WHERE id = v_offer.request_id FOR UPDATE;
  IF v_request.passenger_id <> auth.uid() THEN RAISE EXCEPTION 'Only the request owner can accept'; END IF;
  IF v_request.status NOT IN ('open','negotiating') THEN RAISE EXCEPTION 'Request no longer available'; END IF;
  IF EXISTS (SELECT 1 FROM rides WHERE driver_id = v_offer.driver_id AND status IN ('en_route','arrived','started')) THEN
    UPDATE offers SET status = 'expired' WHERE id = p_offer_id;
    RAISE EXCEPTION 'Driver is no longer available';
  END IF;

  SELECT * INTO v_cfg FROM pricing_versions WHERE id = v_request.pricing_version_id;
  IF v_cfg.id IS NULL THEN v_cfg := public.active_pricing(); END IF;
  v_comm := public.commission_for(v_cfg.config, v_request.vehicle, v_offer.price);

  INSERT INTO rides (request_id, passenger_id, driver_id, vehicle, fare,
                     pickup_label, pickup_lat, pickup_lng, dest_label, dest_lat, dest_lng,
                     estimated_fare, commission, driver_net, distance_km, pricing_version_id, pricing_snapshot, city)
  VALUES (v_request.id, v_request.passenger_id, v_offer.driver_id, v_request.vehicle, v_offer.price,
          v_request.pickup_label, v_request.pickup_lat, v_request.pickup_lng,
          v_request.dest_label, v_request.dest_lat, v_request.dest_lng,
          v_request.estimated_fare, v_comm, v_offer.price - v_comm, v_request.distance_km, v_cfg.id,
          jsonb_build_object('version', v_cfg.version, 'commission', v_cfg.config->'commission',
                             'vehicle', v_cfg.config->'vehicles'->v_request.vehicle,
                             'negotiation', v_cfg.config->'negotiation'),
          v_request.city)
  RETURNING id INTO v_ride_id;

  UPDATE offers SET status = 'accepted' WHERE id = p_offer_id;
  UPDATE offers SET status = 'declined' WHERE request_id = v_request.id AND id <> p_offer_id AND status = 'pending';
  UPDATE ride_requests SET status = 'accepted' WHERE id = v_request.id;

  INSERT INTO ride_messages (request_id, sender_id, body)
  VALUES (v_request.id, auth.uid(), 'OFFRE_ACCEPTEE:' || v_offer.price::text);

  RETURN v_ride_id;
END;
$$;

-- Driver advances the ride through valid transitions only.
CREATE OR REPLACE FUNCTION public.update_ride(p_ride_id uuid, p_status text) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_ride rides;
  v_label text;
BEGIN
  PERFORM public.assert_active_user();
  SELECT * INTO v_ride FROM rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;
  IF v_ride.driver_id <> auth.uid() THEN RAISE EXCEPTION 'Only the driver can update the ride'; END IF;
  IF NOT (
    (v_ride.status = 'en_route' AND p_status IN ('arrived','cancelled')) OR
    (v_ride.status = 'arrived' AND p_status IN ('started','cancelled')) OR
    (v_ride.status = 'started' AND p_status = 'completed')
  ) THEN
    RAISE EXCEPTION 'Invalid status transition % -> %', v_ride.status, p_status;
  END IF;

  UPDATE rides SET
    status = p_status,
    started_at = CASE WHEN p_status = 'started' THEN now() ELSE started_at END,
    completed_at = CASE WHEN p_status = 'completed' THEN now() ELSE completed_at END,
    cancelled_by = CASE WHEN p_status = 'cancelled' THEN auth.uid() ELSE cancelled_by END,
    cancel_reason = CASE WHEN p_status = 'cancelled' THEN coalesce(cancel_reason, 'Annulée par le chauffeur') ELSE cancel_reason END
  WHERE id = p_ride_id;

  IF p_status = 'completed' THEN
    v_label := 'Course ' || v_ride.pickup_label || ' → ' || v_ride.dest_label;
    INSERT INTO transactions (user_id, ride_id, kind, amount, method, label)
    VALUES (v_ride.passenger_id, v_ride.id, 'payment', -v_ride.fare, 'cash', v_label);
    INSERT INTO transactions (user_id, ride_id, kind, amount, method, label)
    VALUES (v_ride.driver_id, v_ride.id, 'earning', v_ride.fare, 'cash', v_label);
    IF coalesce(v_ride.commission, 0) > 0 THEN
      INSERT INTO transactions (user_id, ride_id, kind, amount, method, label)
      VALUES (v_ride.driver_id, v_ride.id, 'commission', -v_ride.commission, 'cash', 'Commission KHERJA');
    END IF;
    UPDATE profiles SET trips_count = trips_count + 1 WHERE id IN (v_ride.passenger_id, v_ride.driver_id);
  END IF;

  IF p_status = 'cancelled' THEN
    UPDATE ride_requests SET status = 'cancelled' WHERE id = v_ride.request_id AND status = 'accepted';
  END IF;
END;
$$;

-- Passenger or driver cancels before the ride starts, with a reason.
CREATE OR REPLACE FUNCTION public.cancel_ride(p_ride_id uuid, p_reason text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_ride rides;
BEGIN
  PERFORM public.assert_active_user();
  SELECT * INTO v_ride FROM rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;
  IF auth.uid() NOT IN (v_ride.passenger_id, v_ride.driver_id) THEN RAISE EXCEPTION 'Not a ride participant'; END IF;
  IF v_ride.status NOT IN ('en_route','arrived') THEN RAISE EXCEPTION 'Ride can no longer be cancelled'; END IF;
  UPDATE rides SET status = 'cancelled', cancelled_by = auth.uid(),
    cancel_reason = left(coalesce(nullif(p_reason, ''), CASE WHEN auth.uid() = v_ride.passenger_id THEN 'Annulée par le passager' ELSE 'Annulée par le chauffeur' END), 300)
  WHERE id = p_ride_id;
  UPDATE ride_requests SET status = 'cancelled' WHERE id = v_ride.request_id AND status = 'accepted';
END;
$$;

-- Driver location ping (live tracking).
CREATE OR REPLACE FUNCTION public.ping_location(p_lat double precision, p_lng double precision) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public.assert_active_user();
  IF p_lat NOT BETWEEN -90 AND 90 OR p_lng NOT BETWEEN -180 AND 180 THEN RAISE EXCEPTION 'Invalid coordinates'; END IF;
  UPDATE profiles SET current_lat = p_lat, current_lng = p_lng, location_updated_at = now() WHERE id = auth.uid();
END;
$$;

-- ==================== admin RPCs ====================
CREATE OR REPLACE FUNCTION public.admin_me() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v admin_users;
BEGIN
  SELECT * INTO v FROM admin_users WHERE user_id = auth.uid() AND active;
  IF v.user_id IS NULL THEN RETURN NULL; END IF;
  RETURN jsonb_build_object(
    'user_id', v.user_id,
    'role', v.role_code,
    'display_name', v.display_name,
    'email', v.email,
    'permissions', (SELECT coalesce(jsonb_agg(permission_code), '[]'::jsonb) FROM admin_role_permissions WHERE role_code = v.role_code)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_driver_status(p_user uuid, p_status text, p_reason text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_before profiles;
BEGIN
  PERFORM public.require_perm('drivers.approve');
  IF p_status NOT IN ('approved','rejected','pending') THEN RAISE EXCEPTION 'Invalid status'; END IF;
  SELECT * INTO v_before FROM profiles WHERE id = p_user FOR UPDATE;
  IF v_before.id IS NULL OR v_before.role <> 'driver' THEN RAISE EXCEPTION 'Driver not found'; END IF;
  IF p_status = 'rejected' AND coalesce(trim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required'; END IF;
  UPDATE profiles SET driver_status = p_status, status_reason = p_reason,
    is_online = CASE WHEN p_status = 'approved' THEN is_online ELSE false END
  WHERE id = p_user;
  PERFORM public.write_audit('driver.' || p_status, 'profile', p_user::text,
    jsonb_build_object('driver_status', v_before.driver_status), jsonb_build_object('driver_status', p_status), p_reason);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_account_status(p_user uuid, p_status text, p_reason text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_before profiles;
BEGIN
  SELECT * INTO v_before FROM profiles WHERE id = p_user FOR UPDATE;
  IF v_before.id IS NULL THEN RAISE EXCEPTION 'User not found'; END IF;
  PERFORM public.require_perm(CASE WHEN v_before.role = 'driver' THEN 'drivers.manage' ELSE 'users.manage' END);
  IF p_status NOT IN ('active','suspended') THEN RAISE EXCEPTION 'Invalid status'; END IF;
  IF p_status = 'suspended' AND coalesce(trim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required'; END IF;
  UPDATE profiles SET account_status = p_status, status_reason = p_reason,
    is_online = CASE WHEN p_status = 'suspended' THEN false ELSE is_online END
  WHERE id = p_user;
  IF p_status = 'suspended' THEN
    UPDATE ride_requests SET status = 'cancelled' WHERE passenger_id = p_user AND status IN ('open','negotiating');
    UPDATE offers SET status = 'declined' WHERE driver_id = p_user AND status = 'pending';
  END IF;
  PERFORM public.write_audit('account.' || p_status, 'profile', p_user::text,
    jsonb_build_object('account_status', v_before.account_status), jsonb_build_object('account_status', p_status), p_reason);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_save_pricing(
  p_config jsonb, p_publish boolean DEFAULT false, p_effective_at timestamptz DEFAULT NULL, p_note text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_prev pricing_versions;
BEGIN
  PERFORM public.require_perm('pricing.manage');
  PERFORM public.validate_pricing(p_config);
  IF p_publish AND p_effective_at IS NOT NULL AND p_effective_at < now() - interval '5 minutes' THEN
    RAISE EXCEPTION 'Effective date cannot be in the past';
  END IF;
  v_prev := public.active_pricing();
  INSERT INTO pricing_versions (config, status, effective_at, note, created_by, published_by, published_at)
  VALUES (p_config,
          CASE WHEN p_publish THEN 'published' ELSE 'draft' END,
          CASE WHEN p_publish THEN coalesce(p_effective_at, now()) END,
          left(p_note, 500), auth.uid(),
          CASE WHEN p_publish THEN auth.uid() END,
          CASE WHEN p_publish THEN now() END)
  RETURNING id INTO v_id;
  PERFORM public.write_audit(CASE WHEN p_publish THEN 'pricing.publish' ELSE 'pricing.draft' END,
    'pricing_version', v_id::text, v_prev.config, p_config, p_note);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_publish_pricing(p_id uuid, p_effective_at timestamptz DEFAULT NULL) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v pricing_versions;
  v_prev pricing_versions;
BEGIN
  PERFORM public.require_perm('pricing.manage');
  SELECT * INTO v FROM pricing_versions WHERE id = p_id FOR UPDATE;
  IF v.id IS NULL OR v.status <> 'draft' THEN RAISE EXCEPTION 'Draft not found'; END IF;
  PERFORM public.validate_pricing(v.config);
  v_prev := public.active_pricing();
  UPDATE pricing_versions SET status = 'published', effective_at = coalesce(p_effective_at, now()),
    published_by = auth.uid(), published_at = now()
  WHERE id = p_id;
  PERFORM public.write_audit('pricing.publish', 'pricing_version', p_id::text, v_prev.config, v.config, v.note);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_restore_pricing(p_id uuid, p_note text DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v pricing_versions;
  v_prev pricing_versions;
  v_id uuid;
BEGIN
  PERFORM public.require_perm('pricing.manage');
  SELECT * INTO v FROM pricing_versions WHERE id = p_id;
  IF v.id IS NULL THEN RAISE EXCEPTION 'Version not found'; END IF;
  PERFORM public.validate_pricing(v.config);
  v_prev := public.active_pricing();
  INSERT INTO pricing_versions (config, status, effective_at, note, restored_from, created_by, published_by, published_at)
  VALUES (v.config, 'published', now(), coalesce(p_note, 'Restauration de la version ' || v.version), v.id, auth.uid(), auth.uid(), now())
  RETURNING id INTO v_id;
  PERFORM public.write_audit('pricing.restore', 'pricing_version', v_id::text, v_prev.config, v.config, p_note);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_cancel_scheduled_pricing(p_id uuid) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v pricing_versions;
BEGIN
  PERFORM public.require_perm('pricing.manage');
  SELECT * INTO v FROM pricing_versions WHERE id = p_id FOR UPDATE;
  IF v.id IS NULL OR v.status <> 'published' OR v.effective_at <= now() THEN
    RAISE EXCEPTION 'Only a scheduled (future) version can be cancelled';
  END IF;
  UPDATE pricing_versions SET status = 'archived' WHERE id = p_id;
  PERFORM public.write_audit('pricing.unschedule', 'pricing_version', p_id::text, NULL, NULL, NULL);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_simulate_fare(
  p_config jsonb, p_distance numeric, p_vehicle text, p_city text, p_at timestamptz,
  p_commission_pct numeric DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_cfg jsonb := p_config;
BEGIN
  PERFORM public.require_perm('pricing.read');
  IF v_cfg IS NULL THEN v_cfg := (public.active_pricing()).config; END IF;
  PERFORM public.validate_pricing(v_cfg);
  IF p_distance IS NULL OR p_distance <= 0 OR p_distance > 500 THEN RAISE EXCEPTION 'Distance invalide'; END IF;
  IF p_commission_pct IS NOT NULL AND (p_commission_pct < 0 OR p_commission_pct > 50) THEN RAISE EXCEPTION 'Commission invalide'; END IF;
  RETURN public.compute_fare(v_cfg, p_distance, p_vehicle, coalesce(p_city, 'Alger'), coalesce(p_at, now()), p_commission_pct);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_cancel_ride(p_ride_id uuid, p_reason text) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v rides;
BEGIN
  PERFORM public.require_perm('rides.manage');
  IF coalesce(trim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required'; END IF;
  SELECT * INTO v FROM rides WHERE id = p_ride_id FOR UPDATE;
  IF v.id IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;
  IF v.status IN ('completed','cancelled') THEN RAISE EXCEPTION 'Ride already closed'; END IF;
  UPDATE rides SET status = 'cancelled', cancelled_by = NULL, cancel_reason = left('Admin: ' || p_reason, 300) WHERE id = p_ride_id;
  UPDATE ride_requests SET status = 'cancelled' WHERE id = v.request_id AND status = 'accepted';
  PERFORM public.write_audit('ride.cancel', 'ride', p_ride_id::text, jsonb_build_object('status', v.status), jsonb_build_object('status','cancelled'), p_reason);
END;
$$;

-- Refund / adjustment on a completed ride (positive amount credited to the passenger).
CREATE OR REPLACE FUNCTION public.admin_adjust_ride(p_ride_id uuid, p_amount integer, p_reason text) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v rides;
BEGIN
  PERFORM public.require_perm('finance.adjust');
  IF coalesce(trim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required'; END IF;
  SELECT * INTO v FROM rides WHERE id = p_ride_id;
  IF v.id IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;
  IF v.status <> 'completed' THEN RAISE EXCEPTION 'Only completed rides can be adjusted'; END IF;
  IF p_amount = 0 OR abs(p_amount) > v.fare THEN RAISE EXCEPTION 'Amount out of range'; END IF;
  INSERT INTO transactions (user_id, ride_id, kind, amount, method, label, created_by)
  VALUES (v.passenger_id, v.id, CASE WHEN p_amount > 0 THEN 'refund' ELSE 'adjustment' END, p_amount, 'cash',
          left('Ajustement: ' || p_reason, 200), auth.uid());
  PERFORM public.write_audit('ride.adjust', 'ride', p_ride_id::text, NULL, jsonb_build_object('amount', p_amount), p_reason);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_admin(p_email text, p_role text, p_active boolean DEFAULT true, p_display_name text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid;
  v_before admin_users;
BEGIN
  PERFORM public.require_perm('admins.manage');
  IF NOT EXISTS (SELECT 1 FROM admin_roles WHERE code = p_role) THEN RAISE EXCEPTION 'Unknown role'; END IF;
  SELECT id INTO v_uid FROM auth.users WHERE lower(email) = lower(trim(p_email));
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No account with this email'; END IF;
  IF v_uid = auth.uid() AND (NOT p_active OR p_role <> 'super_admin') THEN
    RAISE EXCEPTION 'You cannot demote or deactivate yourself';
  END IF;
  SELECT * INTO v_before FROM admin_users WHERE user_id = v_uid;
  INSERT INTO admin_users (user_id, role_code, display_name, email, active, created_by)
  VALUES (v_uid, p_role, coalesce(p_display_name, split_part(p_email, '@', 1)), lower(trim(p_email)), p_active, auth.uid())
  ON CONFLICT (user_id) DO UPDATE SET role_code = excluded.role_code, active = excluded.active,
    display_name = coalesce(p_display_name, admin_users.display_name);
  PERFORM public.write_audit('admin.set', 'admin_user', v_uid::text, to_jsonb(v_before),
    jsonb_build_object('role', p_role, 'active', p_active), NULL);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_overview(p_from timestamptz, p_to timestamptz) RETURNS jsonb
LANGUAGE plpgsql STABLE
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v jsonb;
BEGIN
  PERFORM public.require_perm('overview.read');
  SELECT jsonb_build_object(
    'passengers', (SELECT count(*) FROM profiles WHERE role = 'passenger'),
    'drivers', (SELECT count(*) FROM profiles WHERE role = 'driver'),
    'drivers_online', (SELECT count(*) FROM profiles WHERE role = 'driver' AND is_online),
    'drivers_pending', (SELECT count(*) FROM profiles WHERE role = 'driver' AND driver_status = 'pending'),
    'suspended', (SELECT count(*) FROM profiles WHERE account_status = 'suspended'),
    'open_requests', (SELECT count(*) FROM ride_requests WHERE status IN ('open','negotiating') AND expires_at > now()),
    'active_rides', (SELECT count(*) FROM rides WHERE status IN ('en_route','arrived','started')),
    'completed', (SELECT count(*) FROM rides WHERE status = 'completed' AND created_at BETWEEN p_from AND p_to),
    'cancelled', (SELECT count(*) FROM rides WHERE status = 'cancelled' AND created_at BETWEEN p_from AND p_to),
    'requests', (SELECT count(*) FROM ride_requests WHERE created_at BETWEEN p_from AND p_to),
    'gross', (SELECT coalesce(sum(fare), 0) FROM rides WHERE status = 'completed' AND completed_at BETWEEN p_from AND p_to),
    'commission', (SELECT coalesce(sum(commission), 0) FROM rides WHERE status = 'completed' AND completed_at BETWEEN p_from AND p_to),
    'driver_net', (SELECT coalesce(sum(driver_net), 0) FROM rides WHERE status = 'completed' AND completed_at BETWEEN p_from AND p_to),
    'refunds', (SELECT coalesce(sum(amount), 0) FROM transactions WHERE kind = 'refund' AND created_at BETWEEN p_from AND p_to),
    'avg_fare', (SELECT coalesce(round(avg(fare)), 0) FROM rides WHERE status = 'completed' AND completed_at BETWEEN p_from AND p_to),
    'by_vehicle', (SELECT coalesce(jsonb_object_agg(vehicle, n), '{}'::jsonb) FROM (
        SELECT vehicle, count(*) n FROM rides WHERE created_at BETWEEN p_from AND p_to GROUP BY vehicle) t),
    'series', (SELECT coalesce(jsonb_agg(jsonb_build_object('day', d, 'rides', coalesce(r.n, 0), 'gross', coalesce(r.g, 0), 'commission', coalesce(r.c, 0)) ORDER BY d), '[]'::jsonb)
      FROM generate_series(date_trunc('day', p_from AT TIME ZONE 'Africa/Algiers'), date_trunc('day', p_to AT TIME ZONE 'Africa/Algiers'), interval '1 day') AS gs(d)
      LEFT JOIN (
        SELECT date_trunc('day', completed_at AT TIME ZONE 'Africa/Algiers') AS dday, count(*) AS n, sum(fare) AS g, sum(commission) AS c
        FROM rides WHERE status = 'completed' AND completed_at BETWEEN p_from AND p_to GROUP BY 1
      ) r ON r.dday = gs.d)
  ) INTO v;
  RETURN v;
END;
$$;

-- ==================== realtime ====================
DO $$
DECLARE
  t text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    FOREACH t IN ARRAY ARRAY['rides','ride_requests','offers','ride_messages','profiles'] LOOP
      IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t) THEN
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
      END IF;
    END LOOP;
  END IF;
END $$;
