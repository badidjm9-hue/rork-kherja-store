import type { PricingVersion } from "./supabase";
import { classify, cloneConfig, diffConfig } from "./pricing";

function version(
  id: string,
  status: string,
  effectiveAt: string | null,
  versionNumber: number,
): PricingVersion {
  return {
    id,
    status,
    effective_at: effectiveAt,
    version: versionNumber,
    config: {},
    created_at: "2026-11-26T00:00:00Z",
    created_by: null,
    note: null,
    published_at: null,
    published_by: null,
    restored_from: null,
  };
}

describe("pricing version classification", () => {
  it("selects the latest effective published version and classifies the rest", () => {
    const now = Date.parse("2026-11-26T12:00:00Z");
    const versions = [
      version("old", "published", "2026-11-25T12:00:00Z", 1),
      version("active", "published", "2026-11-26T10:00:00Z", 2),
      version("same-time-higher-version", "published", "2026-11-26T10:00:00Z", 3),
      version("future", "published", "2026-11-27T12:00:00Z", 4),
      version("draft", "draft", null, 5),
      version("archived", "archived", null, 6),
    ];

    expect(Object.fromEntries(classify(versions, now))).toEqual({
      old: "superseded",
      active: "superseded",
      "same-time-higher-version": "active",
      future: "scheduled",
      draft: "draft",
      archived: "archived",
    });
  });
});

describe("pricing configuration helpers", () => {
  it("reports nested changes and treats arrays as values", () => {
    expect(
      diffConfig(
        { commission: { by_vehicle: { car: 15 } }, days: [1, 2] },
        { commission: { by_vehicle: { car: 18 } }, days: [1, 2, 3] },
      ),
    ).toEqual([
      { path: "commission.by_vehicle.car", from: 15, to: 18 },
      { path: "days", from: [1, 2], to: [1, 2, 3] },
    ]);
  });

  it("clones a config so edits do not mutate the source", () => {
    const source = { vehicles: { car: { min_fare: 300 } } };
    const clone = cloneConfig(source);

    clone.vehicles.car.min_fare = 450;

    expect(source.vehicles.car.min_fare).toBe(300);
    expect(clone.vehicles.car.min_fare).toBe(450);
  });
});
