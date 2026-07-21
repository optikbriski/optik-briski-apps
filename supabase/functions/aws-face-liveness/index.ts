// @ts-ignore
declare const Deno: any;

/**
 * AWS Rekognition Face Liveness — Edge Function
 *
 * Actions (POST JSON, Authorization: Bearer <user JWT>):
 *   - create_session  → CreateFaceLivenessSession + temporary client credentials
 *   - get_results     → GetFaceLivenessSessionResults (confidence / reference image)
 *   - credentials     → temporary creds only (STS AssumeRole or Cognito Identity Pool)
 *
 * GET /ui  → minimal Amplify FaceLivenessDetectorCore HTML (WebView host)
 *
 * Required secrets (Supabase → Edge Functions → Secrets):
 *   AWS_ACCESS_KEY_ID
 *   AWS_SECRET_ACCESS_KEY
 *   AWS_REGION                    (e.g. ap-southeast-1)
 *
 * Client streaming credentials (pick ONE):
 *   AWS_LIVENESS_ROLE_ARN        (preferred) IAM role trusted by the IAM user,
 *                                with ONLY rekognition:StartFaceLivenessSession
 *   — OR —
 *   AWS_COGNITO_IDENTITY_POOL_ID Cognito Identity Pool (unauth) whose role has
 *                                rekognition:StartFaceLivenessSession
 *
 * Optional:
 *   AWS_LIVENESS_MIN_CONFIDENCE  default 90
 *
 * IAM (backend user/role used by this function):
 *   rekognition:CreateFaceLivenessSession
 *   rekognition:GetFaceLivenessSessionResults
 *   sts:AssumeRole  (if using AWS_LIVENESS_ROLE_ARN)
 *
 * AWS Console checklist:
 *   1. Enable Amazon Rekognition Face Liveness in the chosen region
 *   2. Create IAM user/keys for this function (above permissions)
 *   3a. Create role AWS_LIVENESS_ROLE_ARN for StartFaceLivenessSession only,
 *       trust the IAM user / account to AssumeRole
 *   3b. OR create Cognito Identity Pool (guest access) + attach StartFaceLivenessSession
 *   4. Set secrets above, then: supabase functions deploy aws-face-liveness
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  CreateFaceLivenessSessionCommand,
  GetFaceLivenessSessionResultsCommand,
  RekognitionClient,
} from "npm:@aws-sdk/client-rekognition@3.758.0";
import {
  AssumeRoleCommand,
  STSClient,
} from "npm:@aws-sdk/client-sts@3.758.0";
import {
  CognitoIdentityClient,
  GetCredentialsForIdentityCommand,
  GetIdCommand,
} from "npm:@aws-sdk/client-cognito-identity@3.758.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

type Body = {
  action?: "create_session" | "get_results" | "credentials";
  session_id?: string;
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function getAwsConfig() {
  const accessKeyId = Deno.env.get("AWS_ACCESS_KEY_ID");
  const secretAccessKey = Deno.env.get("AWS_SECRET_ACCESS_KEY");
  const region = Deno.env.get("AWS_REGION") || "ap-southeast-1";
  if (!accessKeyId || !secretAccessKey) {
    throw new Error(
      "AWS secrets belum di-set. Isi AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION di Supabase Edge Function Secrets.",
    );
  }
  return { accessKeyId, secretAccessKey, region };
}

function getRekognitionClient() {
  const { accessKeyId, secretAccessKey, region } = getAwsConfig();
  return new RekognitionClient({
    region,
    credentials: { accessKeyId, secretAccessKey },
  });
}

function minConfidence(): number {
  const raw = Number(Deno.env.get("AWS_LIVENESS_MIN_CONFIDENCE") ?? 90);
  return Number.isFinite(raw) ? raw : 90;
}

async function getStreamingCredentials(): Promise<{
  accessKeyId: string;
  secretAccessKey: string;
  sessionToken: string;
  expiration?: string;
  provider: "sts_assume_role" | "cognito_identity";
}> {
  const { accessKeyId, secretAccessKey, region } = getAwsConfig();
  const roleArn = (Deno.env.get("AWS_LIVENESS_ROLE_ARN") || "").trim();
  const identityPoolId = (Deno.env.get("AWS_COGNITO_IDENTITY_POOL_ID") || "")
    .trim();

  if (roleArn) {
    const sts = new STSClient({
      region,
      credentials: { accessKeyId, secretAccessKey },
    });
    const assumed = await sts.send(
      new AssumeRoleCommand({
        RoleArn: roleArn,
        RoleSessionName: `face-liveness-${Date.now()}`,
        DurationSeconds: 900,
      }),
    );
    const c = assumed.Credentials;
    if (!c?.AccessKeyId || !c.SecretAccessKey || !c.SessionToken) {
      throw new Error("STS AssumeRole tidak mengembalikan credentials.");
    }
    return {
      accessKeyId: c.AccessKeyId,
      secretAccessKey: c.SecretAccessKey,
      sessionToken: c.SessionToken,
      expiration: c.Expiration?.toISOString?.() ?? undefined,
      provider: "sts_assume_role",
    };
  }

  if (identityPoolId) {
    const cognito = new CognitoIdentityClient({
      region,
      credentials: { accessKeyId, secretAccessKey },
    });
    const idRes = await cognito.send(
      new GetIdCommand({ IdentityPoolId: identityPoolId }),
    );
    if (!idRes.IdentityId) {
      throw new Error("Cognito GetId gagal (IdentityId kosong).");
    }
    const credRes = await cognito.send(
      new GetCredentialsForIdentityCommand({ IdentityId: idRes.IdentityId }),
    );
    const c = credRes.Credentials;
    if (!c?.AccessKeyId || !c.SecretKey || !c.SessionToken) {
      throw new Error(
        "Cognito GetCredentialsForIdentity tidak mengembalikan credentials.",
      );
    }
    return {
      accessKeyId: c.AccessKeyId,
      secretAccessKey: c.SecretKey,
      sessionToken: c.SessionToken,
      expiration: c.Expiration
        ? (c.Expiration instanceof Date
          ? c.Expiration.toISOString()
          : new Date(Number(c.Expiration) * 1000).toISOString())
        : undefined,
      provider: "cognito_identity",
    };
  }

  throw new Error(
    "Kredensial streaming belum dikonfigurasi. Set AWS_LIVENESS_ROLE_ARN (STS) atau AWS_COGNITO_IDENTITY_POOL_ID di secrets.",
  );
}

function bytesToBase64(bytes?: Uint8Array | null): string | null {
  if (!bytes || bytes.length === 0) return null;
  let bin = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    bin += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(bin);
}

function livenessUiHtml(): string {
  // FaceLivenessDetectorCore + custom credentialProvider (no Amplify Auth / Cognito in the page).
  // Flutter WebView injects window.__startLiveness({ sessionId, region, credentials }).
  return `<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no" />
  <title>AWS Face Liveness</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@aws-amplify/ui-react-liveness@3.3.2/dist/styles.css" />
  <style>
    html, body, #root { margin: 0; height: 100%; background: #0f172a; color: #e2e8f0; font-family: system-ui, sans-serif; }
    .boot { display:flex; flex-direction:column; align-items:center; justify-content:center; height:100%; gap:12px; padding:24px; text-align:center; }
    .err { color: #fca5a5; white-space: pre-wrap; }
    .spin { width:36px; height:36px; border:3px solid #334155; border-top-color:#38bdf8; border-radius:50%; animation: r 0.8s linear infinite; }
    @keyframes r { to { transform: rotate(360deg); } }
  </style>
</head>
<body>
  <div id="root"><div class="boot"><div class="spin"></div><div>Menyiapkan AWS Face Liveness…</div></div></div>
  <script type="importmap">
  {
    "imports": {
      "react": "https://esm.sh/react@18.3.1",
      "react/jsx-runtime": "https://esm.sh/react@18.3.1/jsx-runtime",
      "react-dom": "https://esm.sh/react-dom@18.3.1",
      "react-dom/client": "https://esm.sh/react-dom@18.3.1/client",
      "@aws-amplify/ui-react-liveness": "https://esm.sh/@aws-amplify/ui-react-liveness@3.3.2?deps=react@18.3.1,react-dom@18.3.1&external=react,react-dom"
    }
  }
  </script>
  <script type="module">
    import React from 'react';
    import { createRoot } from 'react-dom/client';
    import { FaceLivenessDetectorCore } from '@aws-amplify/ui-react-liveness';

    const root = createRoot(document.getElementById('root'));

    function showBoot(msg) {
      root.render(React.createElement('div', { className: 'boot' },
        React.createElement('div', { className: 'spin' }),
        React.createElement('div', null, msg || 'Menyiapkan…')
      ));
    }

    function showError(msg) {
      root.render(React.createElement('div', { className: 'boot' },
        React.createElement('div', { className: 'err' }, String(msg || 'Error'))
      ));
      try {
        if (window.LivenessBridge && window.LivenessBridge.postMessage) {
          window.LivenessBridge.postMessage(JSON.stringify({ type: 'error', message: String(msg || 'Error') }));
        }
      } catch (_) {}
    }

    function notify(payload) {
      try {
        if (window.LivenessBridge && window.LivenessBridge.postMessage) {
          window.LivenessBridge.postMessage(JSON.stringify(payload));
        }
      } catch (_) {}
    }

    window.__startLiveness = function (cfg) {
      try {
        if (!cfg || !cfg.sessionId || !cfg.region || !cfg.credentials) {
          showError('Konfigurasi liveness tidak lengkap.');
          return;
        }
        const creds = cfg.credentials;
        const credentialProvider = async () => ({
          accessKeyId: creds.accessKeyId,
          secretAccessKey: creds.secretAccessKey,
          sessionToken: creds.sessionToken,
        });

        root.render(React.createElement(FaceLivenessDetectorCore, {
          sessionId: cfg.sessionId,
          region: cfg.region,
          onAnalysisComplete: async () => {
            notify({ type: 'complete', sessionId: cfg.sessionId });
          },
          onError: (err) => {
            const msg = (err && (err.state || err.message || err.error)) || 'Liveness gagal';
            notify({ type: 'error', message: String(msg), sessionId: cfg.sessionId });
            showError(msg);
          },
          onUserCancel: () => {
            notify({ type: 'cancel', sessionId: cfg.sessionId });
          },
          config: { credentialProvider },
        }));
      } catch (e) {
        showError(e && e.message ? e.message : String(e));
      }
    };

    showBoot('Menunggu sesi dari aplikasi…');
    notify({ type: 'ready' });
  </script>
</body>
</html>`;
}

async function requireUser(req: Request) {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return { error: json(401, { error: "Unauthorized" }) };

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !supabaseAnon) {
    throw new Error("SUPABASE_URL / SUPABASE_ANON_KEY missing.");
  }

  const userClient = createClient(supabaseUrl, supabaseAnon, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData.user) {
    return { error: json(401, { error: "JWT tidak valid. Login ulang." }) };
  }
  return { user: authData.user };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const url = new URL(req.url);
    const path = url.pathname.replace(/\/+$/, "");

    // Hosted Amplify UI for Flutter WebView (no auth — session/creds injected by app).
    if (
      req.method === "GET" &&
      (path.endsWith("/ui") || path.endsWith("/aws-face-liveness/ui"))
    ) {
      return new Response(livenessUiHtml(), {
        status: 200,
        headers: {
          ...corsHeaders,
          "Content-Type": "text/html; charset=utf-8",
          "Cache-Control": "no-store",
        },
      });
    }

    if (req.method !== "POST") {
      return json(405, { error: "Method not allowed" });
    }

    const auth = await requireUser(req);
    if ("error" in auth && auth.error) return auth.error;

    const body = (await req.json()) as Body;
    const action = body.action;
    const { region } = getAwsConfig();

    if (action === "credentials") {
      const creds = await getStreamingCredentials();
      return json(200, {
        ok: true,
        region,
        credentials: {
          accessKeyId: creds.accessKeyId,
          secretAccessKey: creds.secretAccessKey,
          sessionToken: creds.sessionToken,
          expiration: creds.expiration ?? null,
        },
        provider: creds.provider,
      });
    }

    if (action === "create_session") {
      const rekognition = getRekognitionClient();
      const created = await rekognition.send(
        new CreateFaceLivenessSessionCommand({
          Settings: {
            AuditImagesLimit: 4,
          },
        }),
      );
      const sessionId = created.SessionId;
      if (!sessionId) {
        return json(500, { error: "CreateFaceLivenessSession tidak mengembalikan SessionId." });
      }

      const creds = await getStreamingCredentials();
      return json(200, {
        ok: true,
        session_id: sessionId,
        region,
        min_confidence: minConfidence(),
        credentials: {
          accessKeyId: creds.accessKeyId,
          secretAccessKey: creds.secretAccessKey,
          sessionToken: creds.sessionToken,
          expiration: creds.expiration ?? null,
        },
        credential_provider: creds.provider,
        ui_path: "aws-face-liveness/ui",
      });
    }

    if (action === "get_results") {
      const sessionId = (body.session_id || "").trim();
      if (!sessionId) {
        return json(400, { error: "session_id wajib" });
      }

      const rekognition = getRekognitionClient();
      const results = await rekognition.send(
        new GetFaceLivenessSessionResultsCommand({ SessionId: sessionId }),
      );

      const confidence = results.Confidence ?? 0;
      const status = results.Status || "UNKNOWN";
      const threshold = minConfidence();
      const passed = status === "SUCCEEDED" && confidence >= threshold;
      const referenceBase64 = bytesToBase64(
        results.ReferenceImage?.Bytes as Uint8Array | undefined,
      );

      if (!passed) {
        return json(422, {
          ok: false,
          passed: false,
          session_id: sessionId,
          status,
          confidence,
          min_confidence: threshold,
          reference_image_base64: referenceBase64,
          error:
            status !== "SUCCEEDED"
              ? `Sesi liveness status ${status}. Coba lagi dengan wajah jelas dan pencahayaan cukup.`
              : `Skor liveness ${confidence.toFixed(1)} di bawah ambang ${threshold}.`,
        });
      }

      return json(200, {
        ok: true,
        passed: true,
        session_id: sessionId,
        status,
        confidence,
        min_confidence: threshold,
        reference_image_base64: referenceBase64,
        provider: "aws",
      });
    }

    return json(400, {
      error: "action harus create_session, get_results, atau credentials",
    });
  } catch (e: any) {
    console.error("aws-face-liveness error:", e);
    return json(500, {
      error: e?.message || String(e),
    });
  }
});
