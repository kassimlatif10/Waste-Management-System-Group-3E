// Ports AdminInvestorListCreateView.post() (investor_views.py:335) — super
// admin creates an investor account. Must be an Edge Function: creating a
// new auth user via the client SDK would hijack the calling ADMIN's own
// session (same reasoning as admin-create-customer/admin-create-collector).
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

function randomPassword(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";
  return Array.from({ length: 32 }, () => chars[Math.floor(Math.random() * chars.length)]).join("");
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
      .from("profiles").select("role").eq("id", callerData.user.id).maybeSingle();
    if (callerProfile?.role !== "super_admin") {
      return json({ error: "Only Super Admin can create investor accounts." }, 403);
    }

    const body = await req.json();
    const required = ["first_name", "last_name", "phone", "investment_amount", "location"];
    for (const f of required) {
      if (!body[f]) return json({ error: `Field "${f}" is required.` }, 400);
    }

    const { data: existing } = await supabase.from("profiles").select("id").eq("phone", body.phone).maybeSingle();
    if (existing) return json({ error: "Phone number already registered." }, 400);

    const { data: created, error: createErr } = await supabase.auth.admin.createUser({
      email: emailForPhone(body.phone),
      password: randomPassword(),
      email_confirm: true,
    });
    if (createErr || !created.user) return json({ error: createErr?.message ?? "Failed to create account" }, 400);
    const newUid = created.user.id;

    await supabase.from("profiles").insert({
      id: newUid, phone: body.phone, first_name: body.first_name, last_name: body.last_name,
      email: body.email || null, role: "investor", password_set: false,
    });

    const { data: profile, error: profileErr } = await supabase.from("investor_profiles").insert({
      user_id: newUid,
      company_name: body.company_name || null,
      location: body.location,
      location_latitude: body.location_latitude ?? null,
      location_longitude: body.location_longitude ?? null,
      investment_amount: body.investment_amount,
      roi_percentage: body.roi_percentage ?? 0,
      yearly_profit_margin: body.yearly_profit_margin ?? 0,
    }).select().single();
    if (profileErr) return json({ error: profileErr.message }, 400);

    return json({
      message: "Investor account created successfully. The investor can now set their password on first login.",
      investor: {
        id: profile.id, user_id: newUid,
        full_name: `${body.first_name} ${body.last_name}`.trim(),
        phone: body.phone, investment_amount: body.investment_amount, location: body.location,
      },
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
