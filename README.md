# arch-galaxytab-submonitor

**[English](README.md)** &nbsp;|&nbsp; [한국어](README.ko.md)

---

An open stack for using a Samsung Galaxy Tab as a secondary display on Arch Linux. A custom-EDID virtual output, low-latency game-stream style transport, and touch/pen return-input together reproduce the Windows Super Display / spacedesk workflow on Linux.

Born from the fact that there is no first-class native-resolution secondary-monitor solution for Galaxy Tab on Linux — only crude web-based tools exist.

> **Status: alpha / personal.** Target-validated only on a Galaxy Book Ultra 3 (Intel + NVIDIA PRIME Optimus) host and a Galaxy Tab S9 Ultra client. Other combinations are unverified.

---

## Architecture

```
 ┌─────────────┐   ┌──────────┐   ┌──────────┐   ┌────────────┐
 │ custom EDID │ → │ virtual  │ → │ Sunshine │ → │  Moonlight │
 │  + kernel   │   │ HDMI out │   │  (host)  │   │   (tab)    │
 │   params    │   │ @ 120Hz  │   │          │   │            │
 └─────────────┘   └──────────┘   └──────────┘   └────────────┘
                                        ^               │
                                        │  touch / pen  │
                                        └───────────────┘
```

1. **Virtual display** — `drm.edid_firmware` + `video=HDMI-A-1:e` enables a synthetic 2960×1848 @ 120 Hz connector on the i915 driver.
2. **Capture / encode** — Sunshine scrapes that output via PipeWire and encodes with NVENC AV1 or HEVC in its lowest-latency preset.
3. **Transport** — Wi-Fi 6E, or USB-C tethering combined with `adb reverse` (recommended for lower jitter).
4. **Input return** — Moonlight's native touch / pen events are injected back into the host via a `uinput` virtual device.

---

## Requirements

### Hardware (target validation combination)

| Component | Model | Note |
|-----------|-------|------|
| Host | Galaxy Book Ultra 3 | Intel Core i7 + RTX 4050 Max-Q; HDMI port wired to the Intel iGPU, not the dGPU |
| Client | Galaxy Tab S9 Ultra | 2960×1848, 120 Hz, AV1 hardware decode |
| Link | Wi-Fi 6E AP **or** USB-C cable | USB-C tethering recommended |

### Software

- Arch Linux, kernel `linux` or `linux-zen` 6.x+
- KDE Plasma 6 on Wayland — other compositors unverified
- [Sunshine](https://github.com/LizardByte/Sunshine) (AUR)
- [Moonlight](https://moonlight-stream.org/) Android client

---

## Repository layout (planned)

```
edid/        EDID generator for 2960×1848 @ 120 Hz (CVT-RB2)
kernel/      Kernel cmdline / mkinitcpio snippets
sunshine/    systemd unit + config template (secrets excluded)
udev/        uinput access rules
scripts/     install / verify / uninstall (dry-run by default)
docs/        Latency tuning, security model, troubleshooting
```

Currently at skeleton stage — there is no working install path yet.

---

## Security Notice

**This stack requires several privilege-escalation points. Do not deploy it on untrusted or public networks as-is.**

### Things you must be aware of

1. `setcap cap_sys_admin+p sunshine` grants kernel-grade capability to the Sunshine binary permanently. An upstream RCE in Sunshine would be immediately root-equivalent. Watch [Sunshine Security Advisories](https://github.com/LizardByte/Sunshine/security) and pin a minimum tested version in your local deployment.
2. Moonlight pairing uses a **4-digit PIN on trust-on-first-use**. Pair only on a trusted LAN.
3. Sunshine binds to `0.0.0.0` with UPnP enabled by default. Firewall the service to a USB tethering NIC or a WireGuard interface.
4. Opening `uinput` lets any process in the logged-in session create virtual input devices — a latent keylogger / automation surface. Scope the udev rule to a dedicated group (e.g. `sunshine-uinput`).
5. Capture should go through `xdg-desktop-portal`. Running privileged components as root to "work around it" is explicitly discouraged.

### Never commit (blocked by `.gitignore`)

- `~/.config/sunshine/sunshine_state.json` (long-term pairing keys)
- `~/.config/sunshine/credentials/` (client certificates / private keys)
- EDID dumped from an actual Samsung panel (may carry PnP ID / trademarked strings)
- Personal network identifiers (real IPs, MACs, hostnames, WireGuard keys)

### Vulnerability reports

See [`SECURITY.md`](./SECURITY.md).

---

## License

MIT — see [`LICENSE`](./LICENSE).

---

## Trademark notice

"Galaxy", "Galaxy Tab", "Galaxy Book", "DeX", and "Super Display" are trademarks of Samsung Electronics Co., Ltd. This project is an independent open-source effort unaffiliated with Samsung, and those terms appear here solely for descriptive / compatibility purposes.

"Moonlight" and "Sunshine" are the names of the Moonlight Stream and LizardByte projects respectively.

---

## Credits

- [Sunshine](https://github.com/LizardByte/Sunshine) — self-hosted game streaming host
- [Moonlight](https://github.com/moonlight-stream) — NVIDIA GameStream compatible client
- [edid-decode](https://git.linuxtv.org/edid-decode.git) — EDID validation reference
- [linuxhw/EDID](https://github.com/linuxhw/EDID) — real-world EDID references (not bundled)
