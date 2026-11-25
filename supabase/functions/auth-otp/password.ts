// Pure helpers for password-based sign-in. No Deno or network APIs here so they can be unit-tested.

export const MIN_PASSWORD_LENGTH = 8;
export const MAX_PASSWORD_LENGTH = 72; // bcrypt limit used by Supabase Auth

/** Returns an error message (French, shown to the user) or null when the password is acceptable. */
export function validatePassword(password: unknown): string | null {
  if (typeof password !== "string") return "Mot de passe invalide";
  if (password.length < MIN_PASSWORD_LENGTH) {
    return `Le mot de passe doit contenir au moins ${MIN_PASSWORD_LENGTH} caractères`;
  }
  // Match the client and Supabase Auth's bcrypt input boundary: UTF-8 bytes, not JS UTF-16 units.
  if (new TextEncoder().encode(password).length > MAX_PASSWORD_LENGTH) return "Mot de passe trop long";
  if (!/\p{L}/u.test(password) || !/[0-9]/.test(password)) {
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
