# Security Policy

## Threat model

`arch-galaxytab-submonitor` is designed to operate on a **private LAN or a USB-tethered link**. Deployment on public Wi-Fi, untrusted LAN segments, or hostile networks is outside the design scope.

### Known privilege-escalation points

| Surface | Description | Mitigation |
|---------|-------------|------------|
| `cap_sys_admin+p` on Sunshine | Kernel-grade capability for KMS capture | Pin Sunshine version, monitor CVEs |
| `uinput` access | Virtual input device creation privilege | Scope to a dedicated group (`sunshine-uinput`) |
| Sunshine HTTP(S) endpoints | Ports 47984 / 47989 / 47990 / 48010 exposed | Firewall to a specific NIC only |
| Moonlight pairing | 4-digit PIN on trust-on-first-use | First-time pairing only on a trusted LAN |

For deeper background see [`README.md` §Security Notice](./README.md#security-notice).

## Reporting a vulnerability

For security problems in the configurations / scripts / documentation in *this* repository:

- **Low sensitivity** — open a public GitHub Issue.
- **High sensitivity** — use GitHub's Security Advisory → "Report a vulnerability" for a private submission.

**For upstream issues, report to the upstream project**:

- Sunshine: https://github.com/LizardByte/Sunshine/security
- Moonlight: https://github.com/moonlight-stream
- Linux DRM / i915: https://www.kernel.org/doc/html/latest/process/security-bugs.html

## Supported versions

Currently at the alpha stage. Only the `main` branch is maintained; no release tags yet. Security updates will target the latest tag once the first release is cut.

## Assets never to commit

Blocked by `.gitignore`, but contributors should still verify manually before opening a PR:

- Sunshine state files and client certificates (`sunshine_state.json`, `credentials/`)
- EDID dumped from real panels (`*_dumped.bin`, `panel_*.bin`)
- Personal network identifiers (IPs, MACs, hostnames, WireGuard keys)
- Any `.env`, `*.local.*`, or personal authentication tokens
