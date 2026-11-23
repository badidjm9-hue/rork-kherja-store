import type { PricingVersion } from "./supabase";

export interface VehicleCfg {
  enabled: boolean;
  base_fare: number;
  per_km: number;
  min_fare: number;
  max_fare: number;
  rounding: number;
  waiting_per_min: number;
  cancellation_fee: number;
}

export interface PricingConfig {
  currency: string;
  vehicles: { car: VehicleCfg; moto: VehicleCfg };
  modifiers: {
    peak: { enabled: boolean; pct: number; windows: [number, number][] };
    night: { enabled: boolean; pct: number; start_hour: number; end_hour: number };
    weekend: { enabled: boolean; pct: number; days: number[] };
    cap_pct: number;
  };
  promo: { daytime: { enabled: boolean; car_pct: number; moto_pct: number } };
  cities: Record<string, { enabled: boolean; multiplier: number }>;
  commission: {
    method: "percent" | "fixed";
    by_vehicle: { car: number; moto: number };
    fixed_amount: number;
    min_amount: number;
    max_amount: number;
  };
  negotiation: { driver_min_pct: number; driver_max_pct: number; passenger_min_pct: number; passenger_max_pct: number };
  delivery: {
    food: { base_fare: number; per_km: number; min_fare: number };
    parcel: { base_fare: number; per_km: number; min_fare: number };
  };
}

export interface FareResult {
  fare: number;
  price_before_discount: number;
  discount: number;
  distance_km: number;
  vehicle: string;
  city: string;
  hour: number;
  night: boolean;
  peak: boolean;
  weekend: boolean;
  adjustment_pct: number;
  promo_pct: number;
  commission: number;
  driver_net: number;
  commission_method: string;
  applied: { rule: string; label: string; value: number }[];
}

export function cloneConfig(c: unknown): PricingConfig {
  return JSON.parse(JSON.stringify(c)) as PricingConfig;
}

export type VersionState = "active" | "scheduled" | "draft" | "superseded" | "archived";

/** Classifies versions: the active one is the latest published with effective_at <= now. */
export function classify(versions: PricingVersion[], now = Date.now()): Map<string, VersionState> {
  const map = new Map<string, VersionState>();
  const live = versions
    .filter((v) => v.status === "published" && v.effective_at && new Date(v.effective_at).getTime() <= now)
    .sort((a, b) => new Date(b.effective_at!).getTime() - new Date(a.effective_at!).getTime() || b.version - a.version);
  const activeId = live[0]?.id;
  versions.forEach((v) => {
    if (v.id === activeId) map.set(v.id, "active");
    else if (v.status === "draft") map.set(v.id, "draft");
    else if (v.status === "archived") map.set(v.id, "archived");
    else if (v.status === "published" && v.effective_at && new Date(v.effective_at).getTime() > now) map.set(v.id, "scheduled");
    else map.set(v.id, "superseded");
  });
  return map;
}

/** Lists human-readable differences between two configs (dot paths). */
export function diffConfig(a: unknown, b: unknown, path = ""): { path: string; from: unknown; to: unknown }[] {
  if (JSON.stringify(a) === JSON.stringify(b)) return [];
  const isObj = (x: unknown) => typeof x === "object" && x !== null && !Array.isArray(x);
  if (isObj(a) && isObj(b)) {
    const ao = a as Record<string, unknown>;
    const bo = b as Record<string, unknown>;
    const keys = Array.from(new Set([...Object.keys(ao), ...Object.keys(bo)]));
    return keys.flatMap((k) => diffConfig(ao[k], bo[k], path ? `${path}.${k}` : k));
  }
  return [{ path, from: a, to: b }];
}

export const DAY_NAMES_FR = ["Dim", "Lun", "Mar", "Mer", "Jeu", "Ven", "Sam"];
export const DAY_NAMES_AR = ["الأحد", "الإثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"];
