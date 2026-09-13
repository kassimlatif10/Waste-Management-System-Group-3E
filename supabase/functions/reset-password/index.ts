// Mirrors accounts/views.py ResetPasswordView: verifies a fresh OTP and
// sets the new password in one step. Needs the service-role admin API
// because there's no logged-in session yet at this point in the flow.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { phone, otp_code, new_password } = await req.json();
    if (!phone || !otp_code || !new_password) {
      return json({ error: "phone, otp_code and new_password are required" }, 400);
    }
    if (String(new_password).length < 6) {
      return json({ error: "Password must be at least 6 characters" }, 400);
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: otp } = await supabase
      .from("otp_verifications")
      .select("*")
      .eq("phone", phone).eq("otp_code", otp_code).eq("purpose", "password_reset")
      .eq("is_used", false)
      .gt("expires_at", new Date().toISOString())
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (!otp) return json({ error: "Invalid or expired code" }, 400);

    const { data: profile } = await supabase
      .from("profiles").select("id").eq("phone", phone).maybeSingle();
    if (!profile) return json({ error: "No account found for this phone" }, 404);

    const { error: updErr } = await supabase.auth.admin.updateUserById(profile.id, {
      password: new_password,
    });
    if (updErr) throw updErr;

    await supabase.from("otp_verifications").update({ is_used: true }).eq("id", otp.id);
    await supabase.from("profiles").update({ password_set: true }).eq("id", profile.id);

    return json({ success: true });
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
