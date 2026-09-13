// Mirrors accounts/views.py VerifyOTPView: validates the code, marks it
// used, and reports whether the phone belongs to an existing profile (and
// whether that profile has already set a password) so the client can route
// to login vs. registration vs. password-reset.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { phone, otp_code, purpose } = await req.json();
    if (!phone || !otp_code || !purpose) {
      return new Response(JSON.stringify({ error: "phone, otp_code and purpose are required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: otp, error: otpErr } = await supabase
      .from("otp_verifications")
      .select("*")
      .eq("phone", phone).eq("otp_code", otp_code).eq("purpose", purpose)
      .eq("is_used", false)
      .gt("expires_at", new Date().toISOString())
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (otpErr) throw otpErr;
    if (!otp) {
      return new Response(JSON.stringify({ error: "Invalid or expired code" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    await supabase.from("otp_verifications").update({ is_used: true }).eq("id", otp.id);

    const { data: profile } = await supabase
      .from("profiles")
      .select("id, password_set")
      .eq("phone", phone)
      .maybeSingle();

    return new Response(JSON.stringify({
      success: true,
      is_new_user: !profile,
      has_password: profile?.password_set ?? false,
    }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
