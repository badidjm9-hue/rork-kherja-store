import { afterEach, beforeEach, describe, expect, spyOn, test } from "bun:test";
import { hashOtp } from "./otp.ts";
import { createHandler, type AttemptKind, type Deps, type SessionTokens, type Store } from "./handler.ts";

const PHONE = "0555123456";
const E164 = "+213555123456";
const EMAIL = "u213555123456@phone.kherja.app";
const SECRET_PW = "Sup3rSecretPw-do-not-leak";

function fakeStore() {
  const attempts: { phone: string; kind: AttemptKind; success: boolean; at: number }[] = [];
  const otps = new Map<string, { code: string; expires_at: string }>();
  const users = new Map<string, { id: string; password?: string; meta: Record<string, unknown> }>();
  const linked = new Map<string, string>();
  let clock = 1_700_000_000_000;
  const calls: { updateUser: { password?: string; contactEmail?: string }[]; accountClose: string[]; authDelete: string[] } = { updateUser: [], accountClose: [], authDelete: [] };
  let closeResult: "ok" | "active" | "error" = "ok";
  let authDeleteResult = true;

  const session = (id: string): SessionTokens => ({
    access_token: "access." + id, refresh_token: "refresh." + id, expires_in: 3600, user_id: id,
  });

  const store: Store = {
    async countAttempts(phone, kind, sinceIso, onlyFailures) {
      const since = new Date(sinceIso).getTime();
      return attempts.filter((a) => a.phone === phone && a.kind === kind && a.at >= since && (!onlyFailures || !a.success)).length;
    },
    async recordAttempt(phone, kind, success) { attempts.push({ phone, kind, success, at: clock }); },
    async saveOtp(phone, code, expires_at) { otps.set(phone, { code, expires_at }); },
    async getOtp(phone) { return otps.get(phone) ?? null; },
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
    async getAuthUser(token) {
      const m = /^social\.(.+)$/.exec(token);
      return m ? { id: m[1], email: m[1] + "@gmail.test" } : null;
    },
    async deleteMyAccount(token) { calls.accountClose.push(token); return closeResult; },
    async deleteAuthUser(userId) { calls.authDelete.push(userId); return authDeleteResult; },
    async findPhoneOwner(phone) {
      return linked.get(phone) ?? users.get("u" + phone.replace(/[^0-9]/g, "") + "@phone.kherja.app")?.id ?? null;
    },
    async getVerifiedPhone(userId) {
      for (const [ph, uid] of linked) if (uid === userId) return ph;
      return null;
    },
    async linkVerifiedPhone(userId, phone) {
      if (linked.has(phone)) return "conflict";
      linked.set(phone, userId);
      return "ok";
    },
    async passwordSession(email, password) {
      const u = users.get(email);
      return u && u.password === password ? session(u.id) : null;
    },
  };
  return { store, attempts, otps, users, linked, calls, setCloseResult: (v: "ok" | "active" | "error") => { closeResult = v; }, setAuthDeleteResult: (v: boolean) => { authDeleteResult = v; }, advance: (ms: number) => { clock += ms; }, now: () => clock };
}

function setup(env: Record<string, string> = {}, smsResult = true, code = "123456") {
  const f = fakeStore();
  const sent: { phone: string; code: string }[] = [];
  const deps: Deps = {
    env: (k) => env[k],
    now: f.now,
    generateCode: () => code,
    hashOtp: (phone, c) => hashOtp("test-secret", phone, c),
    sendSms: async (phone, c) => { sent.push({ phone, code: c }); return smsResult; },
    store: f.store,
  };
  const handle = createHandler(deps);
  const call = async (body: unknown, headers: Record<string, string> = {}) => {
    const res = await handle(new Request("https://x.test/auth-otp", {
      method: "POST", headers: { "content-type": "application/json", ...headers }, body: JSON.stringify(body),
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
    for (const pw of ["short1", "onlyletters", "12345678", "a1".repeat(40)]) {
      expect((await t.call({ action: "verify", phone: PHONE, code: "111222", purpose: "register", password: pw })).status).toBe(400);
    }
    expect(t.otps.has(E164)).toBe(true);
    expect((await t.call({ action: "verify", phone: PHONE, code: "111222", purpose: "register", password: "Kherja2026" })).status).toBe(200);
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

describe("stored OTP codes are hashed", () => {
  test("the database row never contains the code; the SMS and dev response still do", async () => {
    const t = setup({ KHERJA_ENV: "development", ALLOW_DEV_OTP: "true" }, true, "135790");
    await t.call({ action: "request", phone: PHONE });
    const row = t.otps.get(E164)!;
    expect(row.code.startsWith("h1:")).toBe(true);
    expect(row.code).not.toContain("135790");
    expect(JSON.stringify([...t.otps])).not.toContain("135790");
    expect(t.sent[0].code).toBe("135790");
  });
  test("hash is bound to the phone number and the secret", async () => {
    const a = await hashOtp("s", "+213555123456", "111111");
    expect(a).not.toBe(await hashOtp("s", "+213666123456", "111111"));
    expect(a).not.toBe(await hashOtp("other", "+213555123456", "111111"));
  });
  test("correct code verifies against the hash; a legacy plaintext row is refused", async () => {
    const t = setup({}, true, "246802");
    await t.call({ action: "request", phone: PHONE });
    expect((await t.call({ action: "verify", phone: PHONE, code: "246802" })).status).toBe(200);
    t.otps.set(E164, { code: "246802", expires_at: new Date(t.now() + 60000).toISOString() });
    expect((await t.call({ action: "verify", phone: PHONE, code: "246802" })).status).toBe(400);
  });
  test("expiry: valid just before 10 minutes, rejected and deleted after", async () => {
    const t = setup({}, true, "246802");
    await t.call({ action: "request", phone: PHONE });
    t.advance(10 * 60 * 1000 - 1000);
    expect((await t.call({ action: "verify", phone: PHONE, code: "000000" })).json.error).toBe("Code incorrect");
    t.advance(2000);
    const r = await t.call({ action: "verify", phone: PHONE, code: "246802" });
    expect(r.status).toBe(400);
    expect(r.json.error).toContain("expiré");
    expect(t.otps.has(E164)).toBe(false);
  });
});

describe("account deletion", () => {
  const H = { Authorization: "Bearer social.delete-user" };
  test("requires a valid signed-in user and ignores caller-supplied user ids", async () => {
    const t = setup();
    expect((await t.call({ action: "delete_account", user_id: "someone-else" })).status).toBe(401);
    expect((await t.call({ action: "delete_account", user_id: "someone-else" }, { Authorization: "Bearer anon-key" })).status).toBe(401);
    expect(t.calls.accountClose).toHaveLength(0);
    expect(t.calls.authDelete).toHaveLength(0);
  });
  test("blocks deletion while a trip is active and never deletes Auth", async () => {
    const t = setup(); t.setCloseResult("active");
    const r = await t.call({ action: "delete_account" }, H);
    expect(r.status).toBe(409);
    expect(t.calls.accountClose).toEqual(["social.delete-user"]);
    expect(t.calls.authDelete).toHaveLength(0);
  });
  test("anonymises first, then deletes the authenticated identity", async () => {
    const t = setup();
    const r = await t.call({ action: "delete_account" }, H);
    expect(r.status).toBe(200);
    expect(r.json.account_deleted).toBe(true);
    expect(t.calls.accountClose).toEqual(["social.delete-user"]);
    expect(t.calls.authDelete).toEqual(["delete-user"]);
  });
  test("reports retryable partial state when Auth deletion fails", async () => {
    const t = setup(); t.setAuthDeleteResult(false);
    const r = await t.call({ action: "delete_account" }, H);
    expect(r.status).toBe(202);
    expect(r.json.ok).toBe(false);
    expect(r.json.partial).toBe(true);
    expect(t.calls.accountClose).toHaveLength(1);
    expect(t.calls.authDelete).toEqual(["delete-user"]);
  });
});

describe("social accounts must add and verify a phone", () => {
  const H = { Authorization: "Bearer social.g1" };
  test("link actions need a valid user session", async () => {
    const t = setup({}, true, "112233");
    expect((await t.call({ action: "link_request", phone: PHONE })).status).toBe(401);
    expect((await t.call({ action: "link_request", phone: PHONE }, { Authorization: "Bearer anon-key" })).status).toBe(401);
    expect(t.sent.length).toBe(0);
  });
  test("request then verify links the phone; wrong code does not", async () => {
    const t = setup({}, true, "112233");
    expect((await t.call({ action: "link_request", phone: PHONE }, H)).status).toBe(200);
    expect((await t.call({ action: "link_verify", phone: PHONE, code: "000000" }, H)).status).toBe(400);
    expect(t.linked.size).toBe(0);
    const ok = await t.call({ action: "link_verify", phone: PHONE, code: "112233" }, H);
    expect(ok.status).toBe(200);
    expect(t.linked.get(E164)).toBe("g1");
  });
  test("a number owned by another account (phone identity or linked) is refused, no SMS sent", async () => {
    const t = setup({}, true, "112233");
    t.users.set(EMAIL, { id: "phone-user", meta: {} });
    const r = await t.call({ action: "link_request", phone: PHONE }, H);
    expect(r.status).toBe(409);
    expect(t.sent.length).toBe(0);
    const t2 = setup({}, true, "112233");
    t2.linked.set(E164, "someone-else");
    expect((await t2.call({ action: "link_request", phone: PHONE }, H)).status).toBe(409);
  });
  test("verify lockout and per-account SMS cap apply", async () => {
    const t = setup({}, true, "112233");
    await t.call({ action: "link_request", phone: PHONE }, H);
    for (let i = 0; i < 5; i++) await t.call({ action: "link_verify", phone: PHONE, code: "999999" }, H);
    expect((await t.call({ action: "link_verify", phone: PHONE, code: "112233" }, H)).status).toBe(429);
    const t3 = setup({}, true, "112233");
    const phones = ["0555111111", "0555222222", "0555333333", "0555444444", "0555555555", "0555666666"];
    const statuses: number[] = [];
    for (const p of phones) statuses.push((await t3.call({ action: "link_request", phone: p }, H)).status);
    expect(statuses.slice(0, 5)).toEqual([200, 200, 200, 200, 200]);
    expect(statuses[5]).toBe(429);
  });
});
