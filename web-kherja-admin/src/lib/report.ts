// Pure helpers for the Reports page (parsing the admin_report_summary JSON and CSV export).

export interface ReportData {
  ridesByStatus: Record<string, number>;
  ridesRevenue: number;
  ridesAvgFare: number;
  deliveriesByStatus: Record<string, number>;
  deliveriesRevenue: number;
  newPassengers: number;
  newDrivers: number;
  activeDrivers: number;
  daily: { day: string; rides: number; revenue: number }[];
  topDrivers: { driverId: string; name: string; trips: number; revenue: number }[];
}

type Obj = Record<string, unknown>;
const n = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : Number(v) || 0);
const counts = (v: unknown): Record<string, number> =>
  Object.fromEntries(Object.entries((v ?? {}) as Obj).map(([k, x]) => [k, n(x)]));

export function parseReport(raw: unknown): ReportData {
  const o = (raw ?? {}) as Obj;
  return {
    ridesByStatus: counts(o.rides_by_status),
    ridesRevenue: n(o.rides_revenue),
    ridesAvgFare: n(o.rides_avg_fare),
    deliveriesByStatus: counts(o.deliveries_by_status),
    deliveriesRevenue: n(o.deliveries_revenue),
    newPassengers: n(o.new_passengers),
    newDrivers: n(o.new_drivers),
    activeDrivers: n(o.active_drivers),
    daily: ((o.daily as Obj[]) ?? []).map((d) => ({ day: String(d.day), rides: n(d.rides), revenue: n(d.revenue) })),
    topDrivers: ((o.top_drivers as Obj[]) ?? []).map((d) => ({
      driverId: String(d.driver_id),
      name: String(d.name ?? ""),
      trips: n(d.trips),
      revenue: n(d.revenue),
    })),
  };
}

export function isoDay(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

/** Neutralises spreadsheet formula injection and quotes fields. */
export function csvCell(v: string | number): string {
  let s = String(v);
  if (/^[=+\-@\t\r]/.test(s)) s = "'" + s;
  return `"${s.replace(/"/g, '""')}"`;
}

export function buildCsv(r: ReportData): string {
  const rows: (string | number)[][] = [["day", "rides", "revenue_da"]];
  for (const d of r.daily) rows.push([d.day, d.rides, d.revenue]);
  rows.push([], ["metric", "value"]);
  rows.push(["rides_revenue_da", r.ridesRevenue], ["rides_avg_fare_da", r.ridesAvgFare], ["deliveries_revenue_da", r.deliveriesRevenue]);
  rows.push(["new_passengers", r.newPassengers], ["new_drivers", r.newDrivers], ["active_drivers", r.activeDrivers]);
  for (const [k, v] of Object.entries(r.ridesByStatus)) rows.push([`rides_${k}`, v]);
  for (const [k, v] of Object.entries(r.deliveriesByStatus)) rows.push([`deliveries_${k}`, v]);
  rows.push([], ["driver", "trips", "revenue_da"]);
  for (const d of r.topDrivers) rows.push([d.name || d.driverId, d.trips, d.revenue]);
  return rows.map((row) => row.map(csvCell).join(",")).join("\r\n");
}
