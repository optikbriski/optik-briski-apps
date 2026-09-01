-- Probe-only. Tidak mengubah data produksi.
-- Tempel di SQL Editor setelah sop_ig_story_live_apply.sql.

select
  (select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'toko_id' and column_name = 'ig_username') as col_ig_username,
  (select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'toko_id' and column_name = 'ig_user_id') as col_ig_user_id,
  (select count(*) from information_schema.tables
    where table_schema = 'public' and table_name = 'sop_ig_story_cache') as tbl_ig_cache,
  (select count(*) from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'toko_id_normalize_ig') as fn_normalize_ig;

select id, left(coalesce(ig_username, ''), 40) as ig_username,
       length(coalesce(ig_user_id, '')) as ig_id_len
from public.toko_id
order by id
limit 40;
