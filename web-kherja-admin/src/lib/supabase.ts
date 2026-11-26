import { createClient } from "@supabase/supabase-js";
import type { Database, Tables } from "./database.types";

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;

export const supabaseConfigured = Boolean(url && anonKey);

export const supabase = createClient<Database>(url ?? "https://invalid.supabase.co", anonKey ?? "missing", {
  auth: { persistSession: true, autoRefreshToken: true, storageKey: "kherja-admin-auth" },
});

export type Profile = Tables<"profiles">;
export type Ride = Tables<"rides">;
export type RideRequest = Tables<"ride_requests">;
export type Offer = Tables<"offers">;
export type PricingVersion = Tables<"pricing_versions">;
export type AuditLog = Tables<"audit_logs">;
export type AdminUser = Tables<"admin_users">;
export type AdminRole = Tables<"admin_roles">;
export type DeliveryOrder = Tables<"delivery_orders">;
export type Vehicle = Tables<"vehicles">;
export type SupportTicket = Tables<"support_tickets">;
export type SosAlert = Tables<"sos_alerts">;
export type Broadcast = Tables<"notification_broadcasts">;
export type AppSetting = Tables<"app_settings">;
export type DriverDocument = Tables<"driver_documents">;
export type Transaction = Tables<"transactions">;
export type RideStatus = Tables<"ride_status_history">;

/** Turns a Supabase/Postgres error into a readable message. */
export function errorMessage(e: unknown): string {
  if (!e) return "Erreur inconnue";
  if (typeof e === "string") return e;
  if (typeof e === "object" && e !== null && "message" in e) return String((e as { message: unknown }).message);
  return String(e);
}

/** Throws when a Supabase call returned an error, returns data otherwise. */
export function must<T>(res: { data: T; error: unknown }): T {
  if (res.error) throw new Error(errorMessage(res.error));
  return res.data;
}
