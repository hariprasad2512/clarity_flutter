#!/usr/bin/env python3
"""Generate Clarity logo assets from the brand mark (green + white check).

Recreates the uploaded lockup's mark (green circle, white check) in code so
every platform stays in sync. Re-run after any brand tweak:

    python3 tool/generate_logo_assets.py

Brand green #43A047 sampled from the uploaded logo.
Launcher style (per decision): full-bleed green rounded square + white check.
In-app mark: green circle + white check on transparent.
"""

from __future__ import annotations

import os
from collections.abc import Callable

from PIL import Image, ImageDraw

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GREEN = (67, 160, 71, 255)  # #43A047
WHITE = (255, 255, 255, 255)
TRANSPARENT = (0, 0, 0, 0)

# White check as three points (fractions of canvas), matching the logo's
# short-left / long-right arms.
CHECK = ((0.30, 0.545), (0.445, 0.665), (0.715, 0.335))
CHECK_WIDTH_FRAC = 0.115


def _draw_check(draw: ImageDraw.ImageDraw, size: int) -> None:
    pts = [(x * size, y * size) for x, y in CHECK]
    draw.line(pts, fill=WHITE, width=int(size * CHECK_WIDTH_FRAC), joint="curve")


def green_square(size: int, radius_frac: float = 0.225) -> Image.Image:
    """Full-bleed green rounded square with centered white check."""
    img = Image.new("RGBA", (size, size), TRANSPARENT)
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle(
        [0, 0, size - 1, size - 1],
        radius=int(size * radius_frac),
        fill=GREEN,
    )
    _draw_check(draw, size)
    return img


def mark_transparent(size: int) -> Image.Image:
    """Green circle + white check on transparent (in-app / splash)."""
    img = Image.new("RGBA", (size, size), TRANSPARENT)
    draw = ImageDraw.Draw(img)
    pad = int(size * 0.04)
    draw.ellipse([pad, pad, size - 1 - pad, size - 1 - pad], fill=GREEN)
    _draw_check(draw, size)
    return img


def check_transparent(size: int) -> Image.Image:
    """White check alone on transparent (Android adaptive foreground)."""
    img = Image.new("RGBA", (size, size), TRANSPARENT)
    _draw_check(ImageDraw.Draw(img), size)
    return img


def save(img: Image.Image, *parts: str) -> None:
    path = os.path.join(REPO, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print(f"wrote {os.path.relpath(path, REPO)} ({img.size[0]}px)")


def save_ico(
    make: Callable[[int], Image.Image], sizes: list[int], *parts: str
) -> None:
    """Multi-size Windows .ico rendered from the brand mark."""
    path = os.path.join(REPO, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    make(max(sizes)).save(path, sizes=[(s, s) for s in sizes])
    print(f"wrote {os.path.relpath(path, REPO)} (ico {sizes})")


def main() -> None:
    # 1. In-app / splash mark (circle on transparent).
    save(mark_transparent(512), "assets", "logo", "clarity_mark.png")

    # 2. Android legacy launcher PNGs (green square + check).
    for density, px in (
        ("mdpi", 48),
        ("hdpi", 72),
        ("xhdpi", 96),
        ("xxhdpi", 144),
        ("xxxhdpi", 192),
    ):
        save(
            green_square(px),
            "android", "app", "src", "main", "res",
            f"mipmap-{density}", "ic_launcher.png",
        )

    # 3. Android adaptive foreground (white check; bg color in XML).
    for density, px in (
        ("mdpi", 108),
        ("hdpi", 162),
        ("xhdpi", 216),
        ("xxhdpi", 324),
        ("xxxhdpi", 432),
    ):
        save(
            check_transparent(px),
            "android", "app", "src", "main", "res",
            f"mipmap-{density}", "ic_launcher_foreground.png",
        )

    # 4. Android splash center image (circle mark on transparent).
    save(
        mark_transparent(512),
        "android", "app", "src", "main", "res",
        "drawable-nodpi", "launch_image.png",
    )

    # 5. macOS AppIcon set (green square + check; OS applies masking).
    for name, px in (
        ("app_icon_16", 16),
        ("app_icon_32", 32),
        ("app_icon_64", 64),
        ("app_icon_128", 128),
        ("app_icon_256", 256),
        ("app_icon_512", 512),
        ("app_icon_1024", 1024),
    ):
        save(
            green_square(px),
            "macos", "Runner", "Assets.xcassets", "AppIcon.appiconset",
            f"{name}.png",
        )

    # 6. Play Store high-res icon (512, full-bleed, no transparency).
    icon = green_square(512)
    bg = Image.new("RGBA", (512, 512), GREEN)
    bg.alpha_composite(icon)
    save(
        bg.convert("RGB"),
        "assets", "logo", "clarity_store_icon_512.png",
    )

    # 7. Windows app + installer icon (green square + check). The exe's
    # IDI_APP_ICON, taskbar, Start Menu shortcut, and Inno SetupIconFile
    # all read this one file.
    save_ico(
        green_square, [16, 24, 32, 48, 64, 128, 256],
        "windows", "runner", "resources", "app_icon.ico",
    )

    # 8. Windows tray icon (small sizes; tray_manager reads the .ico).
    save_ico(
        green_square, [16, 24, 32, 48],
        "assets", "tray", "tray_icon.ico",
    )


if __name__ == "__main__":
    main()
