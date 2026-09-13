// Ports SuperAdminUserListCreateView.post() (admin_views.py:1380) — an
// admin creating another admin/staff account. Must be an Edge Function:
// creating a new auth user via the client SDK would hijack the calling
// admin's own session (same reasoning as the other admin-create-* functions).
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

function randomPassword(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";
  return Array.from({ length: 20 }, () => chars[Math.floor(Math.random() * chars.length)]).join("");
}

function emailForPhone(phone: string): string {
  const digits = phone.replace(/[^0-9]/g, "");
  return `${digits}@phone.wastapp.com`;
}

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
      .from("profiles").select("role, branch_id").eq("id", callerData.user.id).maybeSingle();
    if (!["staff", "admin", "super_admin"].includes(callerProfile?.role ?? "")) {
      return json({ error: "Admin access required." }, 403);
    }
    const isSuperAdmin = callerProfile?.role === "super_admin";

    const body = await req.json();
    const firstName = String(body.first_name ?? "").trim();
    const lastName = String(body.last_name ?? "").trim();
    const phone = String(body.phone ?? "").trim();
    const email = body.email ? String(body.email).trim() : null;
    const requestedRole = String(body.role ?? "admin").trim();

    if (!firstName) return json({ error: "first_name is required." }, 400);
    if (!phone) return json({ error: "phone is required." }, 400);

    const allowedRoles = isSuperAdmin ? ["admin", "super_admin"] : ["staff"];
    if (!allowedRoles.includes(requestedRole)) {
      return json({ error: `You can only create roles: ${allowedRoles.join(", ")}.` }, 403);
    }

    const { data: existing } = await supabase.from("profiles").select("id").eq("phone", phone).maybeSingle();
    if (existing) return json({ error: "Phone number already registered." }, 400);

    const branchId = isSuperAdmin ? (body.branch_id ?? null) : (callerProfile?.branch_id ?? null);

    const { data: created, error: createErr } = await supabase.auth.admin.createUser({
      email: emailForPhone(phone),
      password: randomPassword(),
      email_confirm: true,
    });
    if (createErr || !created.user) return json({ error: createErr?.message ?? "Failed to create account" }, 400);
    const newUid = created.user.id;

    const { data: profile, error: profileErr } = await supabase.from("profiles").insert({
      id: newUid, phone, first_name: firstName, last_name: lastName,
      email, role: requestedRole, branch_id: branchId,
      is_staff: requestedRole === "super_admin", is_superuser: requestedRole === "super_admin",
      password_set: false,
    }).select().single();
    if (profileErr) return json({ error: profileErr.message }, 400);

    return json({
      id: profile.id, full_name: `${firstName} ${lastName}`.trim(), phone, email,
      role: requestedRole, branch: branchId,
    });
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
