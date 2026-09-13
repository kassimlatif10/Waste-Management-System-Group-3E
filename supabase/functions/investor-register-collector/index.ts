// Ports investor_views.py's InvestorCollectorListCreateView (:632) — an
// investor registering a new collector on their behalf.
//
// This MUST be an Edge Function rather than a client-side call: creating a
// brand-new auth user via the client SDK (signUp) would swap the *caller's*
// (the investor's) browser session over to the new collector, silently
// logging the investor out mid-registration. Account creation for someone
// else always needs the service-role admin API, which only runs safely
// server-side.
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

function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
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

    // Identify the caller from their JWT and confirm they're an investor.
    const { data: callerData, error: callerErr } = await supabase.auth.getUser(
      authHeader.replace("Bearer ", ""),
    );
    if (callerErr || !callerData.user) return json({ error: "Invalid session" }, 401);

    const { data: callerProfile } = await supabase
      .from("profiles").select("role").eq("id", callerData.user.id).maybeSingle();
    if (callerProfile?.role !== "investor") {
      return json({ error: "Only investors can use this endpoint." }, 403);
    }
    const { data: investorProfile } = await supabase
      .from("investor_profiles").select("id").eq("user_id", callerData.user.id).single();

    const body = await req.json();
    const { name, phone, vehicle_type, ghana_card_number, license_number, vehicle_name, vehicle_number } = body;
    const images = (body.images ?? {}) as Record<string, string>;
    if (!name || !phone) return json({ error: "name and phone are required." }, 400);

    const password = randomPassword();
    const { data: created, error: createErr } = await supabase.auth.admin.createUser({
      email: emailForPhone(phone),
      password,
      email_confirm: true,
    });
    if (createErr || !created.user) return json({ error: createErr?.message ?? "Failed to create account" }, 400);
    const newUid = created.user.id;

    const [firstName, ...rest] = String(name).trim().split(" ");
    await supabase.from("profiles").insert({
      id: newUid, phone, first_name: firstName, last_name: rest.join(" "),
      role: "collector", password_set: false,
    });

    const { data: collectorProfile } = await supabase
      .from("collector_profiles")
      .insert({
        user_id: newUid, vehicle_type, is_approved: false,
        registered_by_investor: true, investor_id: investorProfile?.id ?? null,
      })
      .select().single();

    let vehiclePhotoPath: string | null = null;
    if (images.vehicle_photo) {
      vehiclePhotoPath = `${newUid}/vehicles/${Date.now()}.jpg`;
      await supabase.storage.from("vehicle-photos").upload(vehiclePhotoPath, base64ToBytes(images.vehicle_photo), {
        contentType: "image/jpeg", upsert: true,
      });
    }
    await supabase.from("collector_vehicles").insert({
      collector_id: collectorProfile?.id, name: vehicle_name, vehicle_type, vehicle_number,
      vehicle_photo: vehiclePhotoPath, is_default: true,
    });

    const { data: kyc } = await supabase
      .from("collector_kyc")
      .insert({ user_id: newUid, ghana_card_number, license_number, kyc_status: "pending" })
      .select().single();

    for (const docType of ["ghana_card_front", "ghana_card_back", "license_front", "license_back"]) {
      const b64 = images[docType];
      if (!b64) continue;
      const path = `${newUid}/${docType}.jpg`;
      await supabase.storage.from("kyc-documents").upload(path, base64ToBytes(b64), {
        contentType: "image/jpeg", upsert: true,
      });
      await supabase.from("kyc_documents").insert({ kyc_id: kyc?.id, document_type: docType, file: path });
    }

    return json({ message: "Collector submitted for admin approval.", user_id: newUid });
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
