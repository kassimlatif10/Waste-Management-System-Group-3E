// Mirrors accounts/views.py SendOTPView: generates a 6-digit code, 10-min
// expiry, deletes prior unused codes for the same phone+purpose. Real SMS
// dispatch is deferred (matching today's Django dev-mode behavior) — the
// code is returned directly in the response instead of being texted.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { phone, purpose } = await req.json();
    if (!phone || !["password_reset", "verification"].includes(purpose)) {
      return new Response(JSON.stringify({ error: "phone and a valid purpose are required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Rate limit: 5 sends per hour per phone (mirrors DRF AnonRateThrottle scope="otp").
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const { count } = await supabase
      .from("otp_verifications")
      .select("id", { count: "exact", head: true })
      .eq("phone", phone)
      .gte("created_at", oneHourAgo);
    if ((count ?? 0) >= 5) {
      return new Response(JSON.stringify({ error: "Too many OTP requests. Try again later." }), {
        status: 429,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    await supabase.from("otp_verifications").delete().eq("phone", phone).eq("purpose", purpose).eq("is_used", false);

    const code = String(Math.floor(100000 + Math.random() * 900000));
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
    const { error } = await supabase.from("otp_verifications").insert({
      phone, otp_code: code, purpose, expires_at: expiresAt,
    });
    if (error) throw error;

    const devMode = (Deno.env.get("OTP_DEV_MODE") ?? "true") === "true";
    const body: Record<string, unknown> = { success: true };
    if (devMode) body.otp_code = code; // dev-only, matches Django's DEBUG=True behavior

    return new Response(JSON.stringify(body), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
