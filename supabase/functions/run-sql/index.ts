// Temporary admin function to apply RLS policies
// Deploy once, run, then remove
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceKey  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  // Run DDL via PostgREST with service_role
  const statements = [
    `DROP POLICY IF EXISTS "users_insert_own" ON users`,
    `DROP POLICY IF EXISTS "users_update_own" ON users`,
    `CREATE POLICY "users_insert_own" ON users FOR INSERT WITH CHECK (auth_user_id = auth.uid())`,
    `CREATE POLICY "users_update_own" ON users FOR UPDATE USING (auth_user_id = auth.uid())`,
  ];

  const results: string[] = [];

  for (const stmt of statements) {
    try {
      // Use pg REST endpoint with service_role
      const resp = await fetch(`${supabaseUrl}/rest/v1/rpc/run_ddl`, {
        method: 'POST',
        headers: {
          'apikey': serviceKey,
          'Authorization': `Bearer ${serviceKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ ddl: stmt }),
      });
      const text = await resp.text();
      results.push(`${stmt.substring(0, 40)}... => ${resp.status}: ${text}`);
    } catch (e) {
      results.push(`${stmt.substring(0, 40)}... => ERROR: ${e.message}`);
    }
  }

  // Also check policies
  const policiesResp = await fetch(
    `${supabaseUrl}/rest/v1/users?select=id&limit=1`,
    {
      headers: {
        'apikey': serviceKey,
        'Authorization': `Bearer ${serviceKey}`,
      },
    }
  );

  return new Response(JSON.stringify({ results, users_accessible: policiesResp.status }), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
});
