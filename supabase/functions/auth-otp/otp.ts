// OTP hashing. Verification codes are never stored in clear text: the database only holds
// HMAC-SHA256(secret, phone | code), so a leaked backup or a read-only SQL mistake does not
// reveal live codes. The phone is bound into the MAC so a hash cannot be replayed for another number.
// Uses WebCrypto only (available in Deno and Bun), so it is unit-testable.

export const OTP_HASH_PREFIX = "h1:";

function hex(buf: ArrayBuffer): string {
  return Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, "0")).join("");
}

export async function hashOtp(secret: string, phone: string, code: string): Promise<string> {
  if (!secret) throw new Error("otp secret missing");
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${phone}|${code}`));
  return OTP_HASH_PREFIX + hex(mac);
}
