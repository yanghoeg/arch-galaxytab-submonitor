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
 │   params    │   │ @ 60Hz   │   │          │   │            │
 └─────────────┘   └──────────┘   └──────────┘   └────────────┘
                                        ^               │
                                        │  touch / pen  │
                                        └───────────────┘
```

1. **Virtual display** — `drm.edid_firmware` + `video=HDMI-A-1:e` enables a synthetic 2960×1848 @ 60 Hz connector on the i915 driver.
2. **Capture / encode** — Sunshine grabs that output through KMS/Wayland and encodes it with `hevc_vaapi` on the Intel iGPU. NVENC is not usable here: on a PRIME/Optimus laptop the discrete GPU drives no display, so Sunshine's NVENC path reports `Couldn't find monitor [0]`. Raptor Lake-P has no AV1 encoder either, so HEVC is the target.
3. **Transport** — USB-C tethering (tested) or Wi-Fi 6E (unverified). Note that `adb reverse` forwards TCP only, so it cannot carry Moonlight's UDP video and audio; plain USB tethering is what the tested path uses.
4. **Input return** — Moonlight's native touch / pen events are injected back into the host via a `uinput` virtual device.

### Why 60 Hz and not 120

An EDID detailed timing descriptor stores the pixel clock as a 16-bit count of 10 kHz units, so it cannot express more than **655.35 MHz**. 2960×1848 @ 120 Hz needs 713.55 MHz with CVT-RB2 blanking — and 656.41 MHz even with zero blanking, which still overflows. That mode is simply not encodable in an EDID; no amount of timing tuning gets around it.

`edid/generate.py` therefore ships three profiles at the tablet's native resolution:

| Profile | Pixel clock | Note |
|---------|-------------|------|
| `tabs9_60hz` (default) | 346.74 MHz | Large margin |
| `tabs9_85hz` | 497.16 MHz | Measured working on the target host |
| `tabs9_95hz` | 558.25 MHz | Measured working on the target host |
| `tabs9_100hz` | 589.15 MHz | Highest encodable at native resolution |

Select one with `--profile`. The generator refuses any mode it cannot encode rather than emitting a silently truncated blob.

Which profiles a given machine can actually drive is platform-dependent — the display PLL cannot synthesise every pixel clock, and the gaps are not advertised anywhere. On the target host 88 Hz and 90 Hz are pruned while 85, 95 and 100 Hz are accepted, so a missing mode is not necessarily a bad blob. The connector is the oracle: `cat /sys/class/drm/card*-HDMI-A-1/modes`.

### The EDID needs a CTA-861 extension

A base-block-only EDID does not work, however correct its timings are. Without a CTA-861 extension carrying the HDMI IEEE OUI `00-0C-03`, the kernel classifies the sink as DVI and prunes anything above **165 MHz** — measured on the target host, 148 MHz passes and 168 MHz does not, so every mode this project targets disappears. Above 340 MHz the HDMI Forum VSDB (`C4-5D-D8`) is additionally required to declare the character rate.

`edid/generate.py` emits both, which is why a correct blob is 256 bytes rather than 128, and `scripts/verify.sh` asserts they are present. See [`docs/troubleshooting.md`](docs/troubleshooting.md) for the measurements.

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
- [Sunshine](https://github.com/LizardByte/Sunshine) — AUR, either `sunshine` (source) or `sunshine-bin` (prebuilt, the installer default). Override with `--sunshine-pkg`.
- [Moonlight](https://moonlight-stream.org/) Android client
- `intel-media-driver` — **required for hardware encoding.** Without it libva cannot initialise and Sunshine falls back to `libx264` with no warning.
- `edid-decode` — optional, used by `scripts/verify.sh` to validate the installed blob

---

## Repository layout

```
install.sh            Entry point — dry-run by default, --apply to apply
lib/
  util.sh             Logging, dry-run aware executors, string helpers
  bootstrap.sh        Platform detection + adapter loading, shared by both entry points
  ports.sh            Auto-detection + port dispatcher functions
  core.sh             Install steps (EDID → kernel → initramfs → Sunshine → udev)
adapters/
  bootloader/         systemd_boot.sh · grub.sh
  initramfs/          mkinitcpio.sh · dracut.sh
  pkg/                yay.sh · paru.sh · pacman.sh
edid/
  generate.py         CVT-RB2 EDID 1.4 generator, output validated with edid-decode
  generated/          Generated .bin blobs (installer output path)
udev/                 uinput access rules  (sunshine-uinput group)
scripts/
  verify.sh           Read-only post-install check
  uninstall.sh        Reverses install.sh, dry-run by default
docs/
  troubleshooting.md  Measured failure modes and their fixes
```

The installer auto-detects your bootloader, initramfs tool, and AUR helper.
Override with `--bootloader`, `--initramfs`, `--pkg` flags; see `--help` for all options.

## Usage

```bash
./install.sh                            # dry-run: prints every change it would make
./install.sh --apply                    # apply
./install.sh --apply --profile tabs9_100hz

# after rebooting
./scripts/verify.sh                     # read-only check, non-zero exit on failure
./scripts/uninstall.sh --apply          # reverse everything
```

Two things are not automatic once the virtual output exists:

```bash
# 1. point Sunshine at it — otherwise it keeps capturing the built-in panel.
#    Find the index (order of the lines, from 0):
journalctl --user -u app-dev.lizardbyte.app.Sunshine.service | grep 'Found monitor'
./install.sh --apply --sunshine-output 1

# 2. match the scale of your built-in panel — a new output comes up at scale 1,
#    which on a 14.6" 2960x1848 panel renders everything at about half size.
kscreen-doctor output.HDMI-A-1.scale.2
```

Still open: reboot verification of the boot path, touch/pen return, and the Wi-Fi 6E transport. Streaming and pairing work.

---

## Security Notice

**This stack requires several privilege-escalation points. Do not deploy it on untrusted or public networks as-is.**

### Things you must be aware of

1. `setcap cap_sys_admin+p sunshine` grants kernel-grade capability to the Sunshine binary permanently. An upstream RCE in Sunshine would be immediately root-equivalent. Watch [Sunshine Security Advisories](https://github.com/LizardByte/Sunshine/security) and pin a minimum tested version in your local deployment.
2. Moonlight pairing uses a **4-digit PIN on trust-on-first-use**. Pair only on a trusted LAN.
3. Sunshine binds to `0.0.0.0` with UPnP enabled by default. Firewall the service to a USB tethering NIC or a WireGuard interface.
4. Opening `uinput` lets any process in the logged-in session create virtual input devices — a latent keylogger / automation surface. This repo's udev rule puts the node in a dedicated `sunshine-uinput` group, but be aware that the Sunshine packages ship their own rule with `TAG+="uaccess"`, which grants the logged-in user an ACL regardless. The group is therefore tidiness, not a boundary; `scripts/verify.sh` says so when it detects the package rule, and [`docs/troubleshooting.md`](docs/troubleshooting.md) explains how to actually enforce it.
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
