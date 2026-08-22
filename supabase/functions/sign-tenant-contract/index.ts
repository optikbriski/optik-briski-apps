// @ts-ignore
declare const Deno: any;

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const token = String(body.token ?? body.public_token ?? "").trim();
    const signerName = String(body.signer_name ?? "").trim();
    const agree = body.agree === true;
    const signerEmail = String(body.signer_email ?? "").trim();
    if (!token) {
      return new Response(
        JSON.stringify({ ok: false, error: "Tautan kontrak tidak valid" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const forwarded = String(req.headers.get("x-forwarded-for") ?? "");
    const ip = forwarded.split(",")[0]?.trim() ||
      String(req.headers.get("cf-connecting-ip") ?? "").trim() ||
      null;
    const ua = String(req.headers.get("user-agent") ?? "").slice(0, 400);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY") ??
      Deno.env.get("SUPABASE_PUBLISHABLE_KEY")!;
    const db = createClient(supabaseUrl, anon);
    const { data, error } = await db.rpc("sign_tenant_contract", {
      p_token: token,
      p_signer_name: signerName,
      p_agree: agree,
      p_signer_email: signerEmail || null,
      p_ip: ip,
      p_user_agent: ua,
    });
    if (error) {
      return new Response(
        JSON.stringify({ ok: false, error: error.message }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }
    return new Response(JSON.stringify(data ?? { ok: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(
      JSON.stringify({ ok: false, error: String(e) }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
