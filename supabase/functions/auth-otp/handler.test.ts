import { afterEach, beforeEach, describe, expect, spyOn, test } from "bun:test";
import { createHandler, type AttemptKind, type Deps, type SessionTokens, type Store } from "./handler.ts";

const PHONE = "0555123456";
const E164 = "+213555123456";
const EMAIL = "u213555123456@phone.kherja.app";
const SECRET_PW = "Sup3rSecretPw-do-not-leak";

function fakeStore() {
  const attempts: { id: number; phone: string; kind: AttemptKind; success: boolean; at: number; ipHash: string }[] = [];
  let nextAttemptId = 1;
  const otps = new Map<string, { code_hash: string; expires_at: string }>();
  const users = new Map<string, { id: string; password?: string; meta: Record<string, unknown> }>();
  let clock = 1_700_000_000_000;
  const calls: { updateUser: { password?: string; contactEmail?: string }[] } = { updateUser: [] };

  const session = (id: string): SessionTokens => ({
    access_token: "access." + id, refresh_token: "refresh." + id, expires_in: 3600, user_id: id,
  });

  const store: Store = {
    async reserveAttempt(phone, kind, windowSeconds, phoneLimit, failuresOnly, ipHash, ipLimit) {
      const since = clock - windowSeconds * 1000;
      const phoneCount = attempts.filter((a) =>
        a.phone === phone && a.kind === kind && a.at >= since && (!failuresOnly || !a.success)
      ).length;
      const ipCount = attempts.filter((a) => a.ipHash === ipHash && a.kind === kind && a.at >= since).length;
      if (phoneCount >= phoneLimit || ipCount >= ipLimit) return null;
      const id = nextAttemptId++;
      attempts.push({ id, phone, kind, success: false, at: clock, ipHash });
      return id;
    },
    async finishAttempt(id, success) {
      const attempt = attempts.find((a) => a.id === id);
      if (!attempt) throw new Error("attempt not found");
      attempt.success = success;
    },
    async saveOtp(phone, code_hash, expires_at) { otps.set(phone, { code_hash, expires_at }); },
    async getOtp(phone) { return otps.get(phone) ?? null; },
    async consumeOtp(phone, codeHash) {
      const row = otps.get(phone);
      if (!row || row.code_hash !== codeHash || new Date(row.expires_at).getTime() <= clock) return false;
      otps.delete(phone);
      return true;
    },
    async deleteOtp(phone) { otps.delete(phone); },
    async findUserIdByEmail(email) { return users.get(email)?.id ?? null; },
    async createUser(email, meta) {
      const id = "user-" + (users.size + 1);
      users.set(email, { id, meta });
      return id;
    },
    async updateUser(userId, changes) {
      calls.updateUser.push(changes);
      for (const u of users.values()) if (u.id === userId) {
        if (changes.password) u.password = changes.password;
        if (changes.contactEmail) u.meta.contact_email = changes.contactEmail;
      }
      return true;
    },
    async mintSession(_email, userId) { return session(userId); },
    async passwordSession(email, password) {
      const u = users.get(email);
      return u && u.password === password ? session(u.id) : null;
    },
  };
  return { store, attempts, otps, users, calls, advance: (ms: number) => { clock += ms; }, now: () => clock };
}

function setup(env: Record<string, string> = {}, smsResult = true, code = "123456") {
  const f = fakeStore();
  const sent: { phone: string; code: string }[] = [];
  const runtimeEnv: Record<string, string> = {
    OTP_HASH_SECRET: "test-only-secret-with-at-least-32-characters",
    ...env,
  };
  const deps: Deps = {
    env: (k) => runtimeEnv[k],
    now: f.now,
    generateCode: () => code,
    sendSms: async (phone, c) => { sent.push({ phone, code: c }); return smsResult; },
    store: f.store,
  };
  const handle = createHandler(deps);
  const call = async (body: unknown, headers: Record<string, string> = {}) => {
    const res = await handle(new Request("https://x.test/auth-otp", {
      method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": "203.0.113.10", ...headers }, body: JSON.stringify(body),
    }));
    const text = await res.text();
    return { status: res.status, text, json: JSON.parse(text) };
  };
  return { ...f, sent, call };
}

let logs: string[] = [];
let spies: ReturnType<typeof spyOn>[] = [];
beforeEach(() => {
  logs = [];
  spies = (["log", "error", "warn", "info", "debug"] as const).map((m) =>
    spyOn(console, m).mockImplementation((...a: unknown[]) => { logs.push(a.map(String).join(" ")); }));
});
afterEach(() => spies.forEach((s) => s.mockRestore()));

describe("production can never expose a verification code", () => {
  const productionEnvs: [string, Record<string, string>][] = [
    ["no env at all", {}],
    ["KHERJA_ENV=production", { KHERJA_ENV: "production" }],
    ["ALLOW_DEV_OTP=true but env unset", { ALLOW_DEV_OTP: "true" }],
    ["ALLOW_DEV_OTP=true with production", { KHERJA_ENV: "production", ALLOW_DEV_OTP: "true" }],
    ["typo 'dev'", { KHERJA_ENV: "dev", ALLOW_DEV_OTP: "true" }],
    ["wrong case 'Development'", { KHERJA_ENV: "Development", ALLOW_DEV_OTP: "true" }],
    ["development but flag missing", { KHERJA_ENV: "development" }],
    ["development with flag 'yes'", { KHERJA_ENV: "development", ALLOW_DEV_OTP: "yes" }],
  ];

  for (const [name, env] of productionEnvs) {
    test(`SMS unavailable, ${name}: error, code discarded, never in response`, async () => {
      const t = setup(env, false, "987654");
      const r = await t.call({ action: "request", phone: PHONE });
      expect(r.status).toBe(503);
      expect(r.json.ok).toBeUndefined();
      expect(r.json.dev_code ?? null).toBeNull();
      expect(r.text).not.toContain("987654");
      expect(t.otps.has(E164)).toBe(false); // nothing left to guess or leak
    });

    test(`SMS delivered, ${name}: success response carries no code`, async () => {
      const t = setup(env, true, "987654");
      const r = await t.call({ action: "request", phone: PHONE });
      expect(r.status).toBe(200);
      expect(r.json.ok).toBe(true);
      expect(r.json.dev_code).toBeNull();
      expect(r.json.dev).toBeUndefined();
      expect(r.text).not.toContain("987654");
    });
  }

  test("client-controlled fields and headers cannot switch on the dev bypass", async () => {
    const t = setup({}, false, "555111");
    const hostile = {
      action: "request", phone: PHONE,
      dev: true, dev_mode: true, devMode: true, development: true, allow_dev_otp: "true",
      KHERJA_ENV: "development", ALLOW_DEV_OTP: "true", env: "development", debug: true,
    };
    const r = await t.call(hostile, {
      "x-kherja-env": "development", "x-dev": "true", "x-allow-dev-otp": "true", "x-forwarded-host": "localhost",
    });
    expect(r.status).toBe(503);
    expect(r.text).not.toContain("555111");
  });

  test("failed SMS attempts never log the code", async () => {
    const t = setup({}, false, "424242");
    await t.call({ action: "request", phone: PHONE });
    expect(logs.join("\n")).not.toContain("424242");
  });
});

describe("development bypass works only with both server flags", () => {
  test("development + ALLOW_DEV_OTP=true and no SMS returns the code", async () => {
    const t = setup({ KHERJA_ENV: "development", ALLOW_DEV_OTP: "true" }, false, "246810");
    const r = await t.call({ action: "request", phone: PHONE });
    expect(r.status).toBe(200);
    expect(r.json.dev_code).toBe("246810");
    expect(r.json.dev).toBe(true);
  });

  test("development with a working SMS provider still does not return the code", async () => {
    const t = setup({ KHERJA_ENV: "development", ALLOW_DEV_OTP: "true" }, true, "246810");
    const r = await t.call({ action: "request", phone: PHONE });
    expect(r.json.dev_code).toBeNull();
  });
});

describe("OTP hash-at-rest", () => {
  test("stores only a keyed digest, never the six-digit OTP", async () => {
    const t = setup({}, true, "111222");
    const response = await t.call({ action: "request", phone: PHONE });
    expect(response.status).toBe(200);
    const row = t.otps.get(E164);
    expect(row).toBeDefined();
    expect(row?.code_hash).toMatch(/^[a-f0-9]{64}$/);
    expect(row?.code_hash).not.toBe("111222");
    expect(JSON.stringify(row)).not.toContain("111222");
  });
});

describe("OTP request rate limit", () => {
  test("fourth request within five minutes is blocked (limit now actually triggers)", async () => {
    const t = setup({}, true);
    for (let i = 0; i < 3; i++) expect((await t.call({ action: "request", phone: PHONE })).status).toBe(200);
    expect((await t.call({ action: "request", phone: PHONE })).status).toBe(429);
    t.advance(5 * 60 * 1000 + 1);
    expect((await t.call({ action: "request", phone: PHONE })).status).toBe(200);
  });
  test("invalid phone is rejected before any work", async () => {
    const t = setup();
    expect((await t.call({ action: "request", phone: "12345" })).status).toBe(400);
    expect(t.sent.length).toBe(0);
  });
});

describe("verify: legacy OTP login stays compatible", () => {
  test("request then verify creates an account and returns a session (no purpose, no password)", async () => {
    const t = setup({}, true, "111222");
    await t.call({ action: "request", phone: PHONE });
    const r = await t.call({ action: "verify", phone: PHONE, code: "111222" });
    expect(r.status).toBe(200);
    expect(r.json).toMatchObject({ ok: true, is_new: true, user_id: "user-1", access_token: "access.user-1", refresh_token: "refresh.user-1" });
    expect(t.otps.has(E164)).toBe(false);
  });
  test("second login finds the same user (is_new=false)", async () => {
    const t = setup({}, true, "111222");
    await t.call({ action: "request", phone: PHONE });
    await t.call({ action: "verify", phone: PHONE, code: "111222" });
    await t.call({ action: "request", phone: PHONE });
    const r = await t.call({ action: "verify", phone: PHONE, code: "111222" });
    expect(r.json).toMatchObject({ ok: true, is_new: false, user_id: "user-1" });
  });
  test("wrong code, expired code and missing code are rejected", async () => {
    const t = setup({}, true, "111222");
    expect((await t.call({ action: "verify", phone: PHONE, code: "111222" })).status).toBe(400); // none requested
    await t.call({ action: "request", phone: PHONE });
    expect((await t.call({ action: "verify", phone: PHONE, code: "000000" })).json.error).toBe("Code incorrect");
    t.advance(10 * 60 * 1000 + 1);
    expect((await t.call({ action: "verify", phone: PHONE, code: "111222" })).json.error).toContain("expiré");
  });
  test("a code cannot be used twice", async () => {
    const t = setup({}, true, "111222");
    await t.call({ action: "request", phone: PHONE });
    await t.call({ action: "verify", phone: PHONE, code: "111222" });
    expect((await t.call({ action: "verify", phone: PHONE, code: "111222" })).status).toBe(400);
  });
  test("malformed OTP strings are rejected before hashing and do not consume the code", async () => {
    const t = setup({}, true, "111222");
    await t.call({ action: "request", phone: PHONE });
    expect((await t.call({ action: "verify", phone: PHONE, code: "12345" })).status).toBe(400);
    expect(t.otps.has(E164)).toBe(true);
    expect((await t.call({ action: "verify", phone: PHONE, code: "111222" })).status).toBe(200);
  });
  test("non-string code is rejected without crashing", async () => {
    const t = setup({}, true, "111222");
    await t.call({ action: "request", phone: PHONE });
    expect((await t.call({ action: "verify", phone: PHONE, code: 111222 })).status).toBe(400);
  });
  test("unknown action and malformed JSON", async () => {
    const t = setup();
    expect((await t.call({ action: "nope", phone: PHONE })).status).toBe(400);
  });
});

describe("OTP verify brute-force protection", () => {
  test("five wrong codes lock the number even if the sixth guess is correct", async () => {
    const t = setup({}, true, "111222");
    await t.call({ action: "request", phone: PHONE });
    for (let i = 0; i < 5; i++) expect((await t.call({ action: "verify", phone: PHONE, code: "00000" + i })).status).toBe(400);
    const r = await t.call({ action: "verify", phone: PHONE, code: "111222" });
    expect(r.status).toBe(429);
    expect(r.json.access_token).toBeUndefined();
  });
  test("lock expires after the window", async () => {
    const t = setup({}, true, "111222");
    await t.call({ action: "request", phone: PHONE });
    for (let i = 0; i < 5; i++) await t.call({ action: "verify", phone: PHONE, code: "00000" + i });
    t.advance(15 * 60 * 1000 + 1);
    await t.call({ action: "request", phone: PHONE });
    expect((await t.call({ action: "verify", phone: PHONE, code: "111222" })).status).toBe(200);
  });
});

describe("registration (purpose=register)", () => {
  async function requested() { const t = setup({}, true, "111222"); await t.call({ action: "request", phone: PHONE }); return t; }

  test("creates the account, sets the password and contact e-mail, signs in", async () => {
    const t = await requested();
    const r = await t.call({ action: "verify", phone: PHONE, code: "111222", purpose: "register", password: "Kherja2026", email: " Mohamed@Gmail.com " });
    expect(r.status).toBe(200);
    expect(r.json).toMatchObject({ ok: true, is_new: true });
    expect(t.calls.updateUser).toEqual([{ password: "Kherja2026", contactEmail: "mohamed@gmail.com" }]);
    // The new password works for login straight away.
    const login = await t.call({ action: "login", phone: PHONE, password: "Kherja2026" });
    expect(login.status).toBe(200);
    expect(login.json.is_new).toBe(false);
  });
  test("e-mail is optional", async () => {
    const t = await requested();
    const r = await t.call({ action: "verify", phone: PHONE, code: "111222", purpose: "register", password: "Kherja2026" });
    expect(r.status).toBe(200);
    expect(t.calls.updateUser).toEqual([{ password: "Kherja2026", contactEmail: undefined }]);
  });
  test("weak password is rejected WITHOUT burning the code", async () => {
    const t = await requested();
    for (const pw of ["short1", "onlyletters", "12345678", "a1".repeat(40), (String.fromCharCode(0x0623) + "1").repeat(36)]) {
      expect((await t.call({ action: "verify", phone: PHONE, code: "111222", purpose: "register", password: pw })).status).toBe(400);
    }
    expect(t.otps.has(E164)).toBe(true);
    expect((await t.call({ action: "verify", phone: PHONE, code: "111222", purpose: "register", password: "Kherja2026" })).status).toBe(200);
  });
  test("bcrypt UTF-8 byte boundary is enforced", async () => {
    const t = await requested();
    const tooManyUtf8Bytes = (String.fromCharCode(0x0623) + "1").repeat(36);
    expect((await t.call({ action: "verify", phone: PHONE, code: "111222", purpose: "register", password: tooManyUtf8Bytes })).status).toBe(400);
    expect((await t.call({ action: "verify", phone: PHONE, code: "111222", purpose: "register", password: "a1".repeat(36) })).status).toBe(200);
  });
  test("invalid e-mail is rejected without burning the code", async () => {
    const t = await requested();
    const r = await t.call({ action: "verify", phone: PHONE, code: "111222", purpose: "register", password: "Kherja2026", email: "nope" });
    expect(r.status).toBe(400);
    expect(t.otps.has(E164)).toBe(true);
  });
  test("register is refused when the number already has an account, code not burned", async () => {
    const t = await requested();
    await t.call({ action: "verify", phone: PHONE, code: "111222" }); // legacy login creates the account
    await t.call({ action: "request", phone: PHONE });
    const r = await t.call({ action: "verify", phone: PHONE, code: "111222", purpose: "register", password: "Kherja2026" });
    expect(r.status).toBe(409);
    expect(t.otps.has(E164)).toBe(true);
  });
  test("register requires a password", async () => {
    const t = await requested();
    expect((await t.call({ action: "verify", phone: PHONE, code: "111222", purpose: "register" })).status).toBe(400);
  });
  test("unknown purpose is rejected", async () => {
    const t = await requested();
    expect((await t.call({ action: "verify", phone: PHONE, code: "111222", purpose: "admin" })).status).toBe(400);
  });
  test("legacy login purpose refuses a password (cannot silently set one)", async () => {
    const t = await requested();
    const r = await t.call({ action: "verify", phone: PHONE, code: "111222", password: "Kherja2026" });
    expect(r.status).toBe(400);
    expect(t.calls.updateUser.length).toBe(0);
  });
});

describe("password reset (purpose=reset)", () => {
  test("existing account: code proves the phone, password replaced, old one stops working", async () => {
    const t = setup({}, true, "111222");
    await t.call({ action: "request", phone: PHONE });
    await t.call({ action: "verify", phone: PHONE, code: "111222", purpose: "register", password: "OldPass2026" });
    await t.call({ action: "request", phone: PHONE });
    const r = await t.call({ action: "verify", phone: PHONE, code: "111222", purpose: "reset", password: "NewPass2027" });
    expect(r.status).toBe(200);
    expect(r.json.is_new).toBe(false);
    expect((await t.call({ action: "login", phone: PHONE, password: "OldPass2026" })).status).toBe(401);
    expect((await t.call({ action: "login", phone: PHONE, password: "NewPass2027" })).status).toBe(200);
  });
  test("unknown number: 404 and no account is created", async () => {
    const t = setup({}, true, "111222");
    await t.call({ action: "request", phone: PHONE });
    const r = await t.call({ action: "verify", phone: PHONE, code: "111222", purpose: "reset", password: "NewPass2027" });
    expect(r.status).toBe(404);
    expect(t.users.size).toBe(0);
  });
  test("reset needs a valid code: wrong code changes nothing", async () => {
    const t = setup({}, true, "111222");
    await t.call({ action: "request", phone: PHONE });
    await t.call({ action: "verify", phone: PHONE, code: "111222", purpose: "register", password: "OldPass2026" });
    await t.call({ action: "request", phone: PHONE });
    expect((await t.call({ action: "verify", phone: PHONE, code: "999999", purpose: "reset", password: "NewPass2027" })).status).toBe(400);
    expect((await t.call({ action: "login", phone: PHONE, password: "OldPass2026" })).status).toBe(200);
  });
});

describe("password login and rate limiting", () => {
  async function withAccount() {
    const t = setup({}, true, "111222");
    await t.call({ action: "request", phone: PHONE });
    await t.call({ action: "verify", phone: PHONE, code: "111222", purpose: "register", password: "Kherja2026" });
    return t;
  }
  test("correct password signs in", async () => {
    const t = await withAccount();
    const r = await t.call({ action: "login", phone: PHONE, password: "Kherja2026" });
    expect(r.status).toBe(200);
    expect(r.json).toMatchObject({ ok: true, access_token: "access.user-1", refresh_token: "refresh.user-1", is_new: false });
  });
  test("wrong password, unknown number and empty password give the SAME message (no enumeration)", async () => {
    const t = await withAccount();
    const wrong = await t.call({ action: "login", phone: PHONE, password: "nope-nope1" });
    const unknown = await t.call({ action: "login", phone: "0661000000", password: "Kherja2026" });
    const empty = await t.call({ action: "login", phone: PHONE, password: "" });
    const missing = await t.call({ action: "login", phone: PHONE });
    for (const r of [wrong, unknown, empty, missing]) {
      expect(r.status).toBe(401);
      expect(r.json.error).toBe("Numéro ou mot de passe incorrect");
    }
  });
  test("an account created by SMS only (no password) cannot log in with a password", async () => {
    const t = setup({}, true, "111222");
    await t.call({ action: "request", phone: PHONE });
    await t.call({ action: "verify", phone: PHONE, code: "111222" });
    expect((await t.call({ action: "login", phone: PHONE, password: "Kherja2026" })).status).toBe(401);
  });
  test("five failures lock the number, even for the right password; lock expires", async () => {
    const t = await withAccount();
    for (let i = 0; i < 5; i++) expect((await t.call({ action: "login", phone: PHONE, password: "wrong-pass1" })).status).toBe(401);
    const locked = await t.call({ action: "login", phone: PHONE, password: "Kherja2026" });
    expect(locked.status).toBe(429);
    expect(locked.json.access_token).toBeUndefined();
    t.advance(15 * 60 * 1000 + 1);
    expect((await t.call({ action: "login", phone: PHONE, password: "Kherja2026" })).status).toBe(200);
  });
  test("lockout is per phone number", async () => {
    const t = await withAccount();
    for (let i = 0; i < 5; i++) await t.call({ action: "login", phone: PHONE, password: "wrong-pass1" });
    expect((await t.call({ action: "login", phone: "0661000000", password: "x" })).status).toBe(401); // not 429
  });
});


describe("atomic phone and IP rate limits", () => {
  test("concurrent OTP requests cannot exceed the per-phone limit", async () => {
    const t = setup({}, true);
    const results = await Promise.all(
      Array.from({ length: 12 }, () => t.call({ action: "request", phone: PHONE })),
    );
    expect(results.filter((r) => r.status === 200)).toHaveLength(3);
    expect(results.filter((r) => r.status === 429)).toHaveLength(9);
  });

  test("concurrent verification consumes a code only once", async () => {
    const t = setup({}, true, "111222");
    await t.call({ action: "request", phone: PHONE });
    const results = await Promise.all([
      t.call({ action: "verify", phone: PHONE, code: "111222" }),
      t.call({ action: "verify", phone: PHONE, code: "111222" }),
    ]);
    expect(results.filter((r) => r.status === 200)).toHaveLength(1);
    expect(results.filter((r) => r.status === 400)).toHaveLength(1);
  });

  test("IP limit applies across different phone numbers", async () => {
    const t = setup({}, true);
    const results = [];
    for (let i = 0; i < 21; i++) {
      const phone = "0555123" + String(i).padStart(3, "0");
      results.push(await t.call({ action: "request", phone }));
    }
    expect(results.filter((r) => r.status === 200)).toHaveLength(20);
    expect(results[20].status).toBe(429);
  });

  test("missing trusted IP fails closed", async () => {
    const t = setup({}, true);
    const r = await t.call({ action: "request", phone: PHONE }, { "cf-connecting-ip": "" });
    expect(r.status).toBe(500);
    expect(t.sent).toHaveLength(0);
  });

  test("missing OTP hash secret fails closed", async () => {
    const t = setup({ OTP_HASH_SECRET: "" }, true);
    const r = await t.call({ action: "request", phone: PHONE });
    expect(r.status).toBe(500);
    expect(t.sent).toHaveLength(0);
    expect(t.otps.size).toBe(0);
  });
});

describe("passwords and codes never leak", () => {
  test("no password appears in any response body or log line across all flows", async () => {
    const t = setup({}, true, "111222");
    const bodies: string[] = [];
    const collect = async (b: unknown) => { const r = await t.call(b); bodies.push(r.text); return r; };
    await collect({ action: "request", phone: PHONE });
    await collect({ action: "verify", phone: PHONE, code: "111222", purpose: "register", password: SECRET_PW, email: "a@b.co" });
    await collect({ action: "login", phone: PHONE, password: SECRET_PW });
    await collect({ action: "login", phone: PHONE, password: SECRET_PW + "x" });
    await collect({ action: "request", phone: PHONE });
    await collect({ action: "verify", phone: PHONE, code: "111222", purpose: "reset", password: SECRET_PW + "2" });
    expect(bodies.join("\n")).not.toContain(SECRET_PW);
    expect(logs.join("\n")).not.toContain(SECRET_PW);
  });
  test("malformed body: generic error, nothing from the body is logged", async () => {
    const t = setup();
    const res = await createHandler({
      env: () => undefined, now: () => 0, generateCode: () => "000000", sendSms: async () => false, store: t.store,
    })(new Request("https://x.test", { method: "POST", body: `{"password":"${SECRET_PW}",` }));
    expect(res.status).toBe(500);
    expect(await res.text()).not.toContain(SECRET_PW);
    expect(logs.join("\n")).not.toContain(SECRET_PW);
  });
  test("handler only ever hands the password to the store's hashing paths", async () => {
    const t = setup({}, true, "111222");
    await t.call({ action: "request", phone: PHONE });
    await t.call({ action: "verify", phone: PHONE, code: "111222", purpose: "register", password: SECRET_PW });
    // Attempts, OTP rows and user metadata (everything we persist ourselves) contain no password.
    expect(JSON.stringify(t.attempts)).not.toContain(SECRET_PW);
    expect(JSON.stringify([...t.otps])).not.toContain(SECRET_PW);
    expect(JSON.stringify([...t.users.values()].map((u) => u.meta))).not.toContain(SECRET_PW);
  });
});

describe("CORS", () => {
  test("OPTIONS preflight succeeds", async () => {
    const t = setup();
    const res = await createHandler({
      env: () => undefined, now: () => 0, generateCode: () => "000000", sendSms: async () => false, store: t.store,
    })(new Request("https://x.test", { method: "OPTIONS" }));
    expect(res.status).toBe(200);
  });
});
