import { describe, expect, it } from "vitest";
import { buildCsv, csvCell, isoDay, parseReport } from "./report";

describe("report helpers", () => {
  it("parses the RPC JSON and tolerates missing fields", () => {
    const r = parseReport({
      rides_by_status: { completed: 3, cancelled: "1" },
      rides_revenue: 2700,
      daily: [{ day: "2026-11-25", rides: 2, revenue: 1800 }],
      top_drivers: [{ driver_id: "d1", name: "Karim", trips: 3, revenue: 2700 }],
    });
    expect(r.ridesByStatus).toEqual({ completed: 3, cancelled: 1 });
    expect(r.ridesRevenue).toBe(2700);
    expect(r.deliveriesRevenue).toBe(0);
    expect(r.topDrivers[0].name).toBe("Karim");
    expect(parseReport(null).daily).toEqual([]);
  });
  it("formats local ISO days", () => {
    expect(isoDay(new Date(2026, 0, 5))).toBe("2026-01-05");
  });
  it("neutralises CSV formula injection and quotes", () => {
    expect(csvCell('=HYPERLINK("x")')).toBe(`"'=HYPERLINK(""x"")"`);
    expect(csvCell("+1")).toBe(`"'+1"`);
    expect(csvCell("a,b")).toBe('"a,b"');
    expect(csvCell(12)).toBe('"12"');
  });
  it("builds a CSV with daily rows and top drivers", () => {
    const csv = buildCsv(parseReport({ daily: [{ day: "2026-11-25", rides: 2, revenue: 1800 }], top_drivers: [{ driver_id: "d1", name: "=cmd", trips: 1, revenue: 900 }] }));
    expect(csv).toContain('"2026-11-25","2","1800"');
    expect(csv).toContain(`"'=cmd","1","900"`);
  });
});
