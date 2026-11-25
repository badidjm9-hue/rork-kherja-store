import { describe, expect, test } from "bun:test";
import { isBlocked, normalizeEmail, safeEqual, validatePassword } from "./password.ts";
import { decideOtpDelivery, decidePurpose, devOtpAllowed, parsePurpose, resolveRuntimeEnv } from "./policy.ts";
import { displayPhone, emailForPhone, normalizePhone } from "./phone.ts";

const env = (m: Record<string, string>) => (k: string) => m[k];

describe("validatePassword", () => {
  test("accepts letters + digits of valid length", () => {
    expect(validatePassword("kherja2026")).toBeNull();
    expect(validatePassword("مرحبا12345")).toBeNull();
    expect(validatePassword("أ".repeat(35) + "a1")).toBeNull(); // 72 UTF-8 bytes
  });
  test("rejects short, letters-only, digits-only, too long, non-string and Arabic punctuation", () => {
    expect(validatePassword("ab1")).not.toBeNull();
    expect(validatePassword("onlyletters")).not.toBeNull();
    expect(validatePassword("12345678")).not.toBeNull();
    expect(validatePassword("a1".repeat(40))).not.toBeNull();
    expect(validatePassword("أ".repeat(36) + "1")).not.toBeNull(); // 73 UTF-8 bytes
    expect(validatePassword("،".repeat(7) + "1")).not.toBeNull(); // punctuation is not a letter
    expect(validatePassword(undefined)).not.toBeNull();
    expect(validatePassword(12345678)).not.toBeNull();
  });
});

describe("normalizeEmail", () => {
  test("absent -> empty; valid -> trimmed lowercase; malformed -> null", () => {
    expect(normalizeEmail(undefined)).toBe("");
    expect(normalizeEmail("")).toBe("");
    expect(normalizeEmail("  Mohamed@Gmail.com ")).toBe("mohamed@gmail.com");
    expect(normalizeEmail("not-an-email")).toBeNull();
    expect(normalizeEmail("a@b")).toBeNull();
    expect(normalizeEmail(42)).toBeNull();
  });
});

describe("rate-limit helpers", () => {
  test("isBlocked at five failures", () => {
    expect(isBlocked(4)).toBe(false);
    expect(isBlocked(5)).toBe(true);
  });
  test("safeEqual", () => {
    expect(safeEqual("123456", "123456")).toBe(true);
    expect(safeEqual("123456", "123457")).toBe(false);
    expect(safeEqual("123456", "12345")).toBe(false);
  });
});

describe("runtime environment (fail closed)", () => {
  test("only the exact string 'development' is development", () => {
    expect(resolveRuntimeEnv(env({ KHERJA_ENV: "development" }))).toBe("development");
    for (const v of [undefined, "", "production", "prod", "dev", "Development", "DEVELOPMENT", " development", "staging", "true"]) {
      expect(resolveRuntimeEnv(env(v === undefined ? {} : { KHERJA_ENV: v }))).toBe("production");
    }
  });
  test("dev OTP needs development AND ALLOW_DEV_OTP=true", () => {
    expect(devOtpAllowed(env({ KHERJA_ENV: "development", ALLOW_DEV_OTP: "true" }))).toBe(true);
    expect(devOtpAllowed(env({ KHERJA_ENV: "development" }))).toBe(false);
    expect(devOtpAllowed(env({ KHERJA_ENV: "development", ALLOW_DEV_OTP: "1" }))).toBe(false);
    expect(devOtpAllowed(env({ ALLOW_DEV_OTP: "true" }))).toBe(false);
    expect(devOtpAllowed(env({ KHERJA_ENV: "production", ALLOW_DEV_OTP: "true" }))).toBe(false);
  });
});

describe("decideOtpDelivery: exhaustive truth table", () => {
  test("a dev code is possible in exactly one combination", () => {
    for (const smsSent of [true, false]) {
      for (const devAllowed of [true, false]) {
        const d = decideOtpDelivery({ smsSent, devAllowed });
        expect(d.kind === "dev_code").toBe(!smsSent && devAllowed);
        if (!smsSent && !devAllowed) expect(d).toMatchObject({ kind: "error", status: 503 });
        if (smsSent) expect(d.kind).toBe("sent");
      }
    }
  });
});

describe("purpose decisions", () => {
  test("parsePurpose", () => {
    expect(parsePurpose(undefined)).toBe("login");
    expect(parsePurpose("")).toBe("login");
    expect(parsePurpose("register")).toBe("register");
    expect(parsePurpose("reset")).toBe("reset");
    expect(parsePurpose("admin")).toBeNull();
    expect(parsePurpose(5)).toBeNull();
  });
  test("decidePurpose matrix", () => {
    expect(decidePurpose({ purpose: "login", userExists: false, hasPassword: false })).toEqual({ ok: true });
    expect(decidePurpose({ purpose: "login", userExists: true, hasPassword: true }).ok).toBe(false);
    expect(decidePurpose({ purpose: "register", userExists: false, hasPassword: true })).toEqual({ ok: true });
    expect(decidePurpose({ purpose: "register", userExists: true, hasPassword: true })).toMatchObject({ ok: false, status: 409 });
    expect(decidePurpose({ purpose: "register", userExists: false, hasPassword: false })).toMatchObject({ ok: false, status: 400 });
    expect(decidePurpose({ purpose: "reset", userExists: true, hasPassword: true })).toEqual({ ok: true });
    expect(decidePurpose({ purpose: "reset", userExists: false, hasPassword: true })).toMatchObject({ ok: false, status: 404 });
  });
});

describe("phone helpers (moved verbatim)", () => {
  test("normalizePhone", () => {
    expect(normalizePhone("0555 12 34 56")).toBe("+213555123456");
    expect(normalizePhone("+213555123456")).toBe("+213555123456");
    expect(normalizePhone("213555123456")).toBe("+213555123456");
    expect(normalizePhone("0455123456")).toBeNull();
    expect(normalizePhone("12345")).toBeNull();
  });
  test("displayPhone / emailForPhone", () => {
    expect(displayPhone("+213555123456")).toBe("0555 12 34 56");
    expect(emailForPhone("+213555123456")).toBe("u213555123456@phone.kherja.app");
  });
});
