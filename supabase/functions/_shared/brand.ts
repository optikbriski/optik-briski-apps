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

export async function loadBrand(
  db: { from: (table: string) => any },
): Promise<AppBrand> {
  try {
    const { data } = await db
      .from("app_brand")
      .select("display_name, short_name, assistant_name")
      .eq("id", "default")
      .maybeSingle();
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
