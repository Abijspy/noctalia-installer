#!/usr/bin/env python3
"""Write a fake /sys/class/drm with two connected displays and EDIDs.

  make-drm.py DIR

card1-eDP-1:    2560x1600 laptop panel, 30 cm wide, 60 Hz      -> scale 1.5
card1-DP-2:     1920x1080 monitor, 53 cm wide, 60 Hz + 144 Hz  -> scale 1, 144 Hz
card1-HDMI-A-1: disconnected
"""
import os, sys


def dtd(w, h, hblank, vblank, hz):
    pclk = round(hz * (w + hblank) * (h + vblank) / 10000)  # 10 kHz units
    assert pclk < 65536
    b = bytearray(18)
    b[0], b[1] = pclk & 0xFF, pclk >> 8
    b[2], b[3], b[4] = w & 0xFF, hblank & 0xFF, ((w >> 8) << 4) | (hblank >> 8)
    b[5], b[6], b[7] = h & 0xFF, vblank & 0xFF, ((h >> 8) << 4) | (vblank >> 8)
    b[17] = 0x18  # progressive, digital separate sync
    return bytes(b)


def checksum(block):
    block[127] = (-sum(block[:127])) % 256


def edid(width_cm, base_dtd, cta_dtds=()):
    b = bytearray(128)
    b[0:8] = bytes([0, 255, 255, 255, 255, 255, 255, 0])
    b[18], b[19] = 1, 4
    b[21], b[22] = width_cm, round(width_cm * 0.6)
    b[54:72] = base_dtd
    b[126] = 1 if cta_dtds else 0
    checksum(b)
    out = bytes(b)
    if cta_dtds:
        e = bytearray(128)
        e[0], e[1], e[2] = 0x02, 0x03, 4  # CTA-861, timings start right after the header
        off = 4
        for d in cta_dtds:
            e[off:off + 18] = d
            off += 18
        checksum(e)
        out += bytes(e)
    return out


def connector(root, name, status, modes=(), data=b""):
    d = os.path.join(root, name)
    os.makedirs(d, exist_ok=True)
    open(os.path.join(d, "status"), "w").write(status + "\n")
    open(os.path.join(d, "modes"), "w").write("".join(m + "\n" for m in modes))
    open(os.path.join(d, "edid"), "wb").write(data)


root = sys.argv[1]
connector(root, "card1-eDP-1", "connected", ["2560x1600", "1920x1200"],
          edid(30, dtd(2560, 1600, 160, 46, 60)))
connector(root, "card1-DP-2", "connected", ["1920x1080", "1280x720"],
          edid(53, dtd(1920, 1080, 280, 45, 60), [dtd(1920, 1080, 160, 31, 144)]))
connector(root, "card1-HDMI-A-1", "disconnected")
