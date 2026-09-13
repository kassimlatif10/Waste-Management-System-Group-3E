// Ports admin_views.py's SuperAdminDeleteCustomerView/SuperAdminDeleteCollectorView/
// SuperAdminDeleteInvestorView (:1480+) and SuperAdminUserDetailView's DELETE
// (admin account removal) into one shared function.
//
// Must be an Edge Function: deleting an account means deleting the
// auth.users row via the service-role admin API (auth.admin.deleteUser),
// which a client-side call can never do. profiles.id -> auth.users.id is
// "on delete cascade", so removing the auth user cascades through profiles
// and every table that references it.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Missing Authorization header" }, 401);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: callerData, error: callerErr } = await supabase.auth.getUser(
      authHeader.replace("Bearer ", ""),
    );
    if (callerErr || !callerData.user) return json({ error: "Invalid session" }, 401);

    const { data: callerProfile } = await supabase
      .from("profiles").select("role").eq("id", callerData.user.id).maybeSingle();
    if (callerProfile?.role !== "super_admin") {
      return json({ error: "Only a super admin can delete accounts." }, 403);
    }

    const { user_id, expected_role } = await req.json();
    if (!user_id) return json({ error: "user_id is required." }, 400);
    if (user_id === callerData.user.id) return json({ error: "Cannot delete your own account." }, 400);

    if (expected_role) {
      const { data: target } = await supabase
        .from("profiles").select("role").eq("id", user_id).maybeSingle();
      if (!target) return json({ error: "User not found." }, 404);
      if (target.role !== expected_role) return json({ error: "Role mismatch." }, 400);
    }

    const { error: delErr } = await supabase.auth.admin.deleteUser(user_id);
    if (delErr) return json({ error: delErr.message }, 400);

    return json({ message: "Account deleted." });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
