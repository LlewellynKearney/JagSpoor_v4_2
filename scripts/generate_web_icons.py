#!/usr/bin/env python3
"""Generate the official JagSpoor web/PWA icons from the tracked badge.

Source of truth: assets/app logo/logo1.png (the official circular bush badge).
The template `flutter create` icons (the blue Flutter square) must never ship.

Outputs:
  web/favicon.png                 48x48  (transparent, small padding)
  web/icons/Icon-192.png         192x192 (transparent)
  web/icons/Icon-512.png         512x512 (transparent)
  web/icons/Icon-maskable-192.png 192x192 (cream background, maskable safe zone)
  web/icons/Icon-maskable-512.png 512x512 (cream background, maskable safe zone)

Run:  python3 scripts/generate_web_icons.py
"""
from PIL import Image

SRC = "assets/app logo/logo1.png"
CREAM = (245, 239, 230, 255)  # #f5efe6 -- the PWA background_color


def _trim(img):
    bbox = img.getbbox()
    return img.crop(bbox) if bbox else img


def _square(img, bg=None):
    side = max(img.size)
    canvas = Image.new("RGBA", (side, side), bg or (0, 0, 0, 0))
    canvas.paste(img, ((side - img.width) // 2, (side - img.height) // 2), img)
    return canvas


def _scaled(logo, size, padding_fraction, bg=None):
    inner = int(size * (1 - 2 * padding_fraction))
    resized = logo.resize((inner, inner), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), bg or (0, 0, 0, 0))
    off = (size - inner) // 2
    canvas.paste(resized, (off, off), resized)
    return canvas


def main():
    logo = _square(_trim(Image.open(SRC).convert("RGBA")))

    _scaled(logo, 48, 0.04).save("web/favicon.png")
    _scaled(logo, 192, 0.06).save("web/icons/Icon-192.png")
    _scaled(logo, 512, 0.06).save("web/icons/Icon-512.png")
    # Maskable icons need an 18% safe zone on a solid background so an
    # aggressive Android mask never clips the badge.
    _scaled(logo, 192, 0.18, bg=CREAM).save("web/icons/Icon-maskable-192.png")
    _scaled(logo, 512, 0.18, bg=CREAM).save("web/icons/Icon-maskable-512.png")
    print("Wrote 5 official JagSpoor web icons from", SRC)


if __name__ == "__main__":
    main()
