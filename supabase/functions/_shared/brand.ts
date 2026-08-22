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
    const tid = String(tenantId ?? "").trim();
    if (!tid) {
      throw new Error("tenant_id wajib");
    }
    const q = await db
      .from("app_brand")
      .select("display_name, short_name, assistant_name")
      .eq("tenant_id", tid)
      .maybeSingle();
    const data = q.data;
    const name = String(data?.display_name ?? "").trim();
    if (!name) {
      if (tid === OPTIK_TENANT) return fallbackBrand;
      return {
        displayName: "POS",
        shortName: "POS",
        assistantName: "Asisten",
      };
    }
    return {
      displayName: name,
      shortName: String(data?.short_name ?? "").trim() ||
        fallbackBrand.shortName,
      assistantName: String(data?.assistant_name ?? "").trim() ||
        fallbackBrand.assistantName,
    };
  } catch {
    const tid = String(tenantId ?? "").trim();
    if (tid === OPTIK_TENANT || tid === "") return fallbackBrand;
    return {
      displayName: "POS",
      shortName: "POS",
      assistantName: "Asisten",
    };
  }
}
