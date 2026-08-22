/// Scope cek email/NIK saat daftar. Jangan cek lintas merek lewat SELECT
/// (RLS bisa menyembunyikan baris; unik global tetap di SQL 000017).
class RegisterConflict {
  RegisterConflict._();

  static String? tenantScopeId(String? boundTenantId) {
    final t = (boundTenantId ?? '').trim();
    return t.isEmpty ? null : t;
  }
}
