#!/usr/bin/env python3
"""Convert hardcoded _snack / _showSnack / _showSnackBar strings only (not AlertDialog content)."""
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

CALL_START = re.compile(r"^\s*(_snack|_showSnack|_showSnackBar)\(\s*$")
STR_LINE = re.compile(r"^\s*(['\"])(.*)\1\s*,?\s*$")


def slug(text: str) -> str:
    return f"admin_auto_{hashlib.md5(text.encode()).hexdigest()[:10]}"


def is_ui_text(s: str) -> bool:
    if not s or s in ("PUSAT",):
        return False
    if re.match(r"^[a-z][a-z0-9_]*$", s):
        return False
    return bool(re.search(r"[A-Za-zÀ-ÿ]{3,}", s))


def process_file(path: Path, id_d: dict, en_d: dict, id_by_val: dict) -> int:
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    out: list[str] = []
    i = 0
    n = 0
    while i < len(lines):
        line = lines[i]
        if not CALL_START.match(line.rstrip("\n")):
            out.append(line)
            i += 1
            continue
        prefix = CALL_START.match(line.rstrip("\n")).group(1)
        parts: list[str] = []
        j = i + 1
        while j < len(lines):
            sl = STR_LINE.match(lines[j].rstrip("\n"))
            if sl:
                parts.append(sl.group(2))
                j += 1
                continue
            break
        joined = " ".join(p.strip() for p in parts if p.strip())
        if joined and is_ui_text(joined) and ".tr(" not in joined and "$" not in joined:
            key = id_by_val.get(joined) or slug(joined)
            if key not in id_d:
                id_d[key] = joined
                en_d[key] = joined
                id_by_val[joined] = key
            indent = re.match(r"^(\s*)", line).group(1)
            out.append(f"{indent}{prefix}('{key}'.tr(),\n")
            i = j
            n += 1
            continue
        out.append(line)
        i += 1
    if n:
        text = "".join(out)
        if "easy_localization" not in text:
            idx = text.find("import ")
            if idx >= 0:
                end = text.find("\n", idx)
                text = text[: end + 1] + IMPORT + text[end + 1 :]
        path.write_text(text, encoding="utf-8")
    return n


def main() -> None:
    id_d = json.loads(ID_PATH.read_text(encoding="utf-8"))
    en_d = json.loads(EN_PATH.read_text(encoding="utf-8"))
    id_by_val = {v: k for k, v in id_d.items() if isinstance(v, str)}
    total = 0
    for dart in sorted(ADMIN.rglob("*.dart")):
        c = process_file(dart, id_d, en_d, id_by_val)
        if c:
            print("updated", dart.relative_to(ROOT), c)
            total += c
    ID_PATH.write_text(json.dumps(id_d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    EN_PATH.write_text(json.dumps(en_d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("done", total)


if __name__ == "__main__":
    main()
