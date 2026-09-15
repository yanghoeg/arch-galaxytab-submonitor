# arch-galaxytab-submonitor

**[English](README.md)** &nbsp;|&nbsp; [한국어](README.ko.md)

---

Use a Samsung Galaxy Tab as a second monitor for an Arch Linux laptop, at the
tablet's native resolution. The host fakes an HDMI monitor with a custom EDID,
Sunshine streams it over the USB cable, Moonlight on the tablet shows it. What
Super Display and spacedesk do on Windows, without the web-based compromise.

## Coming back to this?

Install is a one-off. After that there are three commands, all in `scripts/`:

| I want to… | Run |
|---|---|
| put the desktop on the tablet | `./scripts/session.sh` |
| stop, and get my real screens back to normal | `./scripts/session.sh --stop` |
| find out why it is not working | `./scripts/verify.sh` |

`session.sh` brings the virtual screen up, starts Sunshine, and prints a
checklist ending in either `Ready — open Moonlight on the tablet` or the thing
that is wrong. Then open Moonlight on the tablet and tap the host.

Never installed it? Start at [First-time setup](#first-time-setup).
Something looks off? [`docs/troubleshooting.md`](docs/troubleshooting.md)
lists every failure seen so far and what fixed it.

> **Status: alpha / personal.** Validated on one combination only — a Galaxy
> Book Ultra 3 (Intel + NVIDIA PRIME Optimus) host and a Galaxy Tab S9 Ultra
> client. Working on that hardware: the 2960×1848 virtual output from a cold
> boot, KDE extending onto it, `hevc_vaapi` capture, Moonlight over USB-C
> tethering, mDNS discovery. **Not verified:** pen/touch return input (wired,
> never round-tripped) and the Wi-Fi 6E transport (only USB-C tested).

---

## Usage

### Every time you use it

```bash
./scripts/session.sh
```

```
  virtual output   2960x1848, scale 2 at 4096,0
  sunshine         started (was inactive)
  capture target   output_name = 1  -> ...HDMI-A-1-Virtual Sub
  encoder          hevc_vaapi [vaapi]
  firewall         active, Sunshine ports open
  tethering        <iface> <address>
  discovery        advertised over mDNS

══ Ready — open Moonlight on the tablet ══
```

Each line is something that has actually stopped a connection at some point.
The script enables the virtual output and places it to the right of your real
screens, sets its scale, starts Sunshine if needed, then checks the rest. It
exits non-zero if any line is wrong.

```bash
./scripts/session.sh --stop       # stop Sunshine, park the virtual output
./scripts/session.sh --no-start   # just report, change nothing
```

Always `--stop` when you are done. The virtual output is not free while idle:
left enabled it sits on top of a real monitor and every window that lands on it
stops maximising properly. (Why that happens is under [How it
works](#why-the-virtual-output-gets-parked). If you forget, a login-time unit
parks it for you at the next login.)

### First-time setup

Six steps. Two of them need a reboot or a phone in your hand, so this is not a
one-liner — but nothing here is repeated later.

#### 1. Install

```bash
./install.sh            # dry-run: prints every change it would make
./install.sh --apply    # do it
```

Dry-run is the default; read it once before applying. The installer detects
your bootloader, initramfs tool and AUR helper (override with `--bootloader`,
`--initramfs`, `--pkg`), backs up the bootloader entry and initramfs config
before touching them, and is a no-op on re-run for anything already in place.
`--help` lists everything.

#### 2. Reboot, then verify

The kernel parameters take effect on the next boot.

```bash
./scripts/verify.sh
```

Read-only; non-zero exit if anything is wrong. A clean run shows the blob and
its CTA-861 blocks, both kernel parameters active, the blob inside every
initramfs image, the connector `connected` at 2960×1848, and Sunshine's
capabilities, service and capture target.

#### 3. Tell Sunshine which screen to capture

Without this Sunshine grabs its default display — the built-in panel — and you
get a mirror instead of a second screen. Find the index (line order, from 0):

```bash
journalctl --user -u app-dev.lizardbyte.app.Sunshine.service | grep 'Found monitor'
```

```
[wayland] Found monitor: Built-in Screen                            <- 0
[wayland] Found monitor: The Linux Foundation HDMI-A-1-Virtual Sub  <- 1
```

```bash
./install.sh --apply --sunshine-output 1
```

#### 4. Create the Sunshine login

First run only. Open <https://localhost:47990>, accept the self-signed
certificate, set a username and password. These and your pairing keys live in
`~/.config/sunshine/`, which `.gitignore` blocks and `uninstall.sh` never
touches.

#### 5. Connect the tablet and open the firewall

Enable USB tethering on the tablet, then confirm the host got an address:

```bash
ip -br addr show label 'enp*u*'
```

Sunshine binds `0.0.0.0`. Scope it to that interface instead of every network.
Ports: TCP 47984 (pairing), 47989 (control), 48010 (RTSP); UDP 47998–48000,
48002 (video, audio, mic). Leave 47990 closed — the web UI stays on localhost.

```
define TAB_IF = "enp0s13f0u*"
iifname $TAB_IF tcp dport { 47984, 47989, 48010 } accept
iifname $TAB_IF udp dport { 47998-48000, 48002 } accept
```

Use `iifname` with a wildcard, never `iif`. The difference can cost you the
whole firewall — see the [security notice](#security-notice).

#### 6. Pair Moonlight

Install [Moonlight](https://moonlight-stream.org/) on the tablet. Add the host
by the address from step 5 (or skip that with mDNS, below), tap it, and type the
PIN it shows into the Sunshine web UI. Pairing is trust-on-first-use over a
4-digit PIN, so do it over the cable.

In Moonlight's settings pick **HEVC** and raise the bitrate — the default is far
too low for 2960×1848 and USB tethering has room for 50–100 Mbps. Do not pick
AV1 unless your host GPU can encode it; Intel iGPUs through Raptor Lake decode
AV1 but cannot encode it, and Sunshine silently falls back to software.

#### Optional: mDNS, so the address stops mattering

Over USB tethering the tablet is the DHCP server, so the host's address changes
whenever you re-tether, and Moonlight remembers addresses rather than names.
Letting Sunshine advertise itself removes the problem.

Sunshine publishes `_nvstream._tcp` through `libavahi-client`, so it needs
`avahi-daemon`. Only one process can hold UDP 5353, and `systemd-resolved`
usually does, so hand it over:

```bash
sudo pacman -S avahi nss-mdns
sudo mkdir -p /etc/systemd/resolved.conf.d
printf '[Resolve]\nMulticastDNS=no\n' \
  | sudo tee /etc/systemd/resolved.conf.d/10-no-mdns.conf
sudo systemctl restart systemd-resolved
sudo systemctl enable --now avahi-daemon
```

`nss-mdns` keeps host-side `.local` lookups working. In `/etc/nsswitch.conf`,
before `dns`:

```
hosts: files mdns_minimal [NOTFOUND=return] myhostname dns
```

mDNS is multicast to `224.0.0.251` / `ff02::fb`, which a rule that only allows
private unicast ranges will not cover — allow the port both ways:

```
iifname $TAB_IF udp dport 5353 accept          # input chain
... 5353 ...                                   # your outbound UDP port set
```

Restart Sunshine and confirm it is advertising:

```bash
systemctl --user restart app-dev.lizardbyte.app.Sunshine.service
avahi-browse -atr | grep nvstream
```

### Running Sunshine only when you need it

The installer enables Sunshine for your graphical session, so its tray icon is
resident from login. If you would rather it were not:

```bash
systemctl --user disable app-dev.lizardbyte.app.Sunshine.service   # once
./scripts/session.sh          # when you want the tablet
./scripts/session.sh --stop   # when you are done
```

`disable` only removes the autostart symlink; nothing stops, and the service
still starts on demand. Install with `--no-enable` to skip enabling in the first
place, and keep passing it on later `--apply` runs — otherwise the installer
quietly turns autostart back on. `verify.sh` reports "running" and "enabled"
as separate lines for exactly this reason.

Two things to know. The unit is aliased `sunshine.service`, but the alias
symlink is created by `enable`, so until you have enabled it once the short
name will not resolve — use `app-dev.lizardbyte.app.Sunshine.service`. And do
not use `install.sh` as a launcher: it edits the bootloader entry and can
rebuild the initramfs. That is what `session.sh` is for.

### Uninstall

```bash
./scripts/uninstall.sh                    # dry-run
./scripts/uninstall.sh --apply            # reverse everything
./scripts/uninstall.sh --apply --purge    # and remove the Sunshine package
```

Reverses the kernel parameters, initramfs entry, EDID blob, capabilities, group,
udev rule and the login-time unit. Sunshine's configuration and pairing keys are
left alone.

---

## How it works

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

1. **Virtual display** — `drm.edid_firmware` + `video=HDMI-A-1:e` make the
   i915 driver bring up a 2960×1848 @ 60 Hz connector with nothing plugged in.
2. **Capture / encode** — Sunshine grabs that output through KMS/Wayland and
   encodes with `hevc_vaapi` on the Intel iGPU. NVENC does not work here: on a
   PRIME/Optimus laptop the discrete GPU drives no display, so Sunshine's NVENC
   path reports `Couldn't find monitor [0]`. Raptor Lake-P has no AV1 encoder
   either, so HEVC it is.
3. **Transport** — USB-C tethering (tested) or Wi-Fi 6E (not). `adb reverse`
   forwards TCP only and cannot carry Moonlight's UDP media, so plain tethering
   is the path.
4. **Input return** — Moonlight's touch and pen events are injected back into
   the host through a `uinput` virtual device. Wired up, not yet exercised.

### Why 60 Hz and not 120

An EDID detailed timing descriptor stores the pixel clock as a 16-bit count of
10 kHz units, so it cannot express more than **655.35 MHz**. 2960×1848 @ 120 Hz
needs 713.55 MHz with CVT-RB2 blanking, and 656.41 MHz even with zero blanking.
It cannot be encoded in an EDID at all; no timing trick gets around it.

`edid/generate.py` therefore ships these profiles at the tablet's native
resolution, selectable with `--profile`:

| Profile | Pixel clock | Note |
|---------|-------------|------|
| `tabs9_60hz` (default) | 346.74 MHz | Large margin |
| `tabs9_85hz` | 497.16 MHz | Measured working on the target host |
| `tabs9_95hz` | 558.25 MHz | Measured working on the target host |
| `tabs9_100hz` | 589.15 MHz | Highest encodable at native resolution |

The generator refuses any mode it cannot encode rather than emitting a silently
truncated blob. Which profiles a given machine can drive is platform-dependent:
the display PLL cannot synthesise every pixel clock and the gaps are not
advertised. On the target host 88 and 90 Hz are pruned while 85, 95 and 100 Hz
are accepted, so a missing mode is not necessarily a bad blob. The connector is
the oracle: `cat /sys/class/drm/card*-HDMI-A-1/modes`.

### The EDID needs a CTA-861 extension

A base-block-only EDID does not work, however correct its timings. Without a
CTA-861 extension carrying the HDMI IEEE OUI `00-0C-03`, the kernel classifies
the sink as DVI and prunes anything above **165 MHz** — measured: 148 MHz
passes, 168 MHz does not — which removes every mode this project targets. Above
340 MHz the HDMI Forum VSDB (`C4-5D-D8`) is additionally required to declare the
character rate.

`edid/generate.py` emits both, which is why a correct blob is 256 bytes rather
than 128, and `verify.sh` asserts they are present.

### Why the virtual output gets parked

`video=<connector>:e` forces the connector on for the whole uptime. That is the
point of it — a tablet has no way to assert hotplug — but it means KWin sees a
permanently connected 2960×1848 screen with nothing behind it, and puts it at
0,0: on top of whatever real monitor is already there.

Two outputs sharing a rectangle is a geometry problem, not a drawing one. KWin
assigns each window to exactly one output and maximises it into *that* output's
rectangle, so windows that land on the virtual one fill only its area. Measured
on a 5120×2880 panel at scale 2.5, "maximised" windows came out 1480×924 inside
a 2048×1152 desktop, with nothing in the KWin log to say why.

So the output is enabled only for as long as a session lasts and always placed
past the right edge of the real screens. `scripts/virtual-output.sh` is that
logic on its own:

```bash
./scripts/virtual-output.sh on       # enable, clear of everything else
./scripts/virtual-output.sh status   # exit 1 if it overlaps a real screen
./scripts/virtual-output.sh off      # park it
```

`on` also sets scale 2 if the output came up at 1. At 2960×1848 on a 14.6"
panel, scale 1 renders everything at half the size it has on a laptop screen;
scale 2 gives a logical 1480×924, close to a typical laptop desktop. A scale you
set by hand is kept; `on --scale 2.5` changes the default.

### What the login-time unit is for

`--stop` covers the tidy case. It does not cover shutting down from the tablet,
a crash, or forgetting: KWin restores the output layout it saved last, so the
virtual screen comes back enabled and overlapping, and the first symptom is that
windows will not maximise.

So the installer also enables `tabdisp-virtual-output.service`, a user unit that
parks the output once at every login. However a session ends, the next one
starts with real screens only.

```bash
systemctl --user status tabdisp-virtual-output.service
```

Its `ExecStart` points into this checkout — move or delete the repo and it
breaks; re-run `install.sh --apply` from the new location. `--no-output-reset`
installs the unit without enabling it.

---

## Requirements

| Component | Model | Note |
|-----------|-------|------|
| Host | Galaxy Book Ultra 3 | Intel Core i7 + RTX 4050 Max-Q; HDMI port wired to the Intel iGPU, not the dGPU |
| Client | Galaxy Tab S9 Ultra | 2960×1848, 120 Hz, AV1 hardware decode |
| Link | USB-C cable (tested) or Wi-Fi 6E (not) | |

- Arch Linux, kernel `linux` or `linux-zen` 6.x+
- KDE Plasma 6 on Wayland — other compositors unverified
- [Sunshine](https://github.com/LizardByte/Sunshine) from AUR: `sunshine` (source) or `sunshine-bin` (prebuilt, the default). `--sunshine-pkg` to choose.
- [Moonlight](https://moonlight-stream.org/) on the tablet
- `intel-media-driver` — **required for hardware encoding.** Without it libva cannot initialise and Sunshine falls back to `libx264` with no warning.
- `edid-decode` — optional; `verify.sh` uses it to validate the installed blob

---

## Repository layout

```
install.sh            Entry point — dry-run by default, --apply to apply
lib/
  util.sh             Logging, dry-run aware executors, string helpers
  bootstrap.sh        Platform detection + adapter loading, shared by both entry points
  ports.sh            Auto-detection + port dispatcher functions
  core.sh             Install steps (EDID → kernel → initramfs → Sunshine → session unit → udev)
adapters/
  bootloader/         systemd_boot.sh · grub.sh
  initramfs/          mkinitcpio.sh · dracut.sh
  pkg/                yay.sh · paru.sh · pacman.sh
edid/
  generate.py         CVT-RB2 EDID 1.4 generator, output validated with edid-decode
  generated/          Generated .bin blobs (installer output path)
udev/                 uinput access rules  (sunshine-uinput group)
systemd/
  tabdisp-virtual-output.service.in   Login-time unit that parks the virtual output
scripts/
  session.sh          Day-to-day: unpark the output, start Sunshine, report readiness
  virtual-output.sh   Enable the virtual output clear of the real ones, or park it
  verify.sh           Read-only post-install check
  uninstall.sh        Reverses install.sh, dry-run by default
docs/
  troubleshooting.md  Measured failure modes and their fixes
```

---

## Security notice

**This stack requires several privilege-escalation points. Do not deploy it on untrusted or public networks as-is.**

1. `setcap cap_sys_admin+p sunshine` grants kernel-grade capability to the Sunshine binary permanently. An upstream RCE in Sunshine would be immediately root-equivalent. Watch [Sunshine Security Advisories](https://github.com/LizardByte/Sunshine/security) and pin a minimum tested version in your local deployment.
2. Moonlight pairing uses a **4-digit PIN on trust-on-first-use**. Pair only on a trusted link.
3. Sunshine binds to `0.0.0.0` with UPnP enabled by default. Firewall the service to a USB tethering NIC or a WireGuard interface. If you scope an nftables rule to that NIC, match it with `iifname` and a wildcard rather than `iif` — `iif` resolves the name at load time, so a USB NIC that is absent at boot or came back on a different port makes the whole ruleset fail to load and leaves you with no firewall at all. See [`docs/troubleshooting.md`](docs/troubleshooting.md).
4. Opening `uinput` lets any process in the logged-in session create virtual input devices — a latent keylogger / automation surface. This repo's udev rule puts the node in a dedicated `sunshine-uinput` group, but the Sunshine packages ship their own rule with `TAG+="uaccess"`, which grants the logged-in user an ACL regardless. The group is tidiness, not a boundary; `verify.sh` says so when it detects the package rule, and [`docs/troubleshooting.md`](docs/troubleshooting.md) explains how to actually enforce it.
5. Capture should go through `xdg-desktop-portal`. Running privileged components as root to "work around it" is explicitly discouraged.

**Never commit** (blocked by `.gitignore`): `~/.config/sunshine/sunshine_state.json` and `~/.config/sunshine/credentials/` (pairing keys and client certificates), EDID dumped from a real Samsung panel (may carry PnP IDs or trademarked strings), and personal network identifiers (real IPs, MACs, hostnames, WireGuard keys).

Vulnerability reports: see [`SECURITY.md`](./SECURITY.md).

---

## License

MIT — see [`LICENSE`](./LICENSE).

## Trademark notice

"Galaxy", "Galaxy Tab", "Galaxy Book", "DeX", and "Super Display" are trademarks of Samsung Electronics Co., Ltd. This project is an independent open-source effort unaffiliated with Samsung, and those terms appear here solely for descriptive / compatibility purposes. "Moonlight" and "Sunshine" are the names of the Moonlight Stream and LizardByte projects respectively.

## Credits

- [Sunshine](https://github.com/LizardByte/Sunshine) — self-hosted game streaming host
- [Moonlight](https://github.com/moonlight-stream) — NVIDIA GameStream compatible client
- [edid-decode](https://git.linuxtv.org/edid-decode.git) — EDID validation reference
- [linuxhw/EDID](https://github.com/linuxhw/EDID) — real-world EDID references (not bundled)
