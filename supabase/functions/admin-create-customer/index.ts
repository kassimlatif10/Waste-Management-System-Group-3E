// Ports CustomerListView.post() (admin_views.py:452) — admin creates a
// customer account. Must be an Edge Function for the same reason as
// investor-register-collector: creating a new auth user via the client SDK
// would hijack the calling ADMIN's own session.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

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
      .from("profiles").select("role").eq("id", callerData.user.id).maybeSingle();
    if (!["staff", "admin", "super_admin"].includes(callerProfile?.role ?? "")) {
      return json({ error: "Admin access required." }, 403);
    }

    const body = await req.json();
    const phone = String(body.phone ?? "").trim();
    const firstName = String(body.first_name ?? "").trim();
    const lastName = String(body.last_name ?? "").trim();
    const email = body.email ? String(body.email).trim() : null;
    const password = body.password ? String(body.password).trim() : "Welcome123!";
    if (!phone) return json({ error: "phone is required." }, 400);

    const { data: existing } = await supabase.from("profiles").select("id").eq("phone", phone).maybeSingle();
    if (existing) return json({ error: "Phone number already registered." }, 400);

    const { data: created, error: createErr } = await supabase.auth.admin.createUser({
      email: emailForPhone(phone),
      password,
      email_confirm: true,
    });
    if (createErr || !created.user) return json({ error: createErr?.message ?? "Failed to create account" }, 400);
    const newUid = created.user.id;

    await supabase.from("profiles").insert({
      id: newUid, phone, first_name: firstName, last_name: lastName,
      email, role: "customer", password_set: true,
    });

    return json({ message: "Customer created.", user_id: newUid });
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
