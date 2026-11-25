// Pure helpers for password-based sign-in. No Deno or network APIs here so they can be unit-tested.

export const MIN_PASSWORD_LENGTH = 8;
export const MAX_PASSWORD_LENGTH = 72; // bcrypt limit used by Supabase Auth

/** Returns an error message (French, shown to the user) or null when the password is acceptable. */
export function validatePassword(password: unknown): string | null {
  if (typeof password !== "string") return "Mot de passe invalide";
  if (password.length < MIN_PASSWORD_LENGTH) {
    return `Le mot de passe doit contenir au moins ${MIN_PASSWORD_LENGTH} caractères`;
  }
  // bcrypt accepts at most 72 UTF-8 bytes, not 72 Unicode characters.
  if (new TextEncoder().encode(password).length > MAX_PASSWORD_LENGTH) return "Mot de passe trop long";
  if (!/[A-Za-z؀-ۿ]/.test(password) || !/[0-9]/.test(password)) {
    return "Le mot de passe doit contenir des lettres et des chiffres";
  }
  return null;
}

/** Optional contact e-mail. Returns the trimmed lowercase address, "" when absent, or null when malformed. */
export function normalizeEmail(email: unknown): string | null {
  if (email === undefined || email === null || email === "") return "";
  if (typeof email !== "string") return null;
  const e = email.trim().toLowerCase();
  if (e.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e)) return null;
  return e;
}

export const MAX_FAILURES = 5;
export const FAILURE_WINDOW_MINUTES = 15;

/** True when the number of recent failed attempts blocks another try. */
export function isBlocked(recentFailures: number): boolean {
  return recentFailures >= MAX_FAILURES;
}

/** Constant-time string comparison (avoids leaking how many leading characters matched). */
export function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
/** HMAC-SHA-256 with a server-only pepper; use distinct prefixes for each value type. */
export async function hmacHex(secret: string, value: string): Promise<string> {
  if (secret.length < 32) throw new Error("OTP_HASH_SECRET must be at least 32 characters");
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

export function hashOtpInput(secret: string, phone: string, code: string): Promise<string> {
  return hmacHex(secret, `otp:${phone}:${code}`);
}

export function hashClientIp(secret: string, ip: string): Promise<string> {
  return hmacHex(secret, `ip:${ip}`);
}
