# arch-galaxytab-submonitor

**[English](README.md)** &nbsp;|&nbsp; [한국어](README.ko.md)

---

An open stack for using a Samsung Galaxy Tab as a secondary display on Arch Linux. A custom-EDID virtual output, low-latency game-stream style transport, and touch/pen return-input together reproduce the Windows Super Display / spacedesk workflow on Linux.

Born from the fact that there is no first-class native-resolution secondary-monitor solution for Galaxy Tab on Linux — only crude web-based tools exist.

> **Status: alpha / personal.** Target-validated only on a Galaxy Book Ultra 3 (Intel + NVIDIA PRIME Optimus) host and a Galaxy Tab S9 Ultra client. Other combinations are unverified.
>
> **Working, measured on hardware:** the 2960×1848 virtual output coming up from boot with no debugfs help, KDE extending onto it, `hevc_vaapi` capture of that output, Moonlight streaming over USB-C tethering, and mDNS discovery through Avahi.
>
> **Not verified yet:**
> - **Pen / touch return input.** The `uinput` path is wired and `/dev/uinput` is writable, but no input has actually been round-tripped — Sunshine's virtual input device has never appeared in `/proc/bus/input/devices`.
> - **Wi-Fi 6E transport.** Only USB-C tethering has been exercised; the firewall rules scope Sunshine to that interface alone.

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
  session.sh          Day-to-day: start Sunshine and report readiness
  verify.sh           Read-only post-install check
  uninstall.sh        Reverses install.sh, dry-run by default
docs/
  troubleshooting.md  Measured failure modes and their fixes
```

The installer auto-detects your bootloader, initramfs tool, and AUR helper.
Override with `--bootloader`, `--initramfs`, `--pkg` flags; see `--help` for all options.

## Usage

### 1. Install

The installer is dry-run by default and prints every change it would make, so
run it once bare and read the output before committing to anything.

```bash
./install.sh                              # dry-run
./install.sh --apply                      # apply
./install.sh --apply --profile tabs9_100hz  # a different refresh rate
```

It auto-detects your bootloader, initramfs tool and AUR helper; override any of
them with `--bootloader`, `--initramfs`, `--pkg`. See `--help` for everything.

The bootloader entry and initramfs config are backed up with a timestamp before
they are edited. Re-running `--apply` is a no-op for anything already in place,
including the initramfs: it is only rebuilt when the blob or the config actually
changed, which matters on a Secure Boot system where the rebuild drags kernel
re-signing along with it.

By default the installer runs `systemctl --user enable --now`, so Sunshine comes
up with your graphical session. If you would rather launch it yourself:

```bash
./install.sh --apply --no-enable          # start it, leave autostart alone
```

Autostart and "running right now" are independent. `systemctl --user disable`
removes the autostart symlink without stopping anything, and the service can
still be started by hand afterwards. Without `--no-enable`, a later `--apply`
would quietly re-enable autostart and undo that choice — which is the whole
reason the flag exists. `scripts/verify.sh` reports the two states separately.

One caveat: the unit ships `Alias=sunshine.service`, but the alias symlink is
created by `enable`. Until you have enabled it once, the short
`systemctl --user start sunshine` will not resolve; use the full unit name
`app-dev.lizardbyte.app.Sunshine.service`.

### 2. Reboot, then verify

The kernel parameters only take effect on the next boot, and the EDID has to be
readable that early — which is why it goes into the initramfs.

```bash
./scripts/verify.sh
```

Read-only, exits non-zero on failure. A healthy run reports the blob and its
CTA-861 blocks, both kernel parameters active, the blob present in every
initramfs image, the connector `connected` at your profile's resolution, and
Sunshine's capabilities, service and capture target.

### 3. Point Sunshine at the virtual output

Without this Sunshine captures whatever display it considers default — usually
the built-in panel, so you end up mirroring instead of extending. The index is
the order these lines appear in, starting at 0:

```bash
journalctl --user -u app-dev.lizardbyte.app.Sunshine.service | grep 'Found monitor'
```

```
[wayland] Found monitor: Built-in Screen                         <- 0
[wayland] Found monitor: The Linux Foundation HDMI-A-1-Virtual Sub  <- 1
```

```bash
./install.sh --apply --sunshine-output 1
```

### 4. Match the display scale

A new output comes up at scale 1. On a 14.6" 2960×1848 panel that renders
everything at roughly half the size it has on a laptop screen — legible in a
screenshot, not in use.

```bash
kscreen-doctor output.HDMI-A-1.scale.2
```

Scale 2 gives a logical 1480×924, which is close enough to a typical 1440×900
laptop desktop that UI elements end up the same physical size on both.

### 5. Create the Sunshine web UI login

First run only. Open <https://localhost:47990>, accept the self-signed
certificate, and set a username and password. Those credentials and your pairing
keys live in `~/.config/sunshine/`, which `.gitignore` blocks and
`scripts/uninstall.sh` deliberately never touches.

### 6. Connect the tablet and open the firewall

USB-C tethering is the tested transport. Enable it on the tablet, then confirm
the host picked up an address:

```bash
ip -br addr show label 'enp*u*'
```

Sunshine binds `0.0.0.0`, so scope it to that interface rather than exposing it
to every network. Ports: TCP 47984 (pairing), 47989 (control), 48010 (RTSP) and
UDP 47998–48000, 48002 (video, audio, mic). Leave 47990 closed — the web UI
belongs on localhost.

```
define TAB_IF = "enp0s13f0u*"
iifname $TAB_IF tcp dport { 47984, 47989, 48010 } accept
iifname $TAB_IF udp dport { 47998-48000, 48002 } accept
```

Use `iifname` with a wildcard, never `iif`. See the security notice below for
why that distinction can cost you the whole firewall.

### 7. Optional: mDNS discovery, so the address stops mattering

The tablet is the DHCP server over USB tethering, so the host's address changes
whenever you re-tether — and Moonlight remembers addresses, not names. Letting
Sunshine advertise itself removes the problem entirely.

Sunshine publishes `_nvstream._tcp` through `libavahi-client`, so it needs
`avahi-daemon` running. Only one process can bind UDP 5353, and on a systemd
system `systemd-resolved` usually holds it, so hand the port over:

```bash
sudo pacman -S avahi nss-mdns
sudo mkdir -p /etc/systemd/resolved.conf.d
printf '[Resolve]\nMulticastDNS=no\n' \
  | sudo tee /etc/systemd/resolved.conf.d/10-no-mdns.conf
sudo systemctl restart systemd-resolved
sudo systemctl enable --now avahi-daemon
```

`nss-mdns` keeps host-side `.local` lookups working now that resolved is out of
the picture. Add it to `/etc/nsswitch.conf` before the `dns` entry:

```
hosts: files mdns_minimal [NOTFOUND=return] myhostname dns
```

Then let mDNS through the firewall. It is multicast to `224.0.0.251` / `ff02::fb`,
so a rule that only permits private unicast ranges will not cover the replies —
the outbound port has to be allowed explicitly:

```
iifname $TAB_IF udp dport 5353 accept          # in the input chain
... 5353 ...                                   # add to your outbound UDP ports
```

Restart Sunshine, then confirm it is actually advertising:

```bash
systemctl --user restart app-dev.lizardbyte.app.Sunshine.service
avahi-browse -atr | grep nvstream
```

You should see your hostname against `_nvstream._tcp` with the tethering address
and port 47989. Moonlight will then find the host by itself.

### 8. Pair Moonlight

Install [Moonlight](https://moonlight-stream.org/) on the tablet and open it.
With step 7 done the host appears on its own; without it, add the host's address
manually. Tap it, and enter the PIN it shows in the Sunshine web UI. Pairing is
trust-on-first-use over a 4-digit PIN, so do it on a link you trust — over USB
tethering that is just the cable.

In Moonlight's settings, pick **HEVC** and raise the bitrate. The default is far
too low for 2960×1848; USB tethering has the headroom for 50–100 Mbps. Do not
pick AV1 unless your host GPU can encode it — Intel iGPUs through Raptor Lake
decode AV1 but cannot encode it, and Sunshine will fall back to software.

### Day to day

Once installed, the virtual output is simply there — it comes up from the kernel
command line at boot and needs nothing from this repo. All that is left is
having Sunshine running before you reach for the tablet:

```bash
./scripts/session.sh
```

```
  virtual output   2960x1848, scale 2
  sunshine         started (was inactive)
  capture target   output_name = 1  -> ...HDMI-A-1-Virtual Sub
  encoder          hevc_vaapi [vaapi]
  firewall         active, Sunshine ports open
  tethering        <iface> <address>
  discovery        advertised over mDNS

══ Ready — open Moonlight on the tablet ══
```

It starts the service if it is not running and then checks the things that
actually stop a connection: an output stuck at scale 1, a capture target
pointing at the wrong screen, a software encoder fallback, a firewall with no
rule for Sunshine, tethering that is not up, and whether mDNS is advertising.
Non-zero exit if any of those are wrong. `--no-start` reports without touching
anything, and `--stop` shuts Sunshine down again.

If you would rather Sunshine were not resident — no tray icon sitting there when
you are not using the tablet — turn autostart off once and drive it from the
script:

```bash
systemctl --user disable app-dev.lizardbyte.app.Sunshine.service
./scripts/session.sh          # when you want the second screen
./scripts/session.sh --stop   # when you are done
```

`disable` only removes the autostart symlink; the service still starts on
demand. Install with `--no-enable` to skip the enable step in the first place,
and keep using it on later `--apply` runs so the installer does not quietly turn
autostart back on.

Nothing else needs stopping. The virtual output is a boot-time thing and costs
nothing while idle — only Sunshine is worth turning off.

Do not use `install.sh` for this. It edits the bootloader entry and can rebuild
the initramfs; it is an installer, not a launcher.

### Uninstall

```bash
./scripts/uninstall.sh                    # dry-run
./scripts/uninstall.sh --apply            # reverse everything
./scripts/uninstall.sh --apply --purge    # and remove the Sunshine package
```

Reverses the kernel parameters, initramfs entry, EDID blob, capabilities, group
and udev rule. Your Sunshine configuration and pairing keys are left alone.

---

## Security Notice

**This stack requires several privilege-escalation points. Do not deploy it on untrusted or public networks as-is.**

### Things you must be aware of

1. `setcap cap_sys_admin+p sunshine` grants kernel-grade capability to the Sunshine binary permanently. An upstream RCE in Sunshine would be immediately root-equivalent. Watch [Sunshine Security Advisories](https://github.com/LizardByte/Sunshine/security) and pin a minimum tested version in your local deployment.
2. Moonlight pairing uses a **4-digit PIN on trust-on-first-use**. Pair only on a trusted LAN.
3. Sunshine binds to `0.0.0.0` with UPnP enabled by default. Firewall the service to a USB tethering NIC or a WireGuard interface. If you scope an nftables rule to that NIC, match it with `iifname` and a wildcard rather than `iif` — `iif` resolves the name at load time, so a USB NIC that is absent at boot or came back on a different port makes the whole ruleset fail to load and leaves you with no firewall at all. See [`docs/troubleshooting.md`](docs/troubleshooting.md).
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
