// Ports CollectorListView.post() (admin_views.py:549) — admin registers a
// collector with KYC documents and an optional vehicle. Must be an Edge
// Function: creating a new auth user via the client SDK would hijack the
// calling ADMIN's own session (same reasoning as investor-register-collector
// and admin-create-customer).
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

function randomPassword(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";
  return Array.from({ length: 12 }, () => chars[Math.floor(Math.random() * chars.length)]).join("");
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
    const {
      name, phone, ghana_card_number, license_number,
      existing_vehicle_id, vehicle_type, vehicle_number, vehicle_name,
      branch_id,
    } = body;
    const autoApprove = body.auto_approve === true || body.auto_approve === "true";
    const isCompanyCollector = body.is_company_collector === true || body.is_company_collector === "true";
    const password = body.password || randomPassword();
    const images = (body.images ?? {}) as Record<string, string>;

    if (!name || !phone || !ghana_card_number || !license_number) {
      return json({ error: "name, phone, ghana_card_number and license_number are required." }, 400);
    }
    const creatingNewVehicle = !existing_vehicle_id && !!vehicle_number;
    if (creatingNewVehicle && !vehicle_type) return json({ error: "vehicle_type is required." }, 400);
    for (const doc of ["ghana_card_front", "ghana_card_back", "license_front", "license_back"]) {
      if (!images[doc]) return json({ error: `${doc} is required.` }, 400);
    }
    if (creatingNewVehicle && !images.vehicle_photo) return json({ error: "vehicle_photo is required." }, 400);

    if (existing_vehicle_id) {
      const { data: veh } = await supabase.from("collector_vehicles").select("id").eq("id", existing_vehicle_id).maybeSingle();
      if (!veh) return json({ error: `Vehicle with id ${existing_vehicle_id} does not exist.` }, 400);
    }

    const { data: existingProfile } = await supabase.from("profiles").select("id").eq("phone", phone).maybeSingle();
    if (existingProfile) return json({ error: "Phone number already registered." }, 400);

    let collectorBranchId = callerProfile?.branch_id ?? null;
    if (branch_id && isSuperAdmin) collectorBranchId = branch_id;

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
      role: "collector", branch_id: collectorBranchId, password_set: !!body.password,
    });

    const { data: cp } = await supabase
      .from("collector_profiles")
      .insert({
        user_id: newUid, vehicle_type: vehicle_type || "",
        is_approved: autoApprove, is_company_collector: isCompanyCollector,
      })
      .select().single();

    const kycStatus = autoApprove ? "approved" : "under_review";
    const { data: kyc } = await supabase
      .from("collector_kyc")
      .insert({
        user_id: newUid, ghana_card_number, license_number,
        vehicle_number_plate: vehicle_number, kyc_status: kycStatus,
        reviewed_by_id: autoApprove ? callerData.user.id : null,
      })
      .select().single();

    for (const docType of ["ghana_card_front", "ghana_card_back", "license_front", "license_back"]) {
      const path = `${newUid}/${docType}.jpg`;
      await supabase.storage.from("kyc-documents").upload(path, base64ToBytes(images[docType]), {
        contentType: "image/jpeg", upsert: true,
      });
      await supabase.from("kyc_documents").insert({ kyc_id: kyc?.id, document_type: docType, file: path });
    }

    let vehicleId: number | null = null;
    if (existing_vehicle_id) {
      await supabase.from("collector_vehicles")
        .update({ collector_id: cp?.id, driver_id: newUid, is_default: true })
        .eq("id", existing_vehicle_id);
      vehicleId = existing_vehicle_id;
    } else if (creatingNewVehicle) {
      const vehiclePhotoPath = `${newUid}/vehicles/${Date.now()}.jpg`;
      await supabase.storage.from("vehicle-photos").upload(vehiclePhotoPath, base64ToBytes(images.vehicle_photo), {
        contentType: "image/jpeg", upsert: true,
      });
      const { data: vehicle } = await supabase.from("collector_vehicles").insert({
        collector_id: cp?.id, driver_id: newUid, name: vehicle_name || vehicle_type,
        vehicle_type, vehicle_number, vehicle_photo: vehiclePhotoPath,
        is_default: true, needs_admin_approval: !autoApprove,
      }).select().single();
      vehicleId = vehicle?.id ?? null;
    }

    return json({
      message: "Collector created successfully.",
      collector: {
        id: cp?.id, name, phone, is_approved: autoApprove,
        vehicle_id: vehicleId, kyc_status: kycStatus,
        temporary_password: body.password ? null : password,
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
