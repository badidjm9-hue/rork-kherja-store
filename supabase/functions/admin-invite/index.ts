import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const allowedRoles = new Set(["operations_manager", "support_agent", "financial_manager", "pricing_manager", "super_admin"]);

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
  let userId = invite?.user?.id ?? null;
  const newlyInvited = Boolean(userId);

  // Existing KHERJA accounts can also be added as employees without sending a duplicate invite.
  if (!userId && inviteError) {
    for (let page = 1; page <= 10 && !userId; page++) {
      const { data, error } = await service.auth.admin.listUsers({ page, perPage: 1000 });
      if (error) return json({ error: error.message }, 500);
      userId = data.users.find((user) => user.email?.toLowerCase() === email)?.id ?? null;
      if (data.users.length < 1000) break;
    }
  }
  if (!userId) return json({ error: inviteError?.message ?? "Invitation failed" }, 400);

  const { data: existingAdmin, error: existingAdminError } = await service
    .from("admin_users").select("user_id").eq("user_id", userId).maybeSingle();
  if (existingAdminError) return json({ error: existingAdminError.message }, 500);
  if (existingAdmin) return json({ error: "This account is already an administrator" }, 409);

  const { error: assignError } = await caller.rpc("admin_set_admin", {
    p_email: email,
    p_role: role,
    p_active: true,
    p_display_name: displayName || email.split("@")[0],
  });
  if (assignError) {
    if (newlyInvited) await service.auth.admin.deleteUser(userId);
    return json({ error: assignError.message }, 400);
  }

  // Least privilege by default: employees receive no permissions until selected.
  // A super admin is the sole exception and always receives the complete permission set.
  if (role !== "super_admin") {
    const { error: permissionError } = await caller.rpc("admin_set_user_permissions", {
      p_user_id: userId,
      p_permission_codes: [],
      p_use_custom: true,
    });
    if (permissionError) {
      await service.from("admin_users").delete().eq("user_id", userId);
      if (newlyInvited) await service.auth.admin.deleteUser(userId);
      return json({ error: permissionError.message }, 400);
    }
  }

  return json({ user_id: userId, invited: newlyInvited });
});
