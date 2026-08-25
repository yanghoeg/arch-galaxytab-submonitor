# arch-galaxytab-submonitor

[English](README.md) &nbsp;|&nbsp; **[한국어](README.ko.md)**

---

Galaxy Tab을 Arch Linux의 보조 디스플레이로 사용하기 위한 오픈 스택. 커스텀 EDID 가상 출력 + 저지연 게임스트리밍 기반 전송 + 터치/펜 리턴 인풋을 묶어, Windows의 Super Display / spacedesk에 해당하는 워크플로를 리눅스에서 재현한다.

Galaxy Tab을 리눅스에서 네이티브 해상도 보조 모니터로 쓸 수 있는 1급 솔루션이 없다는 사실 — 웹 기반 조악한 도구만 존재 — 에서 출발한 프로젝트다.

> **Status: alpha / personal.** Galaxy Book Ultra 3 (Intel + NVIDIA PRIME Optimus) 호스트와 Galaxy Tab S9 Ultra 클라이언트 조합에서만 검증. 다른 하드웨어 조합은 미검증.
>
> **실기에서 확인된 것:** 2960×1848 가상 출력, KDE 확장 배치, 해당 출력의 `hevc_vaapi` 캡처, USB-C 테더링 경유 Moonlight 스트리밍.
>
> **아직 미검증:**
> - **펜 / 터치 리턴 인풋.** `uinput` 경로는 연결돼 있고 `/dev/uinput` 쓰기도 열려 있지만, 실제 입력을 왕복시켜 본 적이 없다 — Sunshine 가상 입력 장치가 `/proc/bus/input/devices` 에 나타난 적이 없다.
> - **Wi-Fi 6E 전송.** USB-C 테더링만 검증했고, 방화벽 규칙도 그 인터페이스에만 열려 있다.
> - **부팅 경로.** `install.sh --apply` 가 커널 파라미터를 쓰고 EDID를 initramfs에 넣지만 재부팅을 거치지 않았다 — 현재 떠 있는 가상 출력은 debugfs로 라이브 적용한 것이다.

---

## 아키텍처

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

1. **가상 디스플레이** — `drm.edid_firmware` + `video=HDMI-A-1:e` 로 i915 드라이버에 2960×1848 @ 60 Hz 합성 커넥터를 활성화.
2. **캡처 / 인코드** — Sunshine이 KMS/Wayland로 해당 출력을 잡아 Intel iGPU의 `hevc_vaapi` 로 인코드. NVENC는 이 구성에서 못 쓴다 — PRIME/Optimus 노트북은 dGPU가 디스플레이를 하나도 물지 않아 Sunshine의 NVENC 경로가 `Couldn't find monitor [0]` 로 실패한다. Raptor Lake-P에는 AV1 인코더도 없어 HEVC가 타깃이다.
3. **전송** — USB-C 테더링(검증됨) 또는 Wi-Fi 6E(미검증). `adb reverse` 는 TCP만 포워딩하므로 Moonlight의 UDP 비디오·오디오를 나를 수 없다 — 검증된 경로는 순수 USB 테더링이다.
4. **입력 리턴** — Moonlight의 네이티브 터치 / S펜 이벤트를 `uinput` 가상 장치로 호스트에 주입.

### 왜 120 Hz 가 아니라 60 Hz 인가

EDID detailed timing descriptor 는 픽셀클럭을 16비트 × 10 kHz 단위로 저장하므로 **655.35 MHz** 를 넘을 수 없다. 2960×1848 @ 120 Hz 는 CVT-RB2 블랭킹 기준 713.55 MHz 가 필요하고, 블랭킹을 0으로 둬도 액티브 픽셀만 656.41 MHz 라 여전히 초과한다. 즉 타이밍 조정으로 우회 가능한 문제가 아니라 EDID 포맷 자체가 표현하지 못하는 모드다.

따라서 `edid/generate.py` 는 태블릿 네이티브 해상도에서 세 가지 프로파일을 제공한다.

| 프로파일 | 픽셀클럭 | 비고 |
|----------|----------|------|
| `tabs9_60hz` (기본) | 346.74 MHz | 여유 큼 |
| `tabs9_85hz` | 497.16 MHz | 타깃 호스트에서 동작 실측 |
| `tabs9_95hz` | 558.25 MHz | 타깃 호스트에서 동작 실측 |
| `tabs9_100hz` | 589.15 MHz | 네이티브 해상도에서 인코딩 가능한 최대치 |

`--profile` 로 선택한다. 생성기는 인코딩 불가능한 모드를 조용히 잘라내지 않고 에러로 거부한다.

어느 프로파일이 실제로 동작하는지는 플랫폼에 달렸다 — 디스플레이 PLL이 모든 픽셀클럭을 합성하지 못하는데 그 공백은 어디에도 고지되지 않는다. 타깃 호스트에서는 88 Hz·90 Hz가 프루닝되고 85·95·100 Hz는 통과한다. 즉 모드가 안 뜬다고 블롭이 잘못된 것은 아니다. 판정 기준은 커넥터다: `cat /sys/class/drm/card*-HDMI-A-1/modes`.

### EDID에는 CTA-861 확장이 필요하다

타이밍이 아무리 정확해도 베이스 블록만으로는 동작하지 않는다. HDMI IEEE OUI `00-0C-03` 을 담은 CTA-861 확장이 없으면 커널이 싱크를 DVI로 판정해 **165 MHz** 를 넘는 모든 것을 프루닝한다 — 타깃 호스트 실측으로 148 MHz는 통과, 168 MHz는 프루닝이라 이 프로젝트가 노리는 모드는 전부 사라진다. 340 MHz를 넘으면 문자율을 고지할 HDMI Forum VSDB(`C4-5D-D8`)까지 추가로 필요하다.

`edid/generate.py` 는 둘 다 생성하며, 그래서 정상 블롭은 128바이트가 아니라 256바이트다. `scripts/verify.sh` 가 둘의 존재를 검사한다. 측정치는 [`docs/troubleshooting.md`](docs/troubleshooting.md) 참조.

---

## 요구 사항

### 하드웨어 (검증 예정 조합)

| 구성 | 모델 | 비고 |
|------|------|------|
| 호스트 | Galaxy Book Ultra 3 | Intel Core i7 + RTX 4050 Max-Q. HDMI 포트가 dGPU가 아닌 Intel iGPU에 연결됨 |
| 클라이언트 | Galaxy Tab S9 Ultra | 2960×1848, 120 Hz, AV1 하드웨어 디코드 |
| 링크 | Wi-Fi 6E AP 또는 USB-C 케이블 | USB-C 테더링 권장 |

### 소프트웨어

- Arch Linux, 커널 `linux` 또는 `linux-zen` 6.x 이상
- KDE Plasma 6 (Wayland) — 타 컴포지터 미검증
- [Sunshine](https://github.com/LizardByte/Sunshine) — AUR. `sunshine`(소스) 또는 `sunshine-bin`(프리빌트, 설치기 기본). `--sunshine-pkg` 로 변경.
- [Moonlight](https://moonlight-stream.org/) Android 클라이언트
- `intel-media-driver` — **하드웨어 인코딩에 필수.** 없으면 libva 초기화가 실패하고 Sunshine이 경고 없이 `libx264` 로 폴백한다.
- `edid-decode` — 선택. `scripts/verify.sh` 가 설치된 blob 검증에 사용

---

## 저장소 구조

```
install.sh            진입점 — 기본 dry-run, --apply 로 실행
lib/
  util.sh             로깅 + dry-run 실행기 + 문자열 헬퍼
  bootstrap.sh        플랫폼 감지 + 어댑터 로딩. 두 진입점이 공유
  ports.sh            자동 감지 + 포트 디스패처 함수
  core.sh             설치 단계 (EDID → 커널 → initramfs → Sunshine → udev)
adapters/
  bootloader/         systemd_boot.sh · grub.sh
  initramfs/          mkinitcpio.sh · dracut.sh
  pkg/                yay.sh · paru.sh · pacman.sh
edid/
  generate.py         CVT-RB2 EDID 1.4 생성기. 출력은 edid-decode 로 검증
  generated/          생성된 .bin blob (설치기 출력 경로)
udev/                 uinput 접근 규칙 (sunshine-uinput 그룹)
scripts/
  verify.sh           설치 후 읽기 전용 점검
  uninstall.sh        install.sh 역순 복원. 기본 dry-run
docs/
  troubleshooting.md  실측한 실패 양상과 대처
```

install.sh 는 부트로더·initramfs 도구·AUR 헬퍼를 자동 감지한다.
`--bootloader`, `--initramfs`, `--pkg` 플래그로 재정의 가능. `--help` 참조.

## 사용법

```bash
./install.sh                            # dry-run: 바꿀 내용을 전부 출력만
./install.sh --apply                    # 실제 적용
./install.sh --apply --profile tabs9_100hz

# 재부팅 후
./scripts/verify.sh                     # 읽기 전용 점검. 실패 시 exit 1
./scripts/uninstall.sh --apply          # 전부 되돌리기
```

가상 출력이 생긴 뒤 자동으로 되지 않는 것이 둘 있다:

```bash
# 1. Sunshine이 그 출력을 잡게 한다 — 안 하면 계속 내장 패널을 캡처한다.
#    인덱스는 아래 줄들의 순서(0부터):
journalctl --user -u app-dev.lizardbyte.app.Sunshine.service | grep 'Found monitor'
./install.sh --apply --sunshine-output 1

# 2. 내장 패널과 배율을 맞춘다 — 새 출력은 scale 1로 올라오는데,
#    14.6" 2960x1848 패널에서는 모든 것이 절반 크기로 그려진다.
kscreen-doctor output.HDMI-A-1.scale.2
```

남은 것: 부팅 경로 재부팅 검증, 터치/펜 리턴, Wi-Fi 6E 전송. 스트리밍과 페어링은 동작한다.

---

## 보안 주의사항

**이 스택은 여러 권한 상승 포인트를 요구하므로 공개·신뢰 불가 네트워크에서 그대로 쓰지 말 것.**

### 반드시 인지할 것

1. `setcap cap_sys_admin+p sunshine` — Sunshine 바이너리에 커널급 능력을 영구 부여. 업스트림 RCE 발생 시 즉시 루트급 영향. [Sunshine Security Advisories](https://github.com/LizardByte/Sunshine/security) 주시하고 최소 검증 버전 로컬 배포에 명시.
2. Moonlight 페어링은 **4자리 PIN 기반 TOFU**. 신뢰 가능한 LAN에서만 페어링.
3. Sunshine 기본 바인딩은 `0.0.0.0` + UPnP. 방화벽으로 USB 테더링 NIC 또는 WireGuard 인터페이스만 허용.
4. `uinput` 접근 개방 시 로그인 세션 내 모든 프로세스가 가상 입력 장치를 만들 수 있음 — 잠재적 키로거 / 자동화 표면. 이 저장소의 udev 규칙은 노드를 전용 `sunshine-uinput` 그룹에 넣지만, Sunshine 패키지가 자체 규칙에 `TAG+="uaccess"` 를 걸어 로그인 사용자에게 ACL을 주므로 그룹은 경계가 아니라 정돈 수준이다. `scripts/verify.sh` 가 패키지 규칙을 감지하면 이를 알려주며, 실제로 강제하는 방법은 [`docs/troubleshooting.md`](docs/troubleshooting.md) 참조.
5. 캡처는 `xdg-desktop-portal` 경유를 원칙으로. "sudo로 실행해서 우회"는 지양.

### 절대 커밋하지 말 것 (`.gitignore`로 차단됨)

- `~/.config/sunshine/sunshine_state.json` (장기 페어링 키)
- `~/.config/sunshine/credentials/` (클라이언트 인증서 / 사설 키)
- Samsung 실제 패널에서 덤프한 EDID 원본 (PnP ID / 상표 문자열 포함 가능)
- 개인 네트워크 식별자 (실제 IP, MAC, 호스트명, WireGuard 키)

### 취약점 보고

[`SECURITY.md`](./SECURITY.md) 참조.

---

## 라이선스

MIT — [`LICENSE`](./LICENSE) 참조.

---

## 상표 고지

"Galaxy", "Galaxy Tab", "Galaxy Book", "DeX", "Super Display"는 Samsung Electronics Co., Ltd.의 상표이다. 이 프로젝트는 Samsung과 무관한 독립 오픈소스 프로젝트이며, 해당 용어는 호환성 설명 목적으로만 사용된다.

"Moonlight", "Sunshine"은 각각 Moonlight Stream 및 LizardByte 프로젝트의 이름이다.

---

## 크레딧

- [Sunshine](https://github.com/LizardByte/Sunshine) — self-hosted game streaming host
- [Moonlight](https://github.com/moonlight-stream) — NVIDIA GameStream compatible client
- [edid-decode](https://git.linuxtv.org/edid-decode.git) — EDID 검증 레퍼런스
- [linuxhw/EDID](https://github.com/linuxhw/EDID) — 실사용 EDID 참조 (직접 포함 없음)
