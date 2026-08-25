# Troubleshooting

Everything below was measured on the target combination (Galaxy Book Ultra 3,
Raptor Lake-P iGPU, KDE Plasma 6 on Wayland, Galaxy Tab S9 Ultra). Numbers are
from that host; the failure modes are general, the exact thresholds are not.

---

## The mode never appears

`/sys/class/drm/card*-HDMI-A-1/modes` is empty, or lists only fallback modes
like `1024x768`, even though `status` says `connected` and `edid-decode` reports
your blob correctly.

**Cause.** The EDID has only a base block. Without a CTA-861 extension carrying
the HDMI IEEE OUI `00-0C-03`, the kernel classifies the sink as DVI and refuses
anything above **165 MHz** — which prunes every mode this project targets.

Measured with the same generator, varying only the mode:

| Mode | Pixel clock | Result |
|------|-------------|--------|
| 1920x1200@60 | 148.20 MHz | accepted |
| 2048x1280@60 | 168.15 MHz | pruned |
| 2560x1440@60 | 234.59 MHz | pruned |
| 2960x1848@60 | 346.74 MHz | pruned |

And with the CTA block added, holding the mode fixed at 2960x1848@60:

| EDID | Result |
|------|--------|
| base block only | pruned |
| + CTA-861 with HDMI VSDB | pruned |
| + HDMI Forum VSDB | **accepted** |

Above 340 MHz the HDMI 1.4b VSDB is not enough — the HDMI Forum VSDB
(OUI `C4-5D-D8`) must declare the character rate as well.

**Fix.** `edid/generate.py` emits both automatically; a correct blob is 256
bytes, not 128. `scripts/verify.sh` asserts their presence. If you built a blob
by hand, check it with:

```bash
edid-decode your.bin | grep OUI
```

---

## Only certain refresh rates get pruned

The 60 Hz profile works but another one silently produces no mode, and the EDID
passes every check.

**Cause.** The display PLL cannot synthesise every pixel clock, and the gaps are
not advertised anywhere. This is not a ceiling — rates above the gap work again.

Measured at 2960x1848, CTA block present:

| Refresh | Pixel clock | Result |
|---------|-------------|--------|
| 60 Hz | 346.74 MHz | accepted |
| 85 Hz | 497.16 MHz | accepted |
| 88 Hz | 515.24 MHz | pruned |
| 90 Hz | 527.50 MHz | pruned |
| 95 Hz | 558.25 MHz | accepted |
| 100 Hz | 589.15 MHz | accepted |

**Fix.** Try a neighbouring profile. The connector is the oracle — after
switching, check:

```bash
cat /sys/class/drm/card*-HDMI-A-1/modes
```

You can test a blob without rebooting or touching your bootloader:

```bash
CONN=/sys/kernel/debug/dri/1/HDMI-A-1
SYS=/sys/class/drm/card1-HDMI-A-1
echo detect | sudo tee $SYS/status      # always reset first, see below
sudo cp your.bin $CONN/edid_override
echo on | sudo tee $SYS/status
cat $SYS/modes
echo detect | sudo tee $SYS/status      # undo
```

Reset to `detect` before each attempt. The kernel only re-probes when the forced
state actually changes, so writing `on` twice in a row leaves the previous
result in place and looks like a failure.

---

## The picture is soft or the encoder is pegging a CPU core

`journalctl --user -u app-dev.lizardbyte.app.Sunshine.service` shows:

```
Found H.264 encoder: libx264 [software]
```

**Cause.** Every hardware encoder was rejected and Sunshine fell back to
software without saying so loudly. The three usual reasons, all seen on this
host:

- `Couldn't initialize va display: unknown libva error` — no VAAPI driver is
  installed. Check `ls /usr/lib/dri/*_drv_video.so`; if there is no
  `iHD_drv_video.so`, install `intel-media-driver`.
- `Couldn't find monitor [0]` under `Trying encoder [nvenc]` — on a PRIME /
  Optimus laptop the discrete GPU drives no display, so the NVENC capture path
  finds nothing. Since capture already happens on the iGPU, VAAPI is both the
  shorter path and the one that works.
- `Device does not support the VK_KHR_video_encode_queue extension` — the
  Vulkan device has no encode queue. Nothing to do; let it fall through.

**Fix.** Install the driver and restart the service. A healthy log reads:

```
Found H.264 encoder: h264_vaapi [vaapi]
Found HEVC encoder:  hevc_vaapi [vaapi]
```

`Could not open codec [av1_vaapi]: Function not implemented` is expected on
Raptor Lake-P — that iGPU decodes AV1 but cannot encode it. Select **HEVC** in
Moonlight; picking AV1 forces the software path back.

---

## Text on the tablet is too small to read

**Cause.** Output scale, not resolution. A fresh virtual output comes up at
scale 1, so at 2960x1848 on a 14.6" panel (~239 PPI) everything renders at
roughly half the size it has on the laptop panel.

**Fix.** Match the built-in panel's scale:

```bash
kscreen-doctor output.HDMI-A-1.scale.2
```

That gives a logical 1480x924 against the built-in panel's 1440x900 — near
identical, so UI elements end up the same physical size on both.

Do **not** lower the EDID resolution to make text bigger. 2960x1848 is the
tablet's native panel resolution; anything smaller makes the tablet upscale and
text gets blurrier, not larger.

---

## The wrong screen is being streamed

Moonlight shows the laptop's built-in display, complete with desktop icons,
instead of the virtual output.

**Cause.** Sunshine captures its default display unless told otherwise.

**Fix.** Find the index — the order of these lines is the index order, starting
at 0:

```bash
journalctl --user -u app-dev.lizardbyte.app.Sunshine.service | grep 'Found monitor'
```

```
[wayland] Found monitor: Built-in Screen
[wayland] Found monitor: The Linux Foundation HDMI-A-1-Virtual Sub
```

Then either re-run `./install.sh --apply --sunshine-output 1`, or set
`output_name = 1` in `~/.config/sunshine/sunshine.conf` and restart the service.
`scripts/verify.sh` reports the current value.

A quick way to tell the two apart without looking at logs: the extended output
has no desktop icons on it, only the wallpaper.

---

## Enforcing the uinput group properly

`udev/60-tabdisp-uinput.rules` puts `/dev/uinput` in a `sunshine-uinput` group,
but the Sunshine packages ship `/usr/lib/udev/rules.d/60-sunshine.rules` with
`TAG+="uaccess"`. That hands the logged-in user an ACL regardless:

```
$ getfacl -p /dev/uinput
user::rw-
user:yanghoeg:rw-      <- uaccess, not the group
group::---
```

Our file sorts after theirs, so the group is applied, but the ACL still wins.
Treat the group as tidiness rather than an access boundary — `verify.sh` says so
explicitly when it detects the package rule.

To actually enforce the group you have to shadow the package file, because a
file in `/etc/udev/rules.d` overrides the same name in `/usr/lib/udev/rules.d`:
copy `60-sunshine.rules` to `/etc/udev/rules.d/`, drop the `TAG+="uaccess"`
clauses, and keep the rest. The cost is that you now own that file — the gamepad
rules in it stop tracking package updates, so re-check it after every Sunshine
upgrade.
