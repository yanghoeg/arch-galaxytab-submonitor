# arch-galaxytab-submonitor

[English](README.md) &nbsp;|&nbsp; **[한국어](README.ko.md)**

---

Galaxy Tab을 Arch Linux의 보조 디스플레이로 사용하기 위한 오픈 스택. 커스텀 EDID 가상 출력 + 저지연 게임스트리밍 기반 전송 + 터치/펜 리턴 인풋을 묶어, Windows의 Super Display / spacedesk에 해당하는 워크플로를 리눅스에서 재현한다.

Galaxy Tab을 리눅스에서 네이티브 해상도 보조 모니터로 쓸 수 있는 1급 솔루션이 없다는 사실 — 웹 기반 조악한 도구만 존재 — 에서 출발한 프로젝트다.

> **Status: alpha / personal.** Galaxy Book Ultra 3 (Intel + NVIDIA PRIME Optimus) 호스트와 Galaxy Tab S9 Ultra 클라이언트 조합에서만 검증. 다른 하드웨어 조합은 미검증.
>
> **실기에서 확인된 것:** debugfs 도움 없이 부팅만으로 올라오는 2960×1848 가상 출력, KDE 확장 배치, 해당 출력의 `hevc_vaapi` 캡처, USB-C 테더링 경유 Moonlight 스트리밍, Avahi 경유 mDNS 자동탐색.
>
> **아직 미검증:**
> - **펜 / 터치 리턴 인풋.** `uinput` 경로는 연결돼 있고 `/dev/uinput` 쓰기도 열려 있지만, 실제 입력을 왕복시켜 본 적이 없다 — Sunshine 가상 입력 장치가 `/proc/bus/input/devices` 에 나타난 적이 없다.
> - **Wi-Fi 6E 전송.** USB-C 테더링만 검증했고, 방화벽 규칙도 그 인터페이스에만 열려 있다.

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

### 1. 설치

설치기는 기본이 dry-run이라 바꿀 내용을 전부 출력만 한다. 한 번 그냥 돌려서 읽어보고 적용하는 것을 권한다.

```bash
./install.sh                              # dry-run
./install.sh --apply                      # 적용
./install.sh --apply --profile tabs9_100hz  # 다른 주사율
```

부트로더·initramfs 도구·AUR 헬퍼는 자동 감지하며 `--bootloader`, `--initramfs`, `--pkg` 로 재정의한다. 전체 옵션은 `--help` 참조.

부트 엔트리와 initramfs 설정은 편집 직전 타임스탬프 백업을 뜬다. 이미 적용된 항목에 `--apply` 를 다시 돌리면 no-op이다.

### 2. 재부팅 후 검증

커널 파라미터는 다음 부팅부터 적용되고, EDID는 그 이른 시점에 읽혀야 한다 — initramfs에 넣는 이유가 이것이다.

```bash
./scripts/verify.sh
```

읽기 전용이며 실패 시 exit 1. 정상이면 블롭과 CTA-861 블록, 커널 파라미터 두 개 활성, 모든 initramfs 이미지에 블롭 포함, 커넥터가 프로파일 해상도로 `connected`, Sunshine의 capability·서비스·캡처 대상을 보고한다.

### 3. Sunshine 이 가상 출력을 잡게 하기

이걸 안 하면 Sunshine이 기본 디스플레이(보통 내장 패널)를 캡처해서 확장이 아니라 복제가 된다. 인덱스는 아래 줄들이 나오는 순서이며 0부터 센다.

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

### 4. 배율 맞추기

새 출력은 scale 1로 올라온다. 14.6" 2960×1848 패널에서는 모든 것이 노트북 화면 대비 절반 크기로 그려진다 — 스크린샷으로는 읽히지만 실사용은 불가능하다.

```bash
kscreen-doctor output.HDMI-A-1.scale.2
```

scale 2면 논리 해상도가 1480×924가 되어, 흔한 1440×900 노트북 데스크톱과 충분히 가까워 UI 요소가 양쪽에서 같은 물리 크기로 보인다.

### 5. Sunshine 웹 UI 계정 생성

최초 실행 시 한 번만. <https://localhost:47990> 을 열고 자체서명 인증서 경고를 넘긴 뒤 사용자명·비밀번호를 만든다. 이 자격증명과 페어링 키는 `~/.config/sunshine/` 에 저장되며, `.gitignore` 가 차단하고 `scripts/uninstall.sh` 도 의도적으로 건드리지 않는다.

### 6. 탭 연결과 방화벽

검증된 전송 경로는 USB-C 테더링이다. 탭에서 테더링을 켠 뒤 호스트가 주소를 받았는지 확인한다.

```bash
ip -br addr show label 'enp*u*'
```

Sunshine은 `0.0.0.0` 에 바인딩하므로 모든 네트워크에 노출하지 말고 해당 인터페이스로 한정한다. 포트는 TCP 47984(페어링)·47989(제어)·48010(RTSP), UDP 47998–48000·48002(비디오·오디오·마이크). 47990은 닫아둔다 — 웹 UI는 localhost 전용이다.

```
define TAB_IF = "enp0s13f0u*"
iifname $TAB_IF tcp dport { 47984, 47989, 48010 } accept
iifname $TAB_IF udp dport { 47998-48000, 48002 } accept
```

`iif` 가 아니라 **`iifname` + 와일드카드**를 쓸 것. 이 차이로 방화벽을 통째로 잃을 수 있다 — 아래 보안 주의사항 참조.

### 7. 선택: mDNS 자동탐색으로 주소 문제 없애기

USB 테더링에서는 탭이 DHCP 서버라 재연결마다 호스트 주소가 바뀌는데, Moonlight은 이름이 아니라 주소를 저장한다. Sunshine이 스스로를 광고하게 하면 이 문제가 사라진다.

Sunshine은 `libavahi-client` 로 `_nvstream._tcp` 를 광고하므로 `avahi-daemon` 이 필요하다. UDP 5353은 한 프로세스만 점유할 수 있고 systemd 시스템에서는 보통 `systemd-resolved` 가 잡고 있으니 넘겨준다.

```bash
sudo pacman -S avahi nss-mdns
sudo mkdir -p /etc/systemd/resolved.conf.d
printf '[Resolve]\nMulticastDNS=no\n' \
  | sudo tee /etc/systemd/resolved.conf.d/10-no-mdns.conf
sudo systemctl restart systemd-resolved
sudo systemctl enable --now avahi-daemon
```

`nss-mdns` 는 resolved가 빠진 뒤에도 호스트 쪽 `.local` 해석을 유지해 준다. `/etc/nsswitch.conf` 의 `dns` 앞에 넣는다.

```
hosts: files mdns_minimal [NOTFOUND=return] myhostname dns
```

그다음 방화벽에 mDNS를 열어준다. `224.0.0.251` / `ff02::fb` 로 가는 멀티캐스트라 사설 유니캐스트 대역만 허용하는 규칙으로는 응답이 나가지 못한다 — 아웃바운드 포트를 명시적으로 허용해야 한다.

```
iifname $TAB_IF udp dport 5353 accept          # input 체인
... 5353 ...                                   # 아웃바운드 UDP 포트 집합에 추가
```

Sunshine을 재시작하고 실제로 광고되는지 확인한다.

```bash
systemctl --user restart app-dev.lizardbyte.app.Sunshine.service
avahi-browse -atr | grep nvstream
```

호스트명이 `_nvstream._tcp` 와 함께 테더링 주소·포트 47989로 보이면 성공이다. 이후 Moonlight이 알아서 호스트를 찾는다.

### 8. Moonlight 페어링

탭에 [Moonlight](https://moonlight-stream.org/) 을 설치하고 실행한다. 7번을 했다면 호스트가 저절로 뜨고, 안 했다면 호스트 주소를 수동으로 추가한다. 탭한 뒤 화면에 뜬 PIN을 Sunshine 웹 UI에 입력한다. 페어링은 4자리 PIN 기반 TOFU이므로 신뢰할 수 있는 링크에서 할 것 — USB 테더링이면 그냥 케이블이다.

Moonlight 설정에서 **HEVC** 를 고르고 비트레이트를 올린다. 기본값은 2960×1848에 턱없이 낮고, USB 테더링은 50~100 Mbps를 감당한다. 호스트 GPU가 AV1 인코드를 못 하면 AV1은 고르지 말 것 — Raptor Lake까지의 Intel iGPU는 AV1을 디코드만 하고 인코드는 못 해서 Sunshine이 소프트웨어로 폴백한다.

### 제거

```bash
./scripts/uninstall.sh                    # dry-run
./scripts/uninstall.sh --apply            # 전부 되돌리기
./scripts/uninstall.sh --apply --purge    # Sunshine 패키지까지 제거
```

커널 파라미터·initramfs 항목·EDID 블롭·capability·그룹·udev 규칙을 되돌린다. Sunshine 설정과 페어링 키는 건드리지 않는다.

---

## 보안 주의사항

**이 스택은 여러 권한 상승 포인트를 요구하므로 공개·신뢰 불가 네트워크에서 그대로 쓰지 말 것.**

### 반드시 인지할 것

1. `setcap cap_sys_admin+p sunshine` — Sunshine 바이너리에 커널급 능력을 영구 부여. 업스트림 RCE 발생 시 즉시 루트급 영향. [Sunshine Security Advisories](https://github.com/LizardByte/Sunshine/security) 주시하고 최소 검증 버전 로컬 배포에 명시.
2. Moonlight 페어링은 **4자리 PIN 기반 TOFU**. 신뢰 가능한 LAN에서만 페어링.
3. Sunshine 기본 바인딩은 `0.0.0.0` + UPnP. 방화벽으로 USB 테더링 NIC 또는 WireGuard 인터페이스만 허용. nftables 규칙을 그 NIC으로 한정할 때는 `iif` 말고 **`iifname` + 와일드카드**를 쓸 것 — `iif` 는 로드 시점에 이름을 해석하므로, 부팅 시 USB NIC이 없거나 다른 포트로 잡히면 룰셋 전체가 로드에 실패해 방화벽이 통째로 사라진다. [`docs/troubleshooting.md`](docs/troubleshooting.md) 참조.
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
