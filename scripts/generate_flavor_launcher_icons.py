#!/usr/bin/env python3
"""Generate launcher icons per flavor + brand (Rekasa / Optik Briski).

Rekasa: latar biru, huruf A/K/M putih.
Briski: latar putih, huruf A/K/M biru.
"""
from __future__ import annotations

import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ANDROID_RES = ROOT / "android/app/src"

REKASA_BLUE = (0, 71, 171)
BRISKI_BLUE = (11, 61, 140)
WHITE = (255, 255, 255)

DENSITIES: dict[str, int] = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

FLAVOR_LETTERS: dict[str, str] = {
    "admin": "A",
    "karyawan": "K",
    "member": "M",
}

BRANDS: dict[str, dict[str, object]] = {
    "rekasa": {
        "logo": ROOT / "assets/images/brand/rekasa-lockup.png",
        "canvas_bg": REKASA_BLUE,
        "badge_bg": REKASA_BLUE,
        "badge_fg": WHITE,
        "badge_ring": WHITE,
        "logo_on_dark": True,
    },
    "optik-briski": {
        "logo": ROOT / "assets/images/logo_briski.png",
        "canvas_bg": WHITE,
        "badge_bg": WHITE,
        "badge_fg": BRISKI_BLUE,
        "badge_ring": BRISKI_BLUE,
        "logo_on_dark": False,
    },
}


def _load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Supplemental/Helvetica.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ]
    for path in candidates:
        p = Path(path)
        if p.exists():
            try:
                return ImageFont.truetype(str(p), size=size)
            except OSError:
                continue
    return ImageFont.load_default()


def _rounded_square(
    size: int,
    radius: int,
    fill: tuple[int, int, int],
    outline: tuple[int, int, int] | None = None,
    outline_w: int = 0,
) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    box = (0, 0, size - 1, size - 1)
    if outline and outline_w > 0:
        draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=outline_w)
    else:
        draw.rounded_rectangle(box, radius=radius, fill=fill)
    return img


def _logo_for_brand(logo: Image.Image, on_dark: bool) -> Image.Image:
    rgba = logo.convert("RGBA")
    if not on_dark:
        return rgba
    # Rekasa lockup biru → putih agar terbaca di latar biru.
    r, g, b, a = rgba.split()
    white = Image.new("L", rgba.size, 255)
    return Image.merge("RGBA", (white, white, white, a))


def render_icon(size: int, flavor: str, brand_key: str, logo: Image.Image) -> Image.Image:
    brand = BRANDS[brand_key]
    letter = FLAVOR_LETTERS[flavor]
    canvas_bg = tuple(brand["canvas_bg"])  # type: ignore[arg-type]
    badge_bg = tuple(brand["badge_bg"])  # type: ignore[arg-type]
    badge_fg = tuple(brand["badge_fg"])  # type: ignore[arg-type]
    badge_ring = tuple(brand["badge_ring"])  # type: ignore[arg-type]
    logo_on_dark = bool(brand["logo_on_dark"])

    radius = max(4, size // 5)
    outline = badge_ring if brand_key == "optik-briski" else None
    outline_w = max(1, size // 48) if outline else 0
    canvas = _rounded_square(size, radius, canvas_bg, outline, outline_w)

    draw = ImageDraw.Draw(canvas)

    # Logo kecil di atas (opsional, tetap terbaca di ukuran launcher).
    logo_copy = _logo_for_brand(logo, logo_on_dark)
    logo_max_w = int(size * 0.72)
    logo_max_h = int(size * 0.28)
    logo_copy.thumbnail((logo_max_w, logo_max_h), Image.Resampling.LANCZOS)
    lx = (size - logo_copy.width) // 2
    ly = max(2, int(size * 0.08))
    canvas.alpha_composite(logo_copy, (lx, ly))

    # Badge A/K/M — satu skema warna per merek.
    badge_d = max(16, int(size * 0.42))
    bx1 = (size - badge_d) // 2
    by1 = size - badge_d - max(2, int(size * 0.06))
    bx2 = bx1 + badge_d
    by2 = by1 + badge_d
    ring_w = max(2, size // 32)
    if brand_key == "rekasa":
        # Latar sudah biru — cukup ring putih + huruf putih.
        draw.ellipse((bx1, by1, bx2, by2), outline=badge_ring, width=ring_w)
        letter_color = badge_fg
    else:
        # Briski: badge putih, huruf biru, ring biru.
        draw.ellipse((bx1, by1, bx2, by2), fill=badge_bg, outline=badge_ring, width=ring_w)
        letter_color = badge_fg

    font = _load_font(max(12, int(badge_d * 0.52)))
    bbox = draw.textbbox((0, 0), letter, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = bx1 + (badge_d - tw) // 2 - bbox[0]
    ty = by1 + (badge_d - th) // 2 - bbox[1] - int(size * 0.01)
    draw.text((tx, ty), letter, fill=letter_color, font=font)

    return canvas


def main() -> None:
    brand_key = os.environ.get("BRAND", "rekasa").strip()
    if brand_key not in BRANDS:
        raise SystemExit(f"BRAND tidak dikenal: {brand_key!r} (pakai rekasa / optik-briski)")

    logo_path = Path(str(BRANDS[brand_key]["logo"]))
    if not logo_path.exists():
        raise SystemExit(f"Logo tidak ada: {logo_path}")

    logo = Image.open(logo_path)
    print(f"==> Icon launcher merek={brand_key}")
    for flavor, _letter in FLAVOR_LETTERS.items():
        for folder, px in DENSITIES.items():
            out_dir = ANDROID_RES / flavor / "res" / folder
            out_dir.mkdir(parents=True, exist_ok=True)
            out_path = out_dir / "ic_launcher.png"
            icon = render_icon(px, flavor, brand_key, logo)
            icon.save(out_path, format="PNG", optimize=True)
            print(f"  {flavor} {px}px -> {out_path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
