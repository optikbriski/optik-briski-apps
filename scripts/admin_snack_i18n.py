#!/usr/bin/env python3
"""Convert hardcoded _snack / _showSnack string literals in admin to .tr()."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADMIN = ROOT / "lib/apps/admin"
ID_PATH = ROOT / "assets/translations/id.json"
EN_PATH = ROOT / "assets/translations/en.json"
IMPORT = "import 'package:easy_localization/easy_localization.dart';\n"

EN_MANUAL: dict[str, str] = {
    "Gagal kirim pengaduan: {error}": "Failed to send complaint: {error}",
    "Gagal memuat antrian: {error}": "Failed to load queue: {error}",
    "Gagal mengirim ke pusat: {error}": "Failed to send to HQ: {error}",
    "Gagal melacak: {error}": "Failed to track: {error}",
    "Gagal hold stok: {error}": "Failed to hold stock: {error}",
    "Owner {email} berhasil diprovision.": "Owner {email} provisioned successfully.",
    "Jumlah harus lebih dari 0": "Quantity must be greater than 0",
    "Sesi dibatalkan": "Session cancelled",
    "Periode sudah dibayar — tidak bisa diubah.": "Period already paid — cannot be changed.",
    "Periode terkunci. Unlock dulu untuk ubah draft.": "Period locked. Unlock first to edit draft.",
    "Draft payroll tersimpan (belum dikunci).": "Payroll draft saved (not locked yet).",
    "Centang nama yang akan memakai template.": "Select names to apply the template.",
    "Buat dan pilih template dulu. Di sini hanya memilih nama.": "Create and select a template first. Here you only pick names.",
    'Template "{name}" diterapkan ke {n} orang.': 'Template "{name}" applied to {n} people.',
    "Template disimpan. Centang nama, lalu terapkan.": "Template saved. Select names, then apply.",
    "Template diperbarui.": "Template updated.",
    "Waktu bayar 15 menit habis — stok hold dilepas. Buka preview lagi untuk hold ulang.": (
        "15-minute payment window expired — stock hold released. Open preview again to re-hold."
    ),
    "Poin tim 0 — pool Rp {amount} tidak dibagi. Isi poin KPI bulan ini atau ganti mode Rp/poin.": (
        "Team points 0 — Rp {amount} pool not distributed. Fill monthly KPI points or switch to Rp/point mode."
    ),
}


def slug(text: str) -> str:
    h = hashlib.md5(text.encode()).hexdigest()[:10]
    return f"admin_auto_{h}"


def to_template(s: str) -> tuple[str, dict[str, str]]:
    named: dict[str, str] = {}
    var_map = {"e": "error", "email": "email", "nama": "name", "amount": "amount", "n": "n"}

    def repl(m: re.Match) -> str:
        var = m.group(1)
        key = var_map.get(var, var)
        named[key] = f"${var}"
        return "{" + key + "}"

    out = re.sub(r"\$(\w+)", repl, s)
    out = re.sub(r"\$\{([^}]+)\}", lambda m: "{" + var_map.get(m.group(1), m.group(1).split(".")[0]) + "}", out)
    return out, named


def tr_call(key: str, named: dict[str, str]) -> str:
    if not named:
        return f"'{key}'.tr()"
    args = ", ".join(f"'{k}': '{v}'" for k, v in named.items())
    return f"'{key}'.tr(namedArgs: {{{args}}})"


def main() -> None:
    id_d = json.loads(ID_PATH.read_text(encoding="utf-8"))
    en_d = json.loads(EN_PATH.read_text(encoding="utf-8"))
    id_by_val = {v: k for k, v in id_d.items() if isinstance(v, str)}

    # Match _snack('...' or _showSnack("... including simple ${} patterns on one line
    call_re = re.compile(
        r"(_snack|_showSnack)\(\s*(['\"])((?:\\.|(?!\2).){2,300}?)\2",
        re.DOTALL,
    )

    for dart in sorted(ADMIN.rglob("*.dart")):
        original = dart.read_text(encoding="utf-8")
        content = original
        changed = False

        for m in list(call_re.finditer(original)):
            prefix, quote, raw = m.group(1), m.group(2), m.group(3)
            if ".tr(" in raw or raw.strip() == "$e":
                continue
            # skip multiline-only dynamic (handled separately below)
            text = raw.replace("\\n", " ").strip()
            if not text or text.startswith("admin_"):
                continue
            template, named = to_template(text)
            key = id_by_val.get(template) or id_by_val.get(text) or slug(template)
            if key not in id_d:
                id_d[key] = template
                en_d[key] = EN_MANUAL.get(template) or EN_MANUAL.get(text) or template
            repl = tr_call(key, named)
            old = f"{prefix}({quote}{raw}{quote}"
            new = f"{prefix}({repl}"
            if old in content:
                content = content.replace(old, new, 1)
                changed = True

        if changed:
            if "easy_localization" not in content:
                idx = content.find("import ")
                if idx >= 0:
                    end = content.find("\n", idx)
                    content = content[: end + 1] + IMPORT + content[end + 1 :]
            dart.write_text(content, encoding="utf-8")
            print("updated", dart.relative_to(ROOT))

    ID_PATH.write_text(json.dumps(id_d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    EN_PATH.write_text(json.dumps(en_d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("done", len(id_d), "keys")


if __name__ == "__main__":
    main()
