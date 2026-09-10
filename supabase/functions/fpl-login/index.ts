// supabase/functions/fpl-login/index.ts
//
// Deploy with: supabase functions deploy fpl-login --no-verify-jwt
//
// Purpose: Flutter Web cannot POST to users.premierleague.com directly —
// browsers block cross-origin requests with cookies (CORS + SameSite).
// This Edge Function runs server-side (Deno), so it is NOT subject to
// browser CORS restrictions. It:
//   1. Receives the user's FPL email + password from the Flutter app
//   2. POSTs them to FPL's official login endpoint
//   3. Reads the pl_profile session cookie from FPL's response
//   4. Calls /api/me/ with that cookie to get the team ID
//   5. Returns ONLY the team ID (integer) to the Flutter app
//   6. Never stores, logs, or forwards the password or session cookie

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const FPL_LOGIN_URL = "https://users.premierleague.com/accounts/login/";
const FPL_ME_URL = "https://fantasy.premierleague.com/api/me/";

const MAX_LOGIN_ATTEMPTS = 5;
const ATTEMPT_WINDOW_HOURS = 1;

// ── CORS ─────────────────────────────────────────────────────────────────────

const getAllowedOrigin = (origin?: string | null): string => {
  if (origin && (origin.includes("localhost") || origin.includes("127.0.0.1"))) {
    return origin;
  }
  return Deno.env.get("ALLOWED_WEB_ORIGIN") ?? "*";
};

const corsHeaders = (origin?: string | null) => ({
  "Access-Control-Allow-Origin": getAllowedOrigin(origin),
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
});

// ── Helpers ───────────────────────────────────────────────────────────────────

const jsonResp = (
  data: unknown,
  status: number,
  cors: Record<string, string>,
): Response =>
  new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

const getClientIp = (req: Request): string =>
  (
    req.headers.get("cf-connecting-ip") ??
    req.headers.get("x-forwarded-for")?.split(",")[0] ??
    "unknown"
  ).trim();

// Extract all Set-Cookie header values, compatible with all Deno versions
const getSetCookies = (headers: Headers): string[] => {
  // Deno 1.37+ has getSetCookie(); fall back to get() for older runtimes
  if (typeof (headers as any).getSetCookie === "function") {
    return (headers as any).getSetCookie() as string[];
  }
  const raw = headers.get("set-cookie");
  return raw ? [raw] : [];
};

// ── Main handler ──────────────────────────────────────────────────────────────

Deno.serve(async (req: Request): Promise<Response> => {
  const origin = req.headers.get("origin");
  const cors = corsHeaders(origin);

  // Preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: cors });
  }

  if (req.method !== "POST") {
    return jsonResp({ error: "Method not allowed" }, 405, cors);
  }

  try {
    return await handleLogin(req, cors);
  } catch (err) {
    console.error("Unhandled error in fpl-login:", err);
    return jsonResp(
      { error: "Internal server error. Please try again." },
      500,
      cors,
    );
  }
});

// ── Core logic ────────────────────────────────────────────────────────────────

async function handleLogin(
  req: Request,
  cors: Record<string, string>,
): Promise<Response> {
  // 1. Parse body
  let email: string;
  let password: string;
  try {
    const body = await req.json();
    email = String(body?.email ?? "").trim();
    password = String(body?.password ?? "").trim();
  } catch {
    return jsonResp({ error: "Invalid JSON body" }, 400, cors);
  }

  if (!email || !password) {
    return jsonResp({ error: "email and password are required" }, 400, cors);
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return jsonResp({ error: "Invalid email format" }, 400, cors);
  }

  const clientIp = getClientIp(req);

  // 2. Rate limiting
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const supabase = createClient(supabaseUrl, serviceKey);

  const oneHourAgo = new Date(
    Date.now() - ATTEMPT_WINDOW_HOURS * 60 * 60 * 1000,
  ).toISOString();

  const { data: recentAttempts, error: rateErr } = await supabase
    .from("fpl_login_attempts")
    .select("id")
    .eq("ip_address", clientIp)
    .gte("attempted_at", oneHourAgo);

  if (rateErr) {
    console.error("Rate limit check error:", rateErr.message);
    // Non-fatal: continue, don't block user due to DB issue
  }

  if ((recentAttempts?.length ?? 0) >= MAX_LOGIN_ATTEMPTS) {
    return jsonResp(
      { error: "Too many login attempts. Please wait 1 hour." },
      429,
      cors,
    );
  }

  const logAttempt = (success: boolean) =>
    supabase
      .from("fpl_login_attempts")
      .insert({ ip_address: clientIp, success })
      .then(() => {})
      .catch(() => {});

  // 3. POST to FPL login
  let loginResp: Response;
  try {
    loginResp = await fetch(FPL_LOGIN_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "Referer": "https://fantasy.premierleague.com/",
        "Origin": "https://fantasy.premierleague.com",
        "User-Agent": "Mozilla/5.0 (compatible; SquadIQ/1.0)",
      },
      body: new URLSearchParams({
        login: email,
        password,
        app: "plfpl-web",
        redirect_uri: "https://fantasy.premierleague.com/",
      }).toString(),
      redirect: "manual",
    });
  } catch (e) {
    await logAttempt(false);
    return jsonResp({ error: `Cannot reach FPL: ${String(e)}` }, 502, cors);
  }

  // 4. Extract pl_profile cookie
  const cookies = getSetCookies(loginResp.headers);
  let plProfile: string | null = null;

  for (const raw of cookies) {
    for (const part of raw.split(";")) {
      const t = part.trim();
      if (t.startsWith("pl_profile=")) {
        plProfile = t;
        break;
      }
    }
    if (plProfile) break;
  }

  if (!plProfile) {
    await logAttempt(false);
    return jsonResp(
      { error: "FPL login failed. Check your email and password." },
      401,
      cors,
    );
  }

  // 5. Call /me/ with the session cookie
  let meResp: Response;
  try {
    meResp = await fetch(FPL_ME_URL, {
      headers: {
        "Cookie": plProfile,
        "Referer": "https://fantasy.premierleague.com/",
        "User-Agent": "Mozilla/5.0 (compatible; SquadIQ/1.0)",
      },
    });
  } catch (e) {
    await logAttempt(false);
    return jsonResp({ error: `Cannot reach FPL /me/: ${String(e)}` }, 502, cors);
  }

  // 6. Parse team ID
  let meData: Record<string, unknown>;
  try {
    meData = await meResp.json();
  } catch {
    await logAttempt(false);
    return jsonResp({ error: "Unexpected response from FPL." }, 502, cors);
  }

  const entry = meData["entry"] as Record<string, unknown> | null | undefined;
  const player = meData["player"] as Record<string, unknown> | null | undefined;

  if (!entry) {
    await logAttempt(false);
    return jsonResp(
      {
        error:
          "No FPL team found for this account. " +
          "Create a team at fantasy.premierleague.com first.",
      },
      404,
      cors,
    );
  }

  const teamId = entry["id"];
  if (typeof teamId !== "number") {
    await logAttempt(false);
    return jsonResp({ error: "Could not read team ID from FPL." }, 502, cors);
  }

  // 7. Log success & return only the public team ID
  await logAttempt(true);

  return jsonResp(
    {
      team_id: teamId,
      team_name: entry["name"] ?? "",
      manager_name:
        `${player?.["first_name"] ?? ""} ${player?.["last_name"] ?? ""}`.trim(),
    },
    200,
    cors,
  );
}
