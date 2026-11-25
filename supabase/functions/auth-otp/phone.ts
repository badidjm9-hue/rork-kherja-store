// Algerian phone helpers (moved verbatim from index.ts so they can be tested).

/** Normalise Algerian numbers to E.164 (+213). Returns null when invalid. */
export function normalizePhone(raw: string): string | null {
  const digits = raw.replace(/[\s()-]/g, "");
  let e164: string;
  if (digits.startsWith("+213")) e164 = digits;
  else if (digits.startsWith("213")) e164 = "+" + digits;
  else if (digits.startsWith("0")) e164 = "+213" + digits.slice(1);
  else return null;
  if (!/^\+213[5-7]\d{8}$/.test(e164)) return null;
  return e164;
}

export function displayPhone(e164: string): string {
  // +213555123456 -> 0555 12 34 56
  const local = "0" + e164.slice(4);
  return `${local.slice(0, 4)} ${local.slice(4, 6)} ${local.slice(6, 8)} ${local.slice(8, 10)}`;
}

// Each phone number maps to a synthetic, auto-confirmed email identity so
// Supabase mints a real session (refreshable, recognised by RLS/Realtime).
export function emailForPhone(phone: string): string {
  return `u${phone.replace(/[^0-9]/g, "")}@phone.kherja.app`;
}
