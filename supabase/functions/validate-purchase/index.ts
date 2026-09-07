// supabase/functions/validate-purchase/index.ts
//
// Deploy with: supabase functions deploy validate-purchase
// Needs a service-role client (not the anon key) since it writes to
// `purchases` and `coin_transactions`, which the authenticated role has
// no insert grant on by design (schema.sql's RLS policy, plan section
// 5's anti-double-spend requirement).
//
// IMPORTANT - THIS IS A STUB, NOT PRODUCTION-READY:
// Real purchase validation requires calling Apple's App Store Server
// API or Google Play Developer API with the receipt/token from the
// client, verifying it against YOUR app's bundle ID and product IDs,
// and checking it hasn't already been consumed (replay protection).
// None of that is implemented here. This stub only checks that a
// non-empty receipt string was provided, then credits the purchase
// unconditionally - it is NOT safe to deploy as-is. Treat the
// `// TODO: real receipt validation` block below as the actual
// remaining work.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing auth" }), { status: 401 });
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    global: { headers: { Authorization: authHeader } },
  });

  // Resolve the calling user from their JWT (anon-key client call, but
  // this function itself runs with the service role for the writes).
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData?.user) {
    return new Response(JSON.stringify({ error: "Invalid session" }), { status: 401 });
  }

  const { product_id, receipt } = await req.json();
  if (!product_id || typeof receipt !== "string" || !receipt.trim()) {
    return new Response(JSON.stringify({ error: "product_id and receipt are required" }), {
      status: 400,
    });
  }

  // TODO: real receipt validation.
  // - Apple: POST to https://buy.itunes.apple.com/verifyReceipt (prod)
  //   or the sandbox URL, with your shared secret; check status == 0
  //   and the product id matches.
  // - Google Play: use the Play Developer API
  //   (purchases.products.get) with a service account to verify
  //   `purchaseState` and `consumptionState`.
  // - Either way: check the receipt/order id hasn't already been
  //   recorded in `purchases.receipt_ref` before crediting again.
  const isValid = receipt.trim().length > 0;

  const { data: appUserRow } = await supabase
    .from("users")
    .select("id")
    .eq("auth_user_id", userData.user.id)
    .single();

  if (!appUserRow) {
    return new Response(JSON.stringify({ error: "App user not found" }), { status: 404 });
  }

  const { data: product } = await supabase
    .from("store_products")
    .select("*")
    .eq("id", product_id)
    .single();

  if (!product) {
    return new Response(JSON.stringify({ error: "Unknown product" }), { status: 404 });
  }

  if (!isValid) {
    await supabase.from("purchases").insert({
      user_id: appUserRow.id,
      product_id,
      receipt_ref: receipt,
      status: "failed",
    });
    return new Response(JSON.stringify({ status: "failed" }), { status: 200 });
  }

  await supabase.from("purchases").insert({
    user_id: appUserRow.id,
    product_id,
    receipt_ref: receipt,
    status: "validated",
  });

  if (product.price_coins) {
    // Coin-priced product: no cash purchase to credit here, this branch
    // exists mainly for real-money products below.
  }

  if (product.price_money_cents) {
    // Credit a fixed coin bundle for a real-money purchase. A real
    // implementation would look up how many coins this specific
    // product grants rather than assuming a 1:1 cents-to-coins ratio.
    const coinsGranted = Math.round(product.price_money_cents / 10);

    await supabase.from("coin_transactions").insert({
      wallet_id: appUserRow.id,
      amount: coinsGranted,
      type: "purchase",
      reference_id: product_id,
    });

    // wallets.coin_balance is a maintained cache column, not derived
    // automatically - keep it in sync in the same transaction-ish
    // sequence as the ledger insert above. A real implementation should
    // wrap both writes in a single Postgres function/transaction rather
    // than two sequential calls from here.
    const { data: wallet } = await supabase
      .from("wallets")
      .select("coin_balance")
      .eq("user_id", appUserRow.id)
      .single();

    await supabase
      .from("wallets")
      .upsert({
        user_id: appUserRow.id,
        coin_balance: (wallet?.coin_balance ?? 0) + coinsGranted,
      });
  }

  return new Response(JSON.stringify({ status: "validated" }), { status: 200 });
});
