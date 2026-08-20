export type AppBrand = {
  displayName: string;
  shortName: string;
  assistantName: string;
};

export const fallbackBrand: AppBrand = {
  displayName: "Optik B. Riski",
  shortName: "OBR",
  assistantName: "OBRA",
};

const OPTIK_TENANT = "00000000-0000-0000-0000-000000000001";

export async function loadBrand(
  db: { from: (table: string) => any },
  tenantId?: string | null,
): Promise<AppBrand> {
  try {
    const tid = String(tenantId ?? "").trim() || OPTIK_TENANT;
    let q = await db
      .from("app_brand")
      .select("display_name, short_name, assistant_name")
      .eq("tenant_id", tid)
      .maybeSingle();
    if (!q.data) {
      q = await db
        .from("app_brand")
        .select("display_name, short_name, assistant_name")
        .eq("id", "default")
        .maybeSingle();
    }
    const data = q.data;
    const name = String(data?.display_name ?? "").trim();
    if (!name) return fallbackBrand;
    return {
      displayName: name,
      shortName: String(data?.short_name ?? "").trim() ||
        fallbackBrand.shortName,
      assistantName: String(data?.assistant_name ?? "").trim() ||
        fallbackBrand.assistantName,
    };
  } catch {
    return fallbackBrand;
  }
}
