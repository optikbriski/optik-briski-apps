// Kategori filter helpers for Member Belanja Online catalog.
// Chip labels: Frame / Lensa / Lainnya (Product Master). Matching is
// trim + case-insensitive. `Lainnya` means "not Frame and not Lensa".

const kMemberCatalogCats = ['Frame', 'Lensa', 'Lainnya'];

/// Canonical chip value, or null for "Semua" / unknown.
String? canonicalizeMemberCatalogKategori(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return null;
  final lower = t.toLowerCase();
  if (lower == 'semua' || lower == 'all') return null;
  for (final c in kMemberCatalogCats) {
    if (c.toLowerCase() == lower) return c;
  }
  return null;
}

/// Normalized product kategori for comparisons (`frame` / `lensa` / …).
String normalizeMemberProductKategori(Object? raw) =>
    (raw ?? '').toString().trim().toLowerCase();

/// True if product belongs in the Lainnya bucket (non-empty, not Frame/Lensa).
bool memberCatalogIsLainnya(Object? productKategori) {
  final k = normalizeMemberProductKategori(productKategori);
  return k.isNotEmpty && k != 'frame' && k != 'lensa';
}

/// Whether [productKategori] matches catalog filter [filterKategori].
///
/// [filterKategori] null/empty = Semua. Canonical or any case accepted.
bool memberCatalogMatchesKategori(
  Object? productKategori,
  String? filterKategori,
) {
  final filter = canonicalizeMemberCatalogKategori(filterKategori);
  if (filter == null) return true;

  if (filter == 'Lainnya') {
    return memberCatalogIsLainnya(productKategori);
  }
  return normalizeMemberProductKategori(productKategori) ==
      filter.toLowerCase();
}

/// Value for `list_member_catalog.p_kategori`.
///
/// Frame / Lensa / Lainnya → server filter (avoids 300-row cap hiding a bucket).
/// Semua / unknown → null (unscoped).
String? memberCatalogServerKategoriParam(String? filterKategori) {
  final filter = canonicalizeMemberCatalogKategori(filterKategori);
  if (filter == 'Frame' || filter == 'Lensa' || filter == 'Lainnya') {
    return filter;
  }
  return null;
}
