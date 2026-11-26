import { describe, expect, it } from "vitest";

import { DOC_TYPES, deliveryStatus, docTypeLabel } from "./labels";

// Picks the French or Arabic string like the app's i18n `t` helper.
const fr = (f: string) => f;
const ar = (_f: string, a: string) => a;

describe("deliveryStatus", () => {
  const known = ["open", "accepted", "picked_up", "delivered", "cancelled", "expired"];

  it("labels every delivery status the database can produce, in French and Arabic", () => {
    for (const s of known) {
      const f = deliveryStatus(fr, s);
      const a = deliveryStatus(ar, s);
      expect(f.label).not.toBe(s);
      expect(a.label).not.toBe(s);
      expect(f.label).not.toBe(a.label);
    }
  });

  it("uses a success tone only for delivered and an error tone only for cancelled", () => {
    expect(deliveryStatus(fr, "delivered").tone).toBe("green");
    expect(deliveryStatus(fr, "cancelled").tone).toBe("red");
    for (const s of known.filter((x) => x !== "delivered")) expect(deliveryStatus(fr, s).tone).not.toBe("green");
  });

  it("falls back to the raw status with a neutral tone for unknown values", () => {
    expect(deliveryStatus(fr, "weird")).toEqual({ label: "weird", tone: "gray" });
  });
});

describe("driver documents", () => {
  it("lists exactly the five document types required_driver_documents() returns in the database", () => {
    expect([...DOC_TYPES]).toEqual(["id_card", "license", "registration", "insurance", "vehicle_photo"]);
  });

  it("has a distinct French and Arabic label for every document type", () => {
    for (const d of DOC_TYPES) {
      expect(docTypeLabel(fr, d)).not.toBe(d);
      expect(docTypeLabel(ar, d)).not.toBe(docTypeLabel(fr, d));
    }
    expect(docTypeLabel(fr, "unknown")).toBe("unknown");
  });
});
