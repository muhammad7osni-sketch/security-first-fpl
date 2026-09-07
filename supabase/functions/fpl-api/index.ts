// supabase/functions/fpl-api/index.ts
//
// Deploy with: supabase functions deploy fpl-api --no-verify-jwt
//
// Purpose: Flutter Web cannot call fantasy.premierleague.com directly —
// the browser enforces CORS and FPL's response has no
// Access-Control-Allow-Origin header for our domain. This function is
// a thin, same-shape proxy: it forwards the request path to FPL,
// forwards FPL's response back unchanged, and adds the CORS headers
// the browser needs. Native builds (Android/iOS/desktop) never call
// this — see FplProvider._resolveBaseUrl() in the Flutter app, which
// only routes through here when kIsWeb is true.
//
// This function does NOT add authentication, does NOT modify FPL's
// response, and does NOT cache beyond a short edge-cache header — all
// caching/TTL logic stays in FplProvider (TtlCache), so behavior is
// identical whether a request went direct (native) or through here
// (web). Keep it that way: this should stay a dumb proxy, not grow
// FPL-specific logic of its own.
//
// --no-verify-jwt is used because this proxies public, unauthenticated
// FPL data — there's nothing user-specific to protect here. If you
// later add a use case that needs the caller's identity, verify the
// JWT properly rather than trusting a client-supplied header.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const FPL_BASE_URL = "https://fantasy.premierleague.com/api";

// Set this to your actual deployed web origin(s) before shipping —
// '*' is fine for local development but defeats the purpose of a
// origin allowlist in production. Multiple origins can be handled by
// checking `req.headers.get("Origin")` against a list instead of a
// single constant, if you serve from more than one domain.
const ALLOWED_ORIGIN = Deno.env.get("ALLOWED_WEB_ORIGIN") ?? "*";

const corsHeaders = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

serve(async (req) => {
  // Browsers send a CORS preflight OPTIONS request before the real GET —
  // this must return 200 with the CORS headers and no body.
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  if (req.method !== "GET") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const url = new URL(req.url);
  // Path after the function name, e.g. a request to
  // `.../functions/v1/fpl-api/bootstrap-static/` forwards to
  // `https://fantasy.premierleague.com/api/bootstrap-static/`.
  const forwardPath = url.pathname.replace(/^\/functions\/v1\/fpl-api/, "");
  const fplUrl = `${FPL_BASE_URL}${forwardPath}${url.search}`;

  try {
    const fplResponse = await fetch(fplUrl, {
      headers: { "User-Agent": "SquadIQ/0.1 (+read-only)" },
    });

    const body = await fplResponse.text();

    return new Response(body, {
      status: fplResponse.status,
      headers: {
        ...corsHeaders,
        "Content-Type": fplResponse.headers.get("Content-Type") ?? "application/json",
        // Short edge cache only - the real TTL policy (20min normal /
        // 1min near deadline) lives in the Flutter app's TtlCache, not
        // here. This just softens a burst of near-simultaneous browser
        // tabs, nothing more.
        "Cache-Control": "public, max-age=60",
      },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: `Upstream fetch failed: ${String(e)}` }), {
      status: 502,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
