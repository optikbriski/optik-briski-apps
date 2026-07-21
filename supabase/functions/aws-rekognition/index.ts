// @ts-ignore
declare const Deno: any;

/**
 * AWS Rekognition CompareFaces / IndexFaces untuk absensi.
 * Face Liveness (anti-spoof) ada di Edge Function terpisah: aws-face-liveness.
 *
 * Secrets: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  CompareFacesCommand,
  CreateCollectionCommand,
  IndexFacesCommand,
  RekognitionClient,
} from "npm:@aws-sdk/client-rekognition@3.758.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const COLLECTION_ID = "optik-briski-attendance";
const DEFAULT_THRESHOLD = 90;

type Body = {
  action?: "enroll" | "compare";
  karyawan_id?: string;
  image_base64?: string;
  source_image_url?: string;
  similarity_threshold?: number;
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function decodeBase64Image(imageBase64: string): Uint8Array {
  const cleaned = imageBase64.includes(",")
    ? imageBase64.split(",").pop()!
    : imageBase64;
  const bin = atob(cleaned);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

function getRekognitionClient(): RekognitionClient {
  const accessKeyId = Deno.env.get("AWS_ACCESS_KEY_ID");
  const secretAccessKey = Deno.env.get("AWS_SECRET_ACCESS_KEY");
  const region = Deno.env.get("AWS_REGION") || "ap-southeast-1";

  if (!accessKeyId || !secretAccessKey) {
    throw new Error(
      "AWS secrets belum di-set. Isi AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION di Supabase Edge Function Secrets.",
    );
  }

  return new RekognitionClient({
    region,
    credentials: { accessKeyId, secretAccessKey },
  });
}

async function ensureCollection(client: RekognitionClient) {
  try {
    await client.send(
      new CreateCollectionCommand({ CollectionId: COLLECTION_ID }),
    );
  } catch (e: any) {
    const name = e?.name || e?.Code || "";
    if (
      name !== "ResourceAlreadyExistsException" &&
      !String(e?.message || "").includes("already exists")
    ) {
      throw e;
    }
  }
}

async function fetchImageBytes(url: string): Promise<Uint8Array> {
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`Gagal unduh foto terdaftar (${res.status}).`);
  }
  return new Uint8Array(await res.arrayBuffer());
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return json(405, { error: "Method not allowed" });
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json(401, { error: "Unauthorized" });
    }

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
      return json(401, { error: "JWT tidak valid. Login ulang." });
    }

    const body = (await req.json()) as Body;
    const action = body.action;
    const karyawanId = (body.karyawan_id || "").trim();
    const imageBase64 = body.image_base64 || "";
    const threshold = Number(body.similarity_threshold ?? DEFAULT_THRESHOLD);

    if (!action || !["enroll", "compare"].includes(action)) {
      return json(400, { error: "action harus enroll atau compare" });
    }
    if (!karyawanId) {
      return json(400, { error: "karyawan_id wajib" });
    }
    if (!imageBase64) {
      return json(400, { error: "image_base64 wajib" });
    }

    const liveBytes = decodeBase64Image(imageBase64);
    if (liveBytes.length < 1000) {
      return json(400, { error: "Foto terlalu kecil / rusak." });
    }

    const rekognition = getRekognitionClient();

    if (action === "enroll") {
      await ensureCollection(rekognition);

      const indexed = await rekognition.send(
        new IndexFacesCommand({
          CollectionId: COLLECTION_ID,
          Image: { Bytes: liveBytes },
          ExternalImageId: karyawanId.replace(/[^a-zA-Z0-9_.\-:]/g, "_"),
          DetectionAttributes: ["DEFAULT"],
          MaxFaces: 1,
          QualityFilter: "AUTO",
        }),
      );

      const face = indexed.FaceRecords?.[0]?.Face;
      if (!face?.FaceId) {
        return json(422, {
          error:
            "Wajah tidak terdeteksi AWS. Coba pencahayaan lebih baik, wajah menghadap kamera.",
        });
      }

      return json(200, {
        ok: true,
        action: "enroll",
        face_id: face.FaceId,
        confidence: face.Confidence ?? null,
        collection_id: COLLECTION_ID,
      });
    }

    // compare
    const sourceUrl = (body.source_image_url || "").trim();
    if (!sourceUrl) {
      return json(400, {
        error: "source_image_url wajib untuk compare (foto wajah terdaftar).",
      });
    }

    const sourceBytes = await fetchImageBytes(sourceUrl);
    const compared = await rekognition.send(
      new CompareFacesCommand({
        SourceImage: { Bytes: sourceBytes },
        TargetImage: { Bytes: liveBytes },
        SimilarityThreshold: threshold,
      }),
    );

    const best = (compared.FaceMatches || [])
      .slice()
      .sort((a, b) => (b.Similarity || 0) - (a.Similarity || 0))[0];

    const similarity = best?.Similarity ?? 0;
    const matched = similarity >= threshold;

    if (!matched) {
      return json(422, {
        ok: false,
        action: "compare",
        matched: false,
        similarity,
        threshold,
        error:
          `Wajah tidak cocok (kemiripan ${similarity.toFixed(1)}%, min ${threshold}%).`,
      });
    }

    return json(200, {
      ok: true,
      action: "compare",
      matched: true,
      similarity,
      threshold,
      karyawan_id: karyawanId,
    });
  } catch (e: any) {
    console.error("aws-rekognition error:", e);
    return json(500, {
      error: e?.message || String(e),
    });
  }
});
