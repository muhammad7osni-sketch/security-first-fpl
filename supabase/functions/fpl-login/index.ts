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
//
// The password travels over HTTPS to this function and is immediately
// discarded after the FPL login call — it is never written to any log,
// database, or storage. Only the public integer team ID is returned.
//
// --no-verify-jwt: this endpoint is called before the user has a
// Supabase session (they're linking their FPL account), so JWT
// verification would always fail. Rate limiting via Supabase's
// built-in function invocation limits applies.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const FPL_LOGIN_URL = "https://users.premierleague.com/accounts/login/";
const FPL_ME_URL    = "https://fantasy.premierleague.com/api/me/";

const ALLOWED_ORIGIN = Deno.env.get("ALLOWED_WEB_ORIGIN") ?? "*";
const MAX_LOGIN_ATTEMPTS = 5;
const ATTEMPT_WINDOW_HOURS = 1;

const corsHeaders = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function getClientIp(req: Request): string {
  return (
    req.headers.get("cf-connecting-ip") ??
    req.headers.get("x-forwarded-for")?.split(",")[0] ??
    "unknown"
  ).trim();
}

serve(async (req) => {
  // ── CORS preflight ────────────────────────────────────────────────────
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const clientIp = getClientIp(req);

  // ── Parse request body ────────────────────────────────────────────────
  let email: string;
  let password: string;

  try {
    const body = await req.json();
    email    = (body.email    ?? "").trim();
    password = (body.password ?? "").trim();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  if (!email || !password) {
    return json({ error: "email and password are required" }, 400);
  }

  // ── Validate email format ────────────────────────────────────────────
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return json({ error: "Invalid email format" }, 400);
  }

  // ── Rate limiting (check attempt count) ──────────────────────────────
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const oneHourAgo = new Date(Date.now() - ATTEMPT_WINDOW_HOURS * 60 * 60 * 1000)
    .toISOString();

  const { data: recentAttempts, error: queryError } = await supabase
    .from("fpl_login_attempts")
    .select("id")
    .eq("ip_address", clientIp)
    .gte("attempted_at", oneHourAgo);

  if (queryError) {
    console.error("Rate limit check failed:", queryError);
    // Don't block on DB error, but log it
  }

  if ((recentAttempts?.length ?? 0) >= MAX_LOGIN_ATTEMPTS) {
    return json(
      { error: "Too many login attempts. Try again in 1 hour." },
      429,
    );
  }

  // ── Step 1: POST credentials to FPL login ────────────────────────────
  let loginResponse: Response;
  try {
    const formData = new URLSearchParams({
      login:        email,
      password:     password,
      app:          "plfpl-web",
      redirect_uri: "https://fantasy.premierleague.com/",
    });

    loginResponse = await fetch(FPL_LOGIN_URL, {
      method:   "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "Referer":  "https://fantasy.premierleague.com/",
        "Origin":   "https://fantasy.premierleague.com",
        "User-Agent": "Mozilla/5.0 (compatible; SquadIQ/0.1)",
      },
      body:     formData.toString(),
      redirect: "manual",
    });
  } catch (e) {
    // Log failed attempt
    await supabase.from("fpl_login_attempts").insert({
      ip_address: clientIp,
      success: false,
    }).catch(() => {}); // Don't block on log error
    
    return json({ error: `Network error reaching FPL: ${String(e)}` }, 502);
  }

  // ── Step 2: Extract pl_profile cookie ────────────────────────────────
  const setCookieHeaders = loginResponse.headers.getSetCookie?.() ??
    [loginResponse.headers.get("set-cookie") ?? ""].filter(Boolean);

  let plProfileCookie: string | null = null;
  for (const raw of setCookieHeaders) {
    const parts = raw.split(";");
    for (const part of parts) {
      const trimmed = part.trim();
      if (trimmed.startsWith("pl_profile=")) {
        plProfileCookie = trimmed;
        break;
      }
    }
    if (plProfileCookie) break;
  }

  if (!plProfileCookie) {
    // Log failed attempt
    await supabase.from("fpl_login_attempts").insert({
      ip_address: clientIp,
      success: false,
    }).catch(() => {});
    
    return json(
      { error: "FPL login failed. Check your email and password." },
      401,
    );
  }

  // ── Step 3: Call /me/ with the session cookie ─────────────────────────
  let meResponse: Response;
  try {
    meResponse = await fetch(FPL_ME_URL, {
      headers: {
        "Cookie":     plProfileCookie,
        "Referer":    "https://fantasy.premierleague.com/",
        "User-Agent": "Mozilla/5.0 (compatible; SquadIQ/0.1)",
      },
    });
  } catch (e) {
    await supabase.from("fpl_login_attempts").insert({
      ip_address: clientIp,
      success: false,
    }).catch(() => {});
    
    return json({ error: `Network error fetching team info: ${String(e)}` }, 502);
  }

  // ── Step 4: Parse team ID ─────────────────────────────────────────────
  let meData: Record<string, unknown>;
  try {
    meData = await meResponse.json();
  } catch {
    await supabase.from("fpl_login_attempts").insert({
      ip_address: clientIp,
      success: false,
    }).catch(() => {});
    
    return json({ error: "Unexpected response from FPL. Please try again." }, 502);
  }

  const entry  = meData["entry"]  as Record<string, unknown> | null;
  const player = meData["player"] as Record<string, unknown> | null;

  if (!entry) {
    await supabase.from("fpl_login_attempts").insert({
      ip_address: clientIp,
      success: false,
    }).catch(() => {});
    
    return json(
      {
        error:
          "No FPL team found for this account. " +
          "Create a team at fantasy.premierleague.com first.",
      },
      404,
    );
  }

  const teamId = entry["id"];
  if (typeof teamId !== "number") {
    await supabase.from("fpl_login_attempts").insert({
      ip_address: clientIp,
      success: false,
    }).catch(() => {});
    
    return json({ error: "Could not read team ID from FPL. Please try again." }, 502);
  }

  // ── Step 5: Log successful attempt ────────────────────────────────────
  await supabase.from("fpl_login_attempts").insert({
    ip_address: clientIp,
    success: true,
  }).catch(() => {}); // Don't block on log error

  // ── Step 6: Return ONLY the public team ID ────────────────────────────
  return json({
    team_id:    teamId,
    team_name:  entry["name"]          ?? "",
    manager_name: `${player?.["first_name"] ?? ""} ${player?.["last_name"] ?? ""}`.trim(),
  });
});
