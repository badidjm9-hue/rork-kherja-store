// Security policy for the auth-otp function. Pure functions only (no Deno, no network) so the
// rules that decide whether a verification code may ever reach a client are unit-tested.

export type RuntimeEnv = "development" | "production";

type EnvGetter = (key: string) => string | undefined;

/**
 * The runtime is "development" ONLY when the server-side secret KHERJA_ENV is exactly
 * "development". Anything else, including unset, typos and "dev", is production (fail closed).
 * It is read from the function's environment, never from the request.
 */
export function resolveRuntimeEnv(get: EnvGetter): RuntimeEnv {
  return get("KHERJA_ENV") === "development" ? "development" : "production";
}

/**
 * A verification code may be returned to the client only in development AND only when
 * ALLOW_DEV_OTP is explicitly "true". Both are server-side settings.
 */
export function devOtpAllowed(get: EnvGetter): boolean {
  return resolveRuntimeEnv(get) === "development" && get("ALLOW_DEV_OTP") === "true";
}

export type OtpDelivery =
  | { kind: "sent" }
  | { kind: "dev_code" }
  | { kind: "error"; status: number; message: string };

/**
 * Decides what to tell the client after a code was generated.
 *  - SMS delivered: "sent" (the code is never returned).
 *  - SMS not delivered, development with the explicit dev flag: "dev_code".
 *  - SMS not delivered otherwise: a secure error; the code is discarded by the caller.
 */
export function decideOtpDelivery(input: { smsSent: boolean; devAllowed: boolean }): OtpDelivery {
  if (input.smsSent) return { kind: "sent" };
  if (input.devAllowed) return { kind: "dev_code" };
  return { kind: "error", status: 503, message: "Service SMS indisponible, réessayez plus tard" };
}

export type Purpose = "login" | "register" | "reset";

export function parsePurpose(raw: unknown): Purpose | null {
  if (raw === undefined || raw === null || raw === "") return "login";
  return raw === "login" || raw === "register" || raw === "reset" ? raw : null;
}

export type PurposeDecision = { ok: true } | { ok: false; status: number; message: string };

/**
 * Runs after the SMS code is proven. `login` keeps the original behaviour (find or create the
 * account) and never accepts a password. `register` requires a brand-new number; `reset`
 * requires an existing account.
 */
export function decidePurpose(input: {
  purpose: Purpose;
  userExists: boolean;
  hasPassword: boolean;
}): PurposeDecision {
  const { purpose, userExists, hasPassword } = input;
  if (purpose === "login") {
    return hasPassword
      ? { ok: false, status: 400, message: "Mot de passe non attendu pour cette action" }
      : { ok: true };
  }
  if (!hasPassword) return { ok: false, status: 400, message: "Mot de passe requis" };
  if (purpose === "register" && userExists) {
    return { ok: false, status: 409, message: "Un compte existe déjà avec ce numéro, connectez-vous" };
  }
  if (purpose === "reset" && !userExists) {
    return { ok: false, status: 404, message: "Aucun compte associé à ce numéro" };
  }
  return { ok: true };
}
