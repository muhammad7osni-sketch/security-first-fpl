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
// --no-verify-jwt: proxies public, unauthenticated FPL data.

const FPL_BASE_URL = "https://fantasy.premierleague.com/api";

const getAllowedOrigin = (origin: string | null): string => {
  if (origin && (origin.includes("localhost") || origin.includes("127.0.0.1"))) {
    return origin;
  }
  return Deno.env.get("ALLOWED_WEB_ORIGIN") ?? "*";
};

const corsHeaders = (origin: string | null) => ({
  "Access-Control-Allow-Origin": getAllowedOrigin(origin),
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
});

Deno.serve(async (req: Request): Promise<Response> => {
  const origin = req.headers.get("origin");
  const cors = corsHeaders(origin);

  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: cors });
  }

  if (req.method !== "GET") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const url = new URL(req.url);

  // The Flutter interceptor sends the FPL path as ?path=/bootstrap-static/
  // (see fpl_provider.dart's onRequest interceptor).
  const fplPath = url.searchParams.get("path") ?? "";
  // Strip the path param and forward remaining query params to FPL
  url.searchParams.delete("path");
  const fplUrl = `${FPL_BASE_URL}${fplPath}${url.search ? url.search : ""}`;

  try {
    const fplResponse = await fetch(fplUrl, {
      headers: { "User-Agent": "SquadIQ/0.1 (+read-only)" },
    });

    const body = await fplResponse.text();

    return new Response(body, {
      status: fplResponse.status,
      headers: {
        ...cors,
        "Content-Type":
          fplResponse.headers.get("Content-Type") ?? "application/json",
        // Short edge cache: the real TTL policy lives in Flutter's TtlCache.
        "Cache-Control": "public, max-age=60",
      },
    });
  } catch (e) {
    return new Response(
      JSON.stringify({ error: `Upstream fetch failed: ${String(e)}` }),
      {
        status: 502,
        headers: { ...cors, "Content-Type": "application/json" },
      },
    );
  }
});
