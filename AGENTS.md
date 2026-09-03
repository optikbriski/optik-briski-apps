# AGENTS.md

## Cursor Cloud specific instructions

Rekasa is a **Flutter** app (`optik_b_riski`) with four build flavors from one codebase
(`admin`, `karyawan`, `member`, `store` — see `lib/main_*.dart` and `.vscode/launch.json`),
backed by **Supabase** (Postgres migrations + Deno edge functions in `supabase/`) and a
static company site in `site/`. "Optik B. Riski" is a tenant skin, not the product name.

### Toolchain (already installed in the environment/snapshot)
- Flutter SDK lives at `/opt/flutter`; `flutter` and `dart` are symlinked into `/usr/local/bin`,
  so they are on `PATH` for non-interactive shells (the update script relies on this).
- Dart deps are refreshed by the startup update script (`flutter pub get`). No manual install needed.
- Note: `flutter pub get` auto-adds an `analyzer: exclude:` block to `analysis_options.yaml`
  (build/platform dirs). This is harmless and can be left or reverted; it is not a repo change to commit.

### Lint / test / build / run (Flutter app — primary product)
- Lint: `flutter analyze` (clean except one pre-existing `unawaited_return_in_try_block` warning).
- Test: `flutter test` (463 unit/widget tests, all passing).
- Build web (as Vercel does): see `scripts/vercel_build.sh` — `flutter build web -t lib/main_admin.dart`
  with `--dart-define`s. Dev run: `flutter run -d web-server --web-port=8080 -t lib/main_admin.dart`
  plus the dart-defines below (`.vscode/launch.json` reads `.dart_define.<flavor>.json`, which are
  gitignored and not present, so pass `--dart-define`s directly).

### Non-obvious: the app cannot boot without Supabase credentials
`lib/shared/bootstrap.dart` calls `Supabase.initialize` with `SUPABASE_URL` /
`SUPABASE_ANON_KEY` (or `SUPABASE_PUBLISHABLE_KEY`) from `--dart-define`. With empty values the
app fails to start (it does not just warn). To run the app end-to-end you need either:
- a hosted Supabase project's URL + anon key (the repo's intended workflow — README + `vercel_build.sh`), or
- a local Supabase stack (self-service; see below).

### Running a local Supabase stack (self-service, no external secrets)
Docker (v29.x) and the `supabase` CLI are installed, but there are important caveats:
- The Docker daemon is **not** auto-started. Start it and open the socket:
  `sudo dockerd > /tmp/dockerd.log 2>&1 &` then `sudo chmod 666 /var/run/docker.sock`.
- `iptables` must be the **legacy** backend (pinned via `update-alternatives --set iptables
  /usr/sbin/iptables-legacy`). If the nft backend is active, Docker can create the default bridge
  but **custom network creation fails** (`DOCKER-FORWARD ... No chain/target/match`). Restart
  `dockerd` after pinning legacy so it rebuilds its chains.
- `supabase/config.toml` is **functions-only** (no `project_id`/`[db]`/`[auth]`), so `supabase start`
  cannot run against the repo directly. Use a scratch workdir: `supabase init` in an empty dir,
  then point its `supabase/migrations` at the repo's migrations.
- The 187 migrations do **not** apply cleanly on a fresh DB (pre-existing bugs — do not "fix" the repo):
  `20260724000001_sync_absen_poin_logs.sql` uses `attendance_logs.late_penalty_points` before it is
  added in `20260724000003_...`, and `20260801000001_member_inbox_demo_promos.sql` inserts a NULL into
  a NOT-NULL column. Bring up an empty stack (no migrations), then apply the repo migrations manually
  with `psql -v ON_ERROR_STOP=0` (errors on those two are benign). Because they are applied as the
  `postgres` role, also grant PostgREST roles:
  `grant select,insert,update,delete on all tables in schema public to authenticated;`
  `grant select on all tables in schema public to anon;` (plus `usage` on schema/sequences and
  `execute` on functions), otherwise authenticated queries hit `permission denied`.
- Get local URL/keys with `supabase status`. Run the app with
  `--dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=<anon key>`.

### Verified hello-world (admin flavor)
Admin has a **Password** login mode (`lib/apps/admin/login_page.dart`) using standard Supabase Auth
(no edge function). To exercise it: create an auth user via the GoTrue admin API
(`POST /auth/v1/admin/users` with the service_role key), then insert a `public.profiles` row
(`role='platform'`, `is_platform=true`, `toko_id='PUSAT'`, `id`=the auth uid) and ensure a
`public.toko_id` row `id='PUSAT'` exists. Logging in as that user lands on the admin dashboard.
Note: right after login the admin web briefly shows a splash/reload (black screen with a spinning
cube) before settling back on the dashboard — the dashboard is fully functional.
