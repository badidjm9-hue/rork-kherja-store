import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const allowedRoles = new Set(["operations_manager", "support_agent", "financial_manager", "pricing_manager"]);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return json({ error: "Unauthorized" }, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) return json({ error: "Server configuration unavailable" }, 503);

  const caller = createClient(url, anonKey, { global: { headers: { Authorization: authorization } } });
  const { data: me, error: meError } = await caller.rpc("admin_me");
  if (meError || !me || !Array.isArray((me as { permissions?: unknown }).permissions)
      || !(me as { permissions: string[] }).permissions.includes("admins.manage")) {
    return json({ error: "Permission denied" }, 403);
  }

  let body: { email?: unknown; display_name?: unknown; role?: unknown };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  const displayName = typeof body.display_name === "string" ? body.display_name.trim().slice(0, 80) : "";
  const role = typeof body.role === "string" ? body.role : "";
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: "Invalid email address" }, 400);
  if (!allowedRoles.has(role)) return json({ error: "Invalid employee role" }, 400);

  const service = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data: invite, error: inviteError } = await service.auth.admin.inviteUserByEmail(email, {
    data: { display_name: displayName },
  });
  if (inviteError || !invite.user) return json({ error: inviteError?.message ?? "Invitation failed" }, 400);

  const { error: assignError } = await caller.rpc("admin_set_admin", {
    p_email: email,
    p_role: role,
    p_active: true,
    p_display_name: displayName || email.split("@")[0],
  });
  if (assignError) {
    // This user was just created by this request. Remove the unassigned invite to avoid
    // leaving a half-created employee record when RBAC rejects the assignment.
    await service.auth.admin.deleteUser(invite.user.id);
    return json({ error: assignError.message }, 400);
  }

  return json({ user_id: invite.user.id, invited: true });
});
