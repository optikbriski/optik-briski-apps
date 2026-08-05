-- Normalize legacy tutup-toko rows so Finance ledger + COA stay consistent:
-- APPROVED + CLOSE-* referensi_id (not omzet POS, not COA quarantine).

UPDATE public.finance_transactions
SET
  status_konfirmasi = 'APPROVED',
  referensi_id = CASE
    WHEN referensi_id IS NOT NULL
      AND btrim(referensi_id) <> ''
      AND upper(referensi_id) LIKE 'CLOSE-%'
      THEN referensi_id
    ELSE
      'CLOSE-'
      || coalesce(nullif(btrim(toko_id), ''), 'PUSAT')
      || '-'
      || coalesce(
           nullif(tanggal_transaksi::text, ''),
           to_char(coalesce(created_at, now()), 'YYYY-MM-DD')
         )
      || '-'
      || id::text
  END,
  updated_at = now()
WHERE (
  upper(coalesce(kategori, '')) LIKE '%PENUTUPAN%'
  OR upper(coalesce(kategori, '')) LIKE '%CLOSING%'
)
AND (
  coalesce(status_konfirmasi, '') IS DISTINCT FROM 'APPROVED'
  OR referensi_id IS NULL
  OR btrim(referensi_id) = ''
  OR upper(referensi_id) NOT LIKE 'CLOSE-%'
);
