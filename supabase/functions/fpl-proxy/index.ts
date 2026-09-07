// FPL API Proxy - Production-ready CORS proxy for web clients
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const FPL_BASE_URL = 'https://fantasy.premierleague.com/api';

// Production CORS headers - restrict to your domain in production
const getCorsHeaders = () => {
  const origin = Deno.env.get('ALLOWED_ORIGIN') || '*';
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Cache-Control': 'public, max-age=300', // 5 min cache for FPL data
  };
};

// Simple in-memory cache for responses (5 minutes)
const cache = new Map<string, { data: string; timestamp: number }>();
const CACHE_TTL = 5 * 60 * 1000; // 5 minutes

serve(async (req) => {
  const corsHeaders = getCorsHeaders();

  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // Only allow GET requests for FPL API proxying
  if (req.method !== 'GET') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const url = new URL(req.url);
  const path = url.searchParams.get('path');

  if (!path) {
    return new Response(
      JSON.stringify({ error: 'Missing path parameter' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  // Check cache first
  const cacheKey = `fpl:${path}`;
  const cached = cache.get(cacheKey);
  if (cached && Date.now() - cached.timestamp < CACHE_TTL) {
    return new Response(cached.data, {
      status: 200,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json',
        'X-Cache': 'HIT',
      },
    });
  }

  try {
    const fplUrl = `${FPL_BASE_URL}${path}`;

    // Add timeout to prevent hanging requests
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10000); // 10 second timeout

    const response = await fetch(fplUrl, {
      signal: controller.signal,
      headers: {
        'User-Agent': 'SquadIQ/1.0 (+fpl-proxy)',
      },
    });

    clearTimeout(timeout);
    const data = await response.text();

    // Cache successful responses
    if (response.ok) {
      cache.set(cacheKey, { data, timestamp: Date.now() });
    }

    return new Response(data, {
      status: response.status,
      headers: {
        ...corsHeaders,
        'Content-Type': response.headers.get('Content-Type') || 'application/json',
        'X-Cache': 'MISS',
      },
    });
  } catch (error) {
    const errorMsg = error instanceof Error ? error.message : 'Unknown error';

    // Return error with CORS headers
    return new Response(
      JSON.stringify({ error: errorMsg, type: 'proxy_error' }),
      {
        status: 503,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    );
  }
});
