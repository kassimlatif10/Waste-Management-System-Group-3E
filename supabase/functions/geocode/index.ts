// Mirrors wast/geo_views.py + services.py's Google/Nominatim proxy: keeps
// the Google Maps API key server-side instead of shipping it in the app.
// GET ?mode=reverse&lat=..&lng=..  or  ?mode=search&query=..
import { corsHeaders } from "../_shared/cors.ts";

const GOOGLE_KEY = Deno.env.get("GOOGLE_MAPS_API_KEY");

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const url = new URL(req.url);
  const mode = url.searchParams.get("mode");

  try {
    if (mode === "reverse") {
      const lat = url.searchParams.get("lat");
      const lng = url.searchParams.get("lng");
      if (!lat || !lng) throw new Error("lat and lng are required");

      if (GOOGLE_KEY) {
        const r = await fetch(
          `https://maps.googleapis.com/maps/api/geocode/json?latlng=${lat},${lng}&key=${GOOGLE_KEY}`,
        );
        const data = await r.json();
        if (data.status === "OK" && data.results?.[0]) {
          return json({ address: data.results[0].formatted_address, raw: data.results[0] });
        }
        // Google denied/empty (e.g. billing not enabled on the key's project) — fall through to Nominatim.
      }
      // Fallback: Nominatim (no key required)
      const r = await fetch(
        `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lng}&format=json`,
        { headers: { "User-Agent": "WastePick/1.0" } },
      );
      const data = await r.json();
      return json({ address: data.display_name ?? null, raw: data });
    }

    if (mode === "search") {
      const query = url.searchParams.get("query");
      if (!query) throw new Error("query is required");

      if (GOOGLE_KEY) {
        const r = await fetch(
          `https://maps.googleapis.com/maps/api/place/textsearch/json?query=${encodeURIComponent(query)}&key=${GOOGLE_KEY}`,
        );
        const data = await r.json();
        if (data.status === "OK" && (data.results ?? []).length > 0) {
          const results = data.results.map((p: any) => ({
            name: p.name,
            address: p.formatted_address,
            lat: p.geometry?.location?.lat,
            lng: p.geometry?.location?.lng,
          }));
          return json({ results });
        }
        // Google denied/empty — fall through to Nominatim.
      }
      const r = await fetch(
        `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(query)}&format=json&limit=8`,
        { headers: { "User-Agent": "WastePick/1.0" } },
      );
      const data = await r.json();
      const results = (data ?? []).map((p: any) => ({
        name: p.display_name, address: p.display_name, lat: Number(p.lat), lng: Number(p.lon),
      }));
      return json({ results });
    }

    throw new Error("mode must be 'reverse' or 'search'");
  } catch (e) {
    return json({ error: String(e) }, 400);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
