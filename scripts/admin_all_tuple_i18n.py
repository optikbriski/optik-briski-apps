#!/usr/bin/env python3
"""Replace admin tuple row labels ('Label', value) with .tr() across lib/apps/admin."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADMIN = ROOT / "lib/apps/admin"
ID_PATH = ROOT / "assets/translations/id.json"
EN_PATH = ROOT / "assets/translations/en.json"

SKIP_LABELS = {
    "Ref", "ID", "Memo", "Status", "NPWP", "DPP", "PPN", "Header", "Nonaktif",
    "Debit", "Kredit", "Saldo", "OPEN", "CLOSED", "APPROVED", "REJECTED",
    "IN_PROGRESS", "DONE", "POS", "Member", "Booking", "CSV", "Owner", "Login",
}
SKIP_RE = [
    re.compile(r"^[a-z][a-z0-9_]*$"),  # sql keys
    re.compile(r"^[A-Z_]+$"),  # ENUM
    re.compile(r"^EEE?,? "),  # date format
    re.compile(r"^CABANG-"),
    re.compile(r"\$"),  # interpolation in label
]


def slug(label: str) -> str:
    h = hashlib.md5(label.encode()).hexdigest()[:10]
    return f"admin_gl_row_{h}"


def should_skip(label: str) -> bool:
    if label.startswith("admin_"):
        return True
    if label in SKIP_LABELS:
        return True
    for pat in SKIP_RE:
        if pat.search(label):
            return True
    return False


def main() -> None:
    id_d = json.loads(ID_PATH.read_text(encoding="utf-8"))
    en_d = json.loads(EN_PATH.read_text(encoding="utf-8"))
    id_by_val = {v: k for k, v in id_d.items() if isinstance(v, str)}

    pat = re.compile(r"\(\s*'([^'\\]{1,200})'\s*,")
    total_labels = 0
    files_changed = 0

    for dart in sorted(ADMIN.rglob("*.dart")):
        original = dart.read_text(encoding="utf-8")
        content = original
        labels: set[str] = set()
        for m in pat.finditer(original):
            label = m.group(1)
            if should_skip(label):
                continue
            if not re.search(r"[a-zA-ZÀ-ÿ]{2,}", label):
                continue
            labels.add(label)

        if not labels:
            continue

        mapping: dict[str, str] = {}
        for label in labels:
            key = id_by_val.get(label)
            if not key:
                key = slug(label)
                if key not in id_d:
                    id_d[key] = label
                    en_d[key] = label  # fallback; refine EN later
            mapping[label] = key

        for label, key in sorted(mapping.items(), key=lambda x: -len(x[0])):
            old = f"('{label}',"
            new = f"('{key}'.tr(),"
            if old in content:
                content = content.replace(old, new)

        if content != original:
            dart.write_text(content, encoding="utf-8")
            files_changed += 1
            total_labels += len(mapping)
            print("updated", dart.relative_to(ROOT), len(mapping))

    ID_PATH.write_text(json.dumps(id_d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    EN_PATH.write_text(json.dumps(en_d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("done", files_changed, "files", total_labels, "labels", len(id_d), "json keys")


if __name__ == "__main__":
    main()
