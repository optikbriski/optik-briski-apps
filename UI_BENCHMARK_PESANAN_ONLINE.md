# UI Benchmark — Pesanan Online (Admin)

Standar acuan desain untuk menyelaraskan fitur Admin lain.
Sumber visual: layar **Pesanan online** saat appearance **Kombo Terang** (`AdminAppearanceMode.komboLight`).

Frozen Lake bukan acuan halaman ini. Nilai hex di bawah adalah swatch Kombo Terang di `lib/shared/admin_appearance.dart`, plus token semantik yang tidak berganti mode di `lib/shared/theme.dart`.

Kode aplikasi tidak diubah. Dokumen ini hanya membedah yang sudah ada.

---

## 1. Ringkasan filosofi desain

Pesanan Online adalah antrian kerja, bukan tabel laporan. Satu pesanan = satu kartu putih di kanvas krem. Status dibaca dari tab di atas, lalu dari badge kecil di kartu. Aksi (kemas, kirim, selesai, batal) duduk di kaki kartu, bukan di layar terpisah.

Tiga peran warna Kombo Terang, dan hanya tiga:

| Peran | Token | Hex | Dipakai untuk |
| --- | --- | --- | --- |
| 1. Kanvas | `bg` / `snow` | `#FBF7F4` | Latar layar, permukaan “salju” |
| 2. Highlight | `navy` | `#2945A2` | Judul, harga, ikon fungsi, tombol isi, tab aktif |
| 3. Garnish | `accent` | `#CC6047` | Garis aksen 3px di tepi kiri kartu, tick, hover. Bukan wash besar |

`ice` di Kombo Terang adalah highlight yang diencerkan (`#E2E6F2`), bukan biru es Frozen Lake. Wash, chip netral, dan tab non-aktif memakai `ice` / `slate`. Terracotta tidak dipakai sebagai latar kartu atau tombol utama.

Kartu putih (`#FFFFFF`) mengambang di atas krim dengan bayangan sangat tipis dan garis tepi navy 24%. Tidak ada grain es di belakang layar: `PremiumScaffold` mematikan backdrop Frozen Lake saat mode kombo.

Nada huruf: tebal untuk nama, harga, dan angka antrean (`w800`); sedang untuk meta (`w500`–`w600`). Judul app bar kecil, rapat, letter-spacing positif. Harga dan nama sedikit dirapatkan (`letterSpacing` negatif).

Yang sengaja tidak ada di halaman utama, dan jangan ditambahkan “agar lengkap” saat menyelaraskan fitur lain:

- Tidak ada search bar, dropdown cabang, atau date range di antrian. Filter status adalah **4 tab penuh lebar**.
- Tidak ada data table. Daftar selalu kartu, di ponsel maupun desktop.
- Tidak ada modal detail produk. Kartu itu sendiri permukaan datanya. Dialog hanya untuk konfirmasi ubah status (resi / catatan).
- Tidak ada nomor order di kartu. Identitas visual adalah **nama pelanggan + nominal**.
- Tidak ada skeleton. Loading adalah spinner navy di tengah.

Cakupan cabang tidak dipilih di antrian. Role pusat melihat semua cabang (pill “semua” di banner). Staf cabang terkunci ke tokonya. Pemilih cabang (`AdminPickerField`) hanya ada di halaman pengaturan.

---

## 2. Peta berkas

Semua UI fitur ini ada di satu file. Tidak ada widget lokal yang sudah dipecah ke file sendiri.

| Peran | Berkas |
| --- | --- |
| Layar antrian + pengaturan kirim | `lib/apps/admin/online_orders_page.dart` |
| Pendaftaran menu (`id: online`) | `lib/apps/admin/admin_dash_nav.dart` |
| Shell dashboard (sidebar ≥ 900px, back di pane) | `lib/apps/admin/dashboard_page.dart` |
| Token & theme Admin | `lib/shared/theme.dart` |
| Swatch Kombo Terang | `lib/shared/admin_appearance.dart` |
| Label status (teks Indonesia) | `lib/shared/member/member_online_order_labels.dart` |
| Aturan uang / preorder / scope toko | `lib/shared/member/member_online_order_rules.dart` |
| Format `Rp` dan tanggal | `lib/shared/admin/admin_format.dart` |
| Badge belum dibaca | `lib/shared/admin/admin_nav_badge_service.dart` |
| Primitif premium | `lib/shared/widgets/admin/` (barrel `admin_premium.dart`) |
| Salinan UI | `assets/translations/id.json` (`dash_menu_online`, `online_*`) |

State UI bukan Provider/Bloc. `_OnlineOrdersPageState` memegang `TabController` (4 tab), daftar baris, loading, dan error. Badge belum-dibaca diikat lewat `ListenableBuilder` ke `AdminNavBadgeService`.

Dua kelas di file yang sama:

- `OnlineOrdersPage` — antrian.
- `OnlineDeliverySettingsPage` — pengaturan jual online / OBR / tarif, dibuka dari ikon tune.

---

## 3. Token desain (Kombo Terang)

### 3.1 Warna kanvas, permukaan, teks

| Token | Hex | Alpha | Pemakaian di Pesanan Online |
| --- | --- | --- | --- |
| `bg` / `snow` | `#FBF7F4` | 100% | Kanvas scaffold, teks di atas tombol navy (`onHighlight`) |
| `bgMid` | `#FBF7F4` | 100% | Isi chip meta, kartu toggle mati, kotak catatan |
| `panel` / `card` | `#FFFFFF` | 100% | Isi `PremiumPanel`, dialog, baris tarif |
| `cardElevated` | `#F7F3EF` | 100% | Isi field (theme input) |
| `cardSheenTop` | `#FFFFFF` | — | Sheen kartu: putih, lalu putih, lalu 4% menuju navy |
| `navy` / `textPrimary` | `#2945A2` | 100% | Judul, harga, ikon, tombol isi, tab aktif |
| `textSecondary` | `#3D4F7A` | 100% | Alamat, isi dialog |
| `slate` / `textMuted` | `#6B7394` | 100% | Subjudul app bar, telepon · cabang · waktu, tab non-aktif |
| `ice` | `#E2E6F2` | 100% | Wash highlight. Bukan warna es |
| `accent` | `#CC6047` | 100% | Ujung garis aksen kartu (garnish) |
| `accentDeep` | `#A84C38` | 100% | Tidak dipakai langsung di halaman ini |
| `accentSoft` | `#F4D4CC` | 100% | Tidak dipakai langsung di halaman ini |
| `line` | `#2945A2` | 14% (`0x24`) | Garis chip meta, garis kartu toggle mati |
| `lineStrong` / `chromeEdge` | `#2945A2` | 24% (`0x3D`) | Tepi `PremiumPanel` (tebal 1.15) |
| Kanvas bawah | `#F6F1EC` | 100% | Ujung gradient scaffold (hampir rata dengan krim) |

Gradient kanvas Kombo Terang: `#FBF7F4` → `#FBF7F4` → `#F6F1EC` (atas ke bawah). Di praktiknya layar terasa krim datar. Radial es dan grain Frozen Lake **tidak digambar**.

`chromeEdge` pada Kombo Terang = `lineStrong`, opacity 1, lebar **1.15**. Bukan outline `ice`.

### 3.2 Warna semantik (tetap di semua mode)

| Token | Hex | Arti di antrian |
| --- | --- | --- |
| `warning` | `#9A7B3C` | Lunas / dikemas, chip preorder, catatan toko |
| `success` | `#3D8F7A` | Selesai, voucher, snackbar sukses, badge “hidup” |
| `danger` | `#A65D5D` | Belum bayar, batal, kedaluwarsa, error, badge belum dibaca |

Tidak ada status “retur” di antrian ini. Batal dan kedaluwarsa satu warna dengan menunggu bayar.

### 3.3 Badge status pesanan

Widget lokal `_statusChip`. Bentuk pil. Padding `8×4`. Radius `99`. Font 11 / `w700`.

Rumus isi dan garis:

- Latar = warna wash × **22%**
- Garis = warna teks × **35%**, tebal 1
- Teks = warna status

| Status data | Label UI | Teks | Wash (sumber 22%) | Garis (sumber 35%) |
| --- | --- | --- | --- | --- |
| `pending_payment` | Menunggu pembayaran | `#A65D5D` | danger | danger |
| `paid` | Lunas · menunggu proses | `#9A7B3C` | warning | warning |
| `packing` | Dikemas | `#9A7B3C` | warning | warning |
| `ready` | Siap diambil / dikirim | `#2945A2` | **ice** `#E2E6F2` | navy |
| `shipped` | Dalam pengiriman | `#2945A2` | **ice** `#E2E6F2` | navy |
| `fulfilled` | Selesai | `#3D8F7A` | success | success |
| `cancelled` | Dibatalkan | `#A65D5D` | danger | danger |
| `expired` | Kedaluwarsa | `#A65D5D` | danger | danger |

`ready` / `shipped` adalah pengecualian: teks navy, latar dari `ice` (bukan dari navy). Di kartu putih hasilnya wash biru-abu sangat pucat, teks biru `#2945A2`.

Chip lain di kartu yang sama:

| Chip | Latar | Garis | Teks | Ukuran |
| --- | --- | --- | --- | --- |
| Meta (kirim/ambil, kurir, jumlah item) | `bgMid` `#FBF7F4` | `line` | `slate` 11.5 / `w600` | padding `9×5`, ikon 13, radius 99 |
| Tag preorder | `warning` 15% | `warning` 40% | `#9A7B3C` 10.5 / `w800` | padding `8×4`, radius 99 |
| Hitungan tab (bukan unread) | `ice` 50%, atau putih 20% jika tab aktif | — | ikut warna label, 10.5 / `w800` | min lebar 20, padding `6×2`, radius 99 |
| Belum dibaca | `#A65D5D` penuh | — | `snow` 9 / `w800` | lingkaran, min 16 (`AdminNavBadge` compact) |

### 3.4 Radius

Token resmi:

| Token | px |
| --- | --- |
| `radiusSm` | 12 |
| `radiusMd` | 16 |
| `radiusLg` / kartu `PremiumPanel` | 20 |
| `radiusXl` / dialog theme | 24 |
| Pil | 99 |

Yang dipakai halaman ini di luar token: **10** (catatan toko), **13** (ikon banner), **14** (ikon kartu, field picker, tombol premium), **18** (banner antrean).

### 3.5 Bayangan (hanya mode terang)

`cardShadow` pada `PremiumPanel` dan tab:

1. `navy` 4%, blur 32, spread −4, offset `(0, 16)`
2. `slate` 6%, blur 8, offset `(0, 2)`

Mode gelap tidak punya bayangan. Kombo Terang punya.

Bayangan lokal (bukan token):

| Elemen | Warna | Blur | Offset |
| --- | --- | --- | --- |
| Banner antrean | navy 16% | 18 | `(0, 8)` |
| Indikator tab aktif | navy 18% | 10 | `(0, 4)` |
| Lingkaran empty state | navy 6% | 24 | `(0, 10)` |
| `PremiumPrimaryButton` (`glow`) | navy 12% | 12 | `(0, 4)` |

Elevasi Material tombol isi di theme = 0. Kedalaman datang dari bayangan token, bukan dari `elevation`.

### 3.6 Spacing yang benar-benar dipakai

Token ada (`6 / 10 / 14 / 20 / 28`) tetapi halaman banyak memakai angka langsung. Angka yang jadi ritme layar:

| Nilai | Dipakai untuk |
| --- | --- |
| 2 | Jarak judul–subjudul (app bar, banner, toggle) |
| 3 | Nama pelanggan → baris meta |
| 4 | Padding dalam tab, jarak voucher |
| 5 | Ikon tab ↔ label, ikon chip ↔ teks |
| 6 | Jarak harga → badge, wrap chip (`spacing` / `runSpacing`), ikon alamat |
| 8 | Padding horizontal tab & banner, jarak blok catatan / resi, wrap tombol |
| 10 | Catatan toko (vertical), alamat di atasnya, jarak antar toggle |
| 12 | Celah kartu, ikon↔teks, padding daftar (atas), hero→panel |
| 14 | Padding kiri kartu, padding dalam banner, jarak section settings |
| 16 | Padding horizontal daftar, padding kanan/atas/bawah kartu, padding field |
| 20 | Padding layar pengaturan, padding empty state (horizontal 32) |
| 40 | Padding bawah daftar dan pengaturan |

Daftar kartu: `EdgeInsets.fromLTRB(16, 12, 16, 40)`, pemisah `SizedBox(height: 12)`.

### 3.7 Penyimpangan warna — jangan disalin

Empat hex ini ditulis langsung di `online_orders_page.dart`. Mereka **tidak** mengikuti swatch Kombo Terang (masih biru tua ala Frozen Lake). Fitur lain wajib memakai `OptikAdminTokens.navy` (`#2945A2`) dan `accent` (`#CC6047`), bukan hex ini.

| Hex | Lokasi |
| --- | --- |
| `#123A6B` | Ujung gradient tab aktif |
| `#163A6E` | Tengah gradient banner antrean |
| `#0E4A62` | Ujung gradient banner antrean |
| `#1A3A6E` | Tengah gradient hero pengaturan |

Awal gradient tab dan banner sudah benar: `OptikAdminTokens.navy` → di Kombo Terang itu `#2945A2`.

---

## 4. Skema tipografi

`buildAdminTheme()` mengatur `fontFamily: null`. Admin **tidak** memakai Fraunces atau Plus Jakarta Sans (itu kulit Karyawan). Huruf Pesanan Online = font default Material (Roboto di Android).

| Peran | px | Bobot | Warna Kombo Terang | Extra |
| --- | --- | --- | --- | --- |
| Judul halaman (app bar) | 15 | w700 | `#2945A2` | letter-spacing 1.0, rata tengah |
| Subjudul app bar (cakupan cabang) | 11 | w500 | `#6B7394` | letter-spacing 0.4 |
| Tab | 12 | w800 aktif / w600 diam | `#FBF7F4` / `#6B7394` | ikon 16 |
| Angka di tab | 10.5 | w800 | ikut label | |
| Judul banner antrean | 15.5 | w800 | `#FBF7F4` | letter-spacing −0.2 |
| Subjudul banner | 12 | w500 | snow 78% | |
| Pill “semua cabang” | 10.5 | w800 | `#FBF7F4` | letter-spacing 0.8 |
| Nama pelanggan | 15.5 | w800 | `#2945A2` | letter-spacing −0.2, height 1.2 |
| Telepon · cabang · waktu | 12 | w500 | `#6B7394` | |
| Nominal | 16 | w800 | `#2945A2` | letter-spacing −0.3, `Rp` tanpa desimal |
| Badge status | 11 | w700 | sesuai §3.3 | |
| Chip meta | 11.5 | w600 | `#6B7394` | |
| Alamat | 12.5 | w400 | `#3D4F7A` | height 1.35 |
| Catatan toko | 12 | w600 | `#9A7B3C` | height 1.35 |
| Resi | 12.5 | w700 | `#2945A2` | |
| Baris kurir / OBR | 11.5 | w600 | `#6B7394` | |
| Subtotal · ongkir | 11.5 | w400 | `#6B7394` | |
| Voucher | 12 | w700 | `#3D8F7A` | |
| Label tombol aksi kartu | 12 | w700 | snow atau navy | |
| Judul empty state | 17 | w800 | `#2945A2` | letter-spacing −0.2 |
| Isi empty state | 13.5 | w500 | slate 92% | height 1.45, rata tengah |
| Judul dialog (theme) | 18 | w800 | `#2945A2` | |
| Isi dialog (theme) | 14 | — | `#3D4F7A` | height 1.4 |
| Label field (theme) | 13 | w600 | `#6B7394` | |
| Eyebrow hero pengaturan | 11 | w700 | snow 72% | UPPERCASE visual lewat teks cabang, letter-spacing 1.1 |
| Judul hero pengaturan | 22 | w800 | `#FBF7F4` | height 1.15 |
| Isi hero | 13 | w400 | snow 88% | height 1.4 |
| Judul section pengaturan | 15–16 | w800 | `#2945A2` | |
| Judul toggle | 14.5 | w800 | `#2945A2` | |
| Subjudul toggle | 12 | w400 | `#6B7394` | height 1.3 |
| Tombol simpan penuh | theme 13 / ikon default | w700 | `#FBF7F4` di atas `#2945A2` | tinggi 50 |

Format uang: `AdminFormat.currency` → simbol `Rp`, 0 digit desimal, locale UI (`id_ID` untuk Indonesia). Contoh: `Rp 150.000`.

Waktu di kartu bersifat relatif (“baru saja”, menit, jam, hari). Lewat 7 hari: pola `d MMM · HH:mm`.

Tidak ada gaya khusus “nomor order”. Field itu tidak ditampilkan.

---

## 5. Struktur layout

### 5.1 Scaffold antrian

```
PremiumScaffold
  background #FBF7F4
  PremiumAppBar (transparan, elevasi 0, judul tengah)
    leading: panah kembali (pane Navigator dashboard, bukan breadcrumb)
    actions: IconButton tune, IconButton refresh
    bottom: tab bar, tinggi preferred 72
  body
    banner antrean
    [tombol "Muat 50 pesanan lagi" bila masih ada]
    TabBarView
      ListView kartu   atau   PremiumEmptyState
```

App bar tanpa subtitle memakai tinggi toolbar standar. Dengan subtitle cakupan cabang, tinggi judul = **72**, ditambah tab **72** → total chrome atas ≈ **144**.

Tidak ada tombol aksi primer di app bar. Aksi utama hidup di tiap kartu. Ikon app bar memakai `IconTheme` navy, ukuran ikon Material default (24). Refresh mati saat loading.

Halaman duduk di pane kanan dashboard. Lebar &lt; **900px**: sidebar jadi drawer, konten penuh. Lebar ≥ 900px: sidebar tetap, antrian mengisi sisa. **Isi antrian tidak berubah bentuk** — tidak ada master–detail, tidak ada tabel, tidak ada `LayoutBuilder` di halaman ini. Kartu selalu satu kolom selebar pane. Tab memakai `FittedBox` supaya empat label tetap muat.

### 5.2 Tab (pengganti filter status)

Bungkus: padding `8, 0, 8, 10`.

Wadah: tinggi 56, lebar penuh, radius 16, isi `snow` 92%, garis `ice` 55%, `cardShadow`.

`TabBar`: tidak bisa di-scroll, `padding` 4, indikator sebesar tab, radius 12, divider transparan.

Indikator aktif: gradient `navy` 92% → `#123A6B` (ujung kedua adalah penyimpangan, lihat §3.7).

Empat tab, kiri ke kanan:

| Ikon | Label | Isi |
| --- | --- | --- |
| `schedule_rounded` | Belum bayar | `pending_payment` |
| `hourglass_top_rounded` | Preorder | lunas/dikemas yang masih preorder |
| `bolt_rounded` | Siap kirim | `ready` / `shipped`, atau lunas/dikemas tanpa preorder |
| `history_rounded` | Riwayat | `fulfilled` / `cancelled` / `expired` |

Angka di tab = jumlah baris. Jika ada entitas belum dibaca, angka diganti `AdminNavBadge` merah.

### 5.3 Banner antrean

Padding luar `8, 8, 8, 4`. Padding dalam `16, 14, 16, 14`. Radius **18**.

Isi: ikon tas 42×42 (radius 13, putih 12%, garis ice 45%, ikon 22) → judul + subjudul → pill cakupan hanya untuk role pusat.

Judul: “Antrean sepi” atau “{n} pesanan perlu dikerjakan”. Subjudul: “{unpaid} belum bayar · {processing} diproses”.

### 5.4 Halaman pengaturan

`PremiumScaffold` + `AppBar` biasa (bukan `PremiumAppBar`), judul “Pengaturan pesanan online”.

`ListView` padding `20, 16, 20, 40`:

1. Hero radius 20, padding `20, 22`, ikon 42, eyebrow cabang, judul 22.
2. Jarak 16.
3. `PremiumPanel`: pemilih cabang (hanya pusat) lalu toggle jual online, ambil di toko, status Biteship.
4. Jarak 14.
5. Panel tarif (hanya jika jual online nyala): baris live, baris OBR, tiga toggle kategori, catatan, ongkir cadangan yang dilipat.
6. Jarak 18.
7. `FilledButton` penuh, tinggi 50, radius 16, navy. Saat menyimpan: spinner 18, stroke 2, putih.

Toggle: margin bawah 10, padding `14, 12, 10, 12`, radius 16. Nyala = latar `ice` 18% + garis `ice` 55%. Mati = `bgMid` + garis `line`. Ikon dalam kotak 40, radius 12, isi `panel`, garis `line`, ikon navy 20. `Switch.adaptive`, `activeColor` navy. Nonaktif: opacity kartu 0.45.

---

## 6. Template komponen

### 6.1 Filter bar

Bukan search + dropdown + date chip. Polanya:

1. Tab tersegmentasi penuh lebar (§5.2) menempel di bawah app bar.
2. Banner ringkas di bawahnya, satu kalimat status antrean.
3. Muat lebih banyak: `OutlinedButton` teks “Muat 50 pesanan lagi”, padding `16, 0, 16, 4`. Jendela data 90 hari, halaman 50.

Pemilih cabang, bila suatu fitur memang perlu, salin **pengaturan**, bukan antrian:

- Pemicu: `AdminPickerField` — radius 14, padding `12×12`, isi snow, garis `chromeEdge` 1.2, `PremiumIconBadge` 40, label 10.5 / `w700` letter-spacing 1.1 uppercase, nilai 15 / `w800`.
- Sheet: `showAdminPicker` — radius 20, judul 16 / `w800`, subjudul 12 / `w500`, field cari mengikuti `inputDecorationTheme` (isi `#F7F3EF`, radius 12, fokus navy 1.5).

### 6.2 Kartu / baris data

Selalu `PremiumPanel`:

- Radius 20, sheen putih, garis `chromeEdge` 1.15, `cardShadow`
- `showAccentBar: true` → garis kiri 3px, radius 2, gradient **`#2945A2` → `#CC6047`**, inset kiri konten 17, garis dimulai 4px dari atas dan bawah
- Padding kartu antrian: `14, 16, 16, 16`
- `onTap` hanya menandai “sudah dilihat”. Ketuk lama menandai belum dibaca. Tidak membuka detail.

Anatomi dalam, atas ke bawah:

1. Baris kepala
   - Ikon 44×44, radius 14, gradient `ice` 55% → 18%, garis `ice` 70%. Ikon 22 navy: motor jika kirim, etalase jika ambil. Titik merah di sudut kanan-atas bila belum dibaca.
   - Celah 12.
   - Nama 15.5. Di bawahnya 3px: telepon · label toko · waktu, 12 muted.
   - Kanan: nominal 16, lalu 6px, lalu badge status.
2. Celah 12.
3. `Wrap` chip meta, jarak 6.
4. Baris subtotal / ongkir / voucher (hijau) bila ada.
5. Alamat (ikon pin 15, celah 6) bila ada. Celah atas 10.
6. Catatan toko: padding `10×8`, radius 10, latar warning 10%, garis warning 28%. Celah atas 8.
7. Resi dan baris kurir bila ada.
8. Celah 12, lalu `Wrap` tombol, jarak 8.

### 6.3 Tombol

| Jenis | Bentuk di antrian | Spec |
| --- | --- | --- |
| Primer aksi kartu | `FilledButton`, latar navy, teks snow | padding `14×10`, label 12 / `w700`. Radius ikut theme: **12** |
| Sekunder | `OutlinedButton` | tinggi minimum theme **48**, garis slate, teks navy, radius 12, label 12 / `w700` |
| Bahaya (Batalkan) | `OutlinedButton` | teks danger, garis danger 45%. Hanya untuk `pending_payment` |
| Ikon app bar | `IconButton` | navy, tanpa lingkaran khusus |
| Simpan pengaturan | `FilledButton.icon` | lebar penuh, tinggi **50**, radius **16**, latar navy |
| Empty / error | `OutlinedButton.icon` atau `FilledButton.icon` | ikon 18 |
| Premium (ada, tidak dipakai antrian) | `PremiumPrimaryButton` | tinggi 52, radius 14, glow navy |

`PremiumPrimaryButton` dan `PremiumActionChip` **tidak** dipakai Pesanan Online. Jangan jadikan mereka wajib hanya karena ada di folder shared. Tombol kartu yang jadi acuan adalah `FilledButton` / `OutlinedButton` theme + override di atas.

Aksi yang muncul mengikuti status (label dari terjemahan):

- `paid` → Kemas (primer)
- Preorder `paid`/`packing` → Siap kirim
- Siap, ambil di toko → Siap diambil, lalu Selesai
- Siap, kirim → Isi resi / Antar sekarang, lalu Selesai / Sudah diantar
- Kirim non-OBR tanpa order Biteship → Panggil kurir (outlined + ikon 16)
- Belum bayar → Batalkan

### 6.4 Dialog

Bukan bottom sheet dan bukan drawer. `AlertDialog` theme:

- Latar `#FFFFFF`, elevasi 0, radius **24**, garis `lineStrong`
- Judul 18 / `w800` navy
- Isi 14, `#3D4F7A`
- Aksi: `TextButton` Batal (navy, `w600`) + `FilledButton` Simpan / Batalkan

Isi ubah status (bukan batal/selesai): dua `TextField` — resi dan catatan toko. Field mengikuti theme: isi `#F7F3EF`, padding `18×16`, radius 12, garis `lineStrong`, fokus navy 1.5, label 13 / `w600` slate.

Batal dan selesai hanya kalimat konfirmasi, tanpa field.

Snackbar: mengambang, radius 16. Sukses latar `#3D8F7A`. Gagal latar `#A65D5D`. Menunggu (tanpa override) latar navy, teks krim.

Tidak ada daftar item produk, pemisah `Divider`, atau foto barang di dialog maupun kartu. Jumlah item hanya chip (“N item”).

### 6.5 Feedback

| Keadaan | Tampilan |
| --- | --- |
| Loading awal | `CircularProgressIndicator` warna navy, di tengah. Bukan shimmer |
| Gagal muat | `PremiumEmptyState`: ikon `cloud_off_outlined`, aksen danger, judul + pesan, tombol isi “Coba lagi” |
| Tab kosong | `PremiumEmptyState`: ikon per tab, lingkaran 88, ikon 34. Preorder memakai aksen warning; tab lain memakai `ice` (ikon jadi navy). Tombol outline refresh |
| Simpan pengaturan | Spinner di dalam tombol, tombol nonaktif |
| Aksi gagal / terlarang | Snackbar danger |
| Aksi sukses | Snackbar success, lalu muat ulang daftar |

Empty state: padding `32, 28, 32, 40`, judul–isi 8, isi–tombol 20, ikon–judul 20.

Ikon kosong per tab: dompet, kardus, truk, jam sejarah.

---

## 7. Widget reusable vs masih di dalam halaman

### Sudah modular (`lib/shared/...`)

| Widget | Pakai di |
| --- | --- |
| `PremiumScaffold` | Antrian dan pengaturan |
| `PremiumAppBar` | Antrian saja |
| `PremiumPanel` | Kartu pesanan, panel pengaturan, panel tarif |
| `PremiumEmptyState` | Error dan empat tab kosong |
| `AdminNavBadge` / `AdminNavBadgeOverlay` | Tab dan sudut ikon kartu |
| `AdminPickerField` + `showAdminPicker` | Pengaturan, pilih cabang |
| `OptikAdminTokens` | Semua warna yang tidak di-hardcode |
| `AdminFormat` | Rupiah dan tanggal |
| `MemberOnlineOrderLabels` | Teks status dan jenis pemenuhan |

Ada di shared tetapi **tidak** dipakai halaman ini: `PremiumPrimaryButton`, `PremiumSectionHeader`, `PremiumStatGrid`, `PremiumListTile`, `PremiumChipWrap`, `PremiumMenuTile`.

### Masih lokal, layak diangkat bila fitur lain butuh pola yang sama

Urutan prioritas:

1. **`_statusChip`** — pil semantik pesanan. Rumusnya stabil dan akan berulang di penjualan, logistik, garansi.
2. **`_metaChip` + `_tagChip`** — pil netral dan pil peringatan. `PremiumActionChip` yang ada bentuknya beda (bukan pil 99, ada ikon theme). Jangan dipaksa jadi satu.
3. **`_premiumTabBar`** — tab tersegmentasi 56px dengan badge. Theme `TabBar` default tidak menghasilkan wadah ini.
4. **`_queuePulse`** — banner gradient + ikon 42 + satu kalimat antrean. Berguna untuk inbox lain, setelah hex beku (§3.7) diganti token.
5. **`_orderCard`** — komposisi kepala (ikon 44, nama, nominal, badge) + chip + tombol. Terlalu spesifik ke `online_orders` untuk diangkat utuh; pecah kepala dan kakinya, jangan satu widget “kartu pesanan” global.
6. **`_toggleCard`** — baris switch 40px. Belum ada primitif setara.
7. **`_heroBanner` pengaturan** — hero 22px. Sama: angkat setelah gradient-nya memakai navy token, bukan `#1A3A6E`.
8. **Dialog ubah status** — `AlertDialog` polos. Cukup theme. Tidak perlu widget baru sampai ada isi khusus (daftar barang, divider).

`_countBadge`, `_action`, `_rateRow`, `_voucherLines` terlalu kecil atau terlalu terikat data pesanan. Biarkan lokal.

---

## 8. Checklist standarisasi

Fitur Admin lain dinyatakan selaras dengan Pesanan Online (Kombo Terang) hanya jika sepuluh poin ini terpenuhi.

1. **Kanvas Kombo Terang.** Latar `PremiumScaffold` / `bg` = `#FBF7F4`. Kartu putih `#FFFFFF`. Tidak memakai palet Frozen Lake (`#000080`, `#ADD8E6`, `#FFFFFA`) dan tidak menggambar grain es.
2. **Tiga peran warna.** Teks dan tombol isi `#2945A2`. Garnish hanya garis 3px atau tick `#CC6047`. Wash memakai `ice` `#E2E6F2` atau `bgMid`, bukan terracotta sebagai latar besar.
3. **Tepi dan bayangan kartu.** `PremiumPanel` radius 20, garis navy 24% setebal 1.15, `cardShadow` dua lapis. Aksen kiri, bila ada, gradient navy → terracotta.
4. **App bar.** `PremiumAppBar` transparan, judul 15 / `w700` navy, letter-spacing ±1, rata tengah. Subjudul 11 / `w500` slate. Tidak ada breadcrumb. Kembali = panah pane. Aksi app bar = ikon, bukan tombol besar.
5. **Ritme jarak.** Daftar: padding horizontal 16, atas 12, bawah 40, celah kartu 12. Di dalam kartu: kepala, lalu 12, lalu chip, lalu 12, lalu tombol. Chip dalam satu grup berjarak 6. Tombol berjarak 8.
6. **Huruf.** Font default Admin, bukan Fraunces. Nama/judul baris 15.5 `w800`. Nominal 16 `w800` dengan `AdminFormat` (`Rp`, tanpa desimal). Meta 12 `w500` `#6B7394`. Tidak menambah ukuran judul halaman di atas 15 pada app bar.
7. **Status pakai pil, bukan teks polos.** Radius 99, padding `8×4`, font 11 `w700`, latar 22%, garis 35%. Peta warna mengikuti §3.3 (warning proses, navy+ice untuk siap/kirim, success selesai, danger bayar/batal/kedaluwarsa).
8. **Filter status = tab tersegmentasi** bila tugasnya antrian: wadah 56px, radius 16, isi snow, indikator radius 12, label 12. Empat tab atau kurang, `FittedBox`, tidak scroll horizontal. Search, dropdown, dan tanggal hanya ditambah bila fitur itu memang pencarian — dan field-nya memakai theme input (radius 12, isi `#F7F3EF`).
9. **Tombol.** Primer kartu: navy, radius 12, label 12 `w700`, padding `14×10`. Sekunder: outline, tinggi 48. Destruktif: outline danger. Tombol layar penuh (simpan): tinggi 50, radius 16. Tidak memakai elevation Material.
10. **Keadaan kosong, gagal, dan sibuk.** Loading = spinner navy di tengah, tanpa skeleton. Kosong = `PremiumEmptyState` (lingkaran 88, judul 17, isi 13.5, satu tombol). Gagal muat = empty state aksen danger. Konfirmasi = `AlertDialog` radius 24. Hasil aksi = snackbar mengambang, success `#3D8F7A` atau danger `#A65D5D`. Daftar tetap kartu satu kolom di lebar desktop maupun sempit; breakpoint 900px hanya milik shell sidebar.

---

## 9. Cara memakai dokumen ini

Saat menyelaraskan satu fitur, bandingkan layar itu dengan antrian Pesanan Online dalam mode **Kombo Terang**, lalu centang §8.

Jangan menyalin hex `#123A6B`, `#163A6E`, `#0E4A62`, atau `#1A3A6E`. Itu sisa warna di halaman sumber, bukan bagian standar.

Warna selalu lewat `OptikAdminTokens` supaya Kombo Gelap tetap ikut. Hex di dokumen ini adalah nilai terselesaikan saat mode = Kombo Terang, untuk dicek di mata, bukan untuk ditulis ulang sebagai `Color(0xFF...)`.
