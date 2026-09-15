# arch-galaxytab-submonitor

[English](README.md) &nbsp;|&nbsp; **[한국어](README.ko.md)**

---

갤럭시탭을 Arch Linux 노트북의 두 번째 모니터로 쓴다. 탭 네이티브 해상도 그대로.
호스트가 커스텀 EDID로 가짜 HDMI 모니터를 만들고 Sunshine이 USB 케이블로
스트리밍하면 탭의 Moonlight이 받아서 보여준다. Windows의 Super Display나
spacedesk가 하는 일을 웹 기반 도구 없이 리눅스에서 한다.

## 오랜만에 열었다면

설치는 한 번이다. 그 뒤로 쓰는 명령은 셋뿐이고 전부 `scripts/` 에 있다.

| 하고 싶은 것 | 명령 |
|---|---|
| 탭에 데스크톱 띄우기 | `./scripts/session.sh` |
| 끝내고 원래 화면으로 돌아오기 | `./scripts/session.sh --stop` |
| 왜 안 되는지 알아보기 | `./scripts/verify.sh` |

`session.sh` 는 가상 화면을 올리고 Sunshine을 띄운 다음 점검표를 찍는다. 끝줄이
`Ready — open Moonlight on the tablet` 이면 탭에서 Moonlight을 열어 호스트를
탭하면 되고, 아니면 뭐가 문제인지 그 줄에 나온다.

설치한 적이 없으면 [처음 설치](#처음-설치)부터. 뭔가 이상하면
[`docs/troubleshooting.md`](docs/troubleshooting.md) 에 지금까지 겪은 고장과
해결이 다 있다.

> **상태: alpha / 개인용.** Galaxy Book Ultra 3 (Intel + NVIDIA PRIME Optimus)
> 호스트와 Galaxy Tab S9 Ultra 조합 하나에서만 확인했다. 이 조합에서 되는 것:
> 콜드 부팅으로 올라오는 2960×1848 가상 출력, KDE 확장 배치, `hevc_vaapi`
> 캡처, USB-C 테더링 경유 Moonlight, mDNS 자동탐색. **아직 확인 안 된 것:**
> 펜·터치 리턴 인풋(연결은 돼 있으나 실제로 왕복시킨 적 없음), Wi-Fi 6E
> 전송(USB-C만 해봄).

---

## 사용법

### 쓸 때마다

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

한 줄 한 줄이 실제로 연결을 막았던 적이 있는 항목이다. 스크립트는 가상 출력을
켜서 실제 화면 오른쪽에 두고 배율을 맞추고 Sunshine이 안 떠 있으면 띄운 다음
나머지를 점검한다. 하나라도 어긋나면 exit 1.

```bash
./scripts/session.sh --stop       # Sunshine 내리고 가상 출력 파킹
./scripts/session.sh --no-start   # 아무것도 안 건드리고 보고만
```

다 쓰면 꼭 `--stop` 할 것. 가상 출력은 놀고 있어도 공짜가 아니다. 켜둔 채 두면
실제 모니터 위에 겹쳐 앉고 거기 떨어진 창은 최대화가 제대로 안 된다. (이유는
[동작 원리](#가상-출력을-왜-파킹하는가) 참조. 잊어버려도 다음 로그인 때 유닛이
대신 파킹해준다.)

### 처음 설치

여섯 단계. 재부팅이 한 번 끼고 탭을 손에 들어야 하는 단계가 있어서 한 줄로는
안 끝나지만 나중에 반복할 일은 없다.

#### 1. 설치

```bash
./install.sh            # dry-run: 바꿀 내용을 전부 출력만
./install.sh --apply    # 실제 적용
```

기본이 dry-run이니 한 번 읽어보고 적용한다. 부트로더·initramfs 도구·AUR 헬퍼는
자동 감지하고(`--bootloader`, `--initramfs`, `--pkg` 로 바꿈), 부트 엔트리와
initramfs 설정은 건드리기 전에 백업을 뜨며, 이미 적용된 항목은 다시 돌려도
건너뛴다. 전체 옵션은 `--help`.

#### 2. 재부팅하고 검증

커널 파라미터는 다음 부팅부터 먹는다.

```bash
./scripts/verify.sh
```

읽기 전용이고 문제가 있으면 exit 1. 정상이면 블롭과 CTA-861 블록, 커널
파라미터 둘 다 활성, 모든 initramfs 이미지에 블롭 포함, 커넥터가 2960×1848로
`connected`, Sunshine의 capability·서비스·캡처 대상까지 보고한다.

#### 3. Sunshine에 어느 화면을 잡을지 알려주기

이걸 빼먹으면 Sunshine이 기본 디스플레이인 내장 패널을 잡아서 확장이 아니라
복제가 된다. 인덱스는 아래 줄이 나오는 순서고 0부터 센다.

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

#### 4. Sunshine 로그인 만들기

첫 실행 때 한 번. <https://localhost:47990> 을 열고 자체서명 인증서 경고를
넘긴 뒤 사용자명과 비밀번호를 정한다. 이 계정과 페어링 키는
`~/.config/sunshine/` 에 들어가며 `.gitignore` 가 막고 `uninstall.sh` 도
건드리지 않는다.

#### 5. 탭 연결하고 방화벽 열기

탭에서 USB 테더링을 켜고 호스트가 주소를 받았는지 본다.

```bash
ip -br addr show label 'enp*u*'
```

Sunshine은 `0.0.0.0` 에 붙는다. 모든 네트워크에 노출하지 말고 이 인터페이스로
한정한다. 포트는 TCP 47984(페어링)·47989(제어)·48010(RTSP), UDP
47998–48000·48002(비디오·오디오·마이크). 47990은 닫아둔다. 웹 UI는 localhost
전용이다.

```
define TAB_IF = "enp0s13f0u*"
iifname $TAB_IF tcp dport { 47984, 47989, 48010 } accept
iifname $TAB_IF udp dport { 47998-48000, 48002 } accept
```

`iif` 말고 `iifname` + 와일드카드를 쓴다. 이 차이로 방화벽을 통째로 잃는다.
[보안 주의사항](#보안-주의사항) 참조.

#### 6. Moonlight 페어링

탭에 [Moonlight](https://moonlight-stream.org/) 을 깐다. 5번에서 나온 주소로
호스트를 추가하고(아래 mDNS를 하면 이 과정이 없어진다) 탭한 뒤 화면에 뜬
PIN을 Sunshine 웹 UI에 넣는다. 4자리 PIN 기반 TOFU라 케이블로 할 것.

Moonlight 설정에서 **HEVC** 를 고르고 비트레이트를 올린다. 기본값은 2960×1848에
한참 모자라고 USB 테더링은 50~100 Mbps를 감당한다. 호스트 GPU가 AV1 인코드를
못 하면 AV1은 고르지 말 것. Raptor Lake까지의 Intel iGPU는 AV1을 디코드만 하고
Sunshine은 말없이 소프트웨어로 떨어진다.

#### 선택: mDNS로 주소 걱정 없애기

USB 테더링에서는 탭이 DHCP 서버라 다시 꽂을 때마다 호스트 주소가 바뀌는데
Moonlight은 이름이 아니라 주소를 기억한다. Sunshine이 스스로를 광고하게 하면
이 문제가 사라진다.

Sunshine은 `libavahi-client` 로 `_nvstream._tcp` 를 광고하므로 `avahi-daemon`
이 필요하다. UDP 5353은 한 프로세스만 잡을 수 있고 보통 `systemd-resolved` 가
잡고 있으니 넘겨준다.

```bash
sudo pacman -S avahi nss-mdns
sudo mkdir -p /etc/systemd/resolved.conf.d
printf '[Resolve]\nMulticastDNS=no\n' \
  | sudo tee /etc/systemd/resolved.conf.d/10-no-mdns.conf
sudo systemctl restart systemd-resolved
sudo systemctl enable --now avahi-daemon
```

`nss-mdns` 가 호스트 쪽 `.local` 해석을 유지해준다. `/etc/nsswitch.conf` 의
`dns` 앞에 넣는다.

```
hosts: files mdns_minimal [NOTFOUND=return] myhostname dns
```

mDNS는 `224.0.0.251` / `ff02::fb` 로 가는 멀티캐스트라 사설 유니캐스트만
허용하는 규칙으로는 안 잡힌다. 포트를 양방향으로 연다.

```
iifname $TAB_IF udp dport 5353 accept          # input 체인
... 5353 ...                                   # 아웃바운드 UDP 포트 집합
```

Sunshine을 재시작하고 광고되는지 본다.

```bash
systemctl --user restart app-dev.lizardbyte.app.Sunshine.service
avahi-browse -atr | grep nvstream
```

### 필요할 때만 Sunshine 띄우기

설치기는 Sunshine을 그래픽 세션에 enable 하므로 로그인하면 트레이 아이콘이
늘 떠 있다. 그게 싫으면:

```bash
systemctl --user disable app-dev.lizardbyte.app.Sunshine.service   # 한 번만
./scripts/session.sh          # 탭 쓸 때
./scripts/session.sh --stop   # 다 썼을 때
```

`disable` 은 자동시작 심링크만 지운다. 아무것도 멈추지 않고 이후 수동 기동도
된다. 처음부터 enable을 건너뛰려면 `--no-enable` 로 설치하고 나중에 `--apply`
를 돌릴 때도 계속 붙인다. 안 붙이면 설치기가 자동시작을 조용히 되살린다.
그래서 `verify.sh` 는 "실행 중"과 "enabled"를 따로 보고한다.

알아둘 것 둘. 유닛에 `sunshine.service` 별칭이 있지만 그 심링크는 `enable` 이
만들기 때문에 한 번도 enable 하지 않았으면 짧은 이름이 안 먹는다. 정식 이름
`app-dev.lizardbyte.app.Sunshine.service` 를 쓴다. 그리고 `install.sh` 를
런처로 쓰지 않는다. 부트 엔트리를 편집하고 initramfs까지 재빌드하는
설치기다. 그 용도가 `session.sh` 다.

### 제거

```bash
./scripts/uninstall.sh                    # dry-run
./scripts/uninstall.sh --apply            # 전부 되돌리기
./scripts/uninstall.sh --apply --purge    # Sunshine 패키지까지
```

커널 파라미터·initramfs 항목·EDID 블롭·capability·그룹·udev 규칙·로그인 유닛을
되돌린다. Sunshine 설정과 페어링 키는 그대로 둔다.

---

## 동작 원리

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

1. **가상 디스플레이** — `drm.edid_firmware` + `video=HDMI-A-1:e` 로 i915
   드라이버가 아무것도 안 꽂힌 상태에서 2960×1848 @ 60 Hz 커넥터를 올린다.
2. **캡처 / 인코드** — Sunshine이 그 출력을 KMS/Wayland로 잡아 Intel iGPU의
   `hevc_vaapi` 로 인코드한다. NVENC는 여기서 안 된다. PRIME/Optimus 노트북은
   dGPU가 디스플레이를 하나도 안 물고 있어서 Sunshine의 NVENC 경로가
   `Couldn't find monitor [0]` 로 실패한다. Raptor Lake-P에는 AV1 인코더도
   없어서 HEVC로 간다.
3. **전송** — USB-C 테더링(검증됨) 또는 Wi-Fi 6E(미검증). `adb reverse` 는
   TCP만 포워딩해서 Moonlight의 UDP 미디어를 못 나르니 순수 테더링이 경로다.
4. **입력 리턴** — Moonlight의 터치·펜 이벤트를 `uinput` 가상 장치로 호스트에
   넣는다. 연결은 돼 있고 아직 써보지 않았다.

### 왜 120 Hz가 아니라 60 Hz인가

EDID의 detailed timing descriptor는 픽셀클럭을 16비트 × 10 kHz로 저장하므로
**655.35 MHz** 를 넘길 수 없다. 2960×1848 @ 120 Hz는 CVT-RB2 블랭킹으로
713.55 MHz, 블랭킹을 0으로 둬도 656.41 MHz다. EDID로는 아예 표현이 안 되고
타이밍을 어떻게 만져도 우회할 수 없다.

그래서 `edid/generate.py` 는 탭 네이티브 해상도에서 이 프로파일을 제공하고
`--profile` 로 고른다.

| 프로파일 | 픽셀클럭 | 비고 |
|----------|----------|------|
| `tabs9_60hz` (기본) | 346.74 MHz | 여유 큼 |
| `tabs9_85hz` | 497.16 MHz | 타깃 호스트에서 동작 실측 |
| `tabs9_95hz` | 558.25 MHz | 타깃 호스트에서 동작 실측 |
| `tabs9_100hz` | 589.15 MHz | 네이티브 해상도에서 인코딩 가능한 최대치 |

생성기는 인코딩 불가능한 모드를 조용히 잘라내지 않고 거부한다. 어느 프로파일이
실제로 도는지는 플랫폼마다 다르다. 디스플레이 PLL이 모든 픽셀클럭을 합성하지
못하는데 그 공백은 어디에도 안 적혀 있다. 타깃 호스트에서는 88·90 Hz가
프루닝되고 85·95·100 Hz는 통과한다. 모드가 안 뜬다고 블롭이 틀린 건 아니다.
판정은 커넥터가 한다: `cat /sys/class/drm/card*-HDMI-A-1/modes`.

### EDID에는 CTA-861 확장이 필요하다

타이밍이 아무리 정확해도 베이스 블록만으로는 안 된다. HDMI IEEE OUI
`00-0C-03` 을 담은 CTA-861 확장이 없으면 커널이 싱크를 DVI로 판정하고
**165 MHz** 넘는 건 전부 프루닝한다. 실측으로 148 MHz는 통과, 168 MHz는
프루닝. 이 프로젝트가 노리는 모드는 전부 사라진다. 340 MHz를 넘으면 HDMI
Forum VSDB(`C4-5D-D8`)로 문자율까지 고지해야 한다.

`edid/generate.py` 는 둘 다 만든다. 정상 블롭이 128이 아니라 256바이트인
이유이고 `verify.sh` 가 둘의 존재를 검사한다.

### 가상 출력을 왜 파킹하는가

`video=<connector>:e` 는 커넥터를 부팅 내내 강제로 켠다. 탭이 핫플러그를
알릴 방법이 없으니 이게 목적이다. 대신 KWin은 뒤에 아무것도 없는 2960×1848
화면이 늘 연결돼 있다고 보고 0,0에 둔다. 이미 실제 모니터가 있는 자리다.

두 출력이 한 사각형을 나눠 갖는 건 그리기 문제가 아니라 기하 문제다. KWin은
창마다 출력을 하나씩 배정하고 *그 출력의* 사각형 안으로 최대화한다. 가상
출력에 떨어진 창은 그 면적만 채운다. 5120×2880 패널 scale 2.5에서 재보니
"최대화된" 창이 2048×1152 데스크톱 안에서 1480×924로 나왔고 KWin 로그에는
아무것도 안 남았다.

그래서 가상 출력은 세션 동안만 켜고 항상 실제 화면 오른쪽 끝 너머에 둔다.
그 로직만 따로 뗀 게 `scripts/virtual-output.sh` 다.

```bash
./scripts/virtual-output.sh on       # 켜서 다른 화면과 안 겹치게
./scripts/virtual-output.sh status   # 실제 화면과 겹치면 exit 1
./scripts/virtual-output.sh off      # 파킹
```

`on` 은 출력이 scale 1로 올라왔으면 2로 바꾼다. 14.6" 2960×1848 패널에서
scale 1은 노트북 화면의 절반 크기로 그려지고 scale 2면 논리 1480×924가 되어
흔한 노트북 데스크톱과 비슷해진다. 직접 정한 배율은 유지되고 `on --scale 2.5`
로 기본값을 바꾼다.

### 로그인 유닛은 뭘 하는가

`--stop` 은 정상 종료를 맡는다. 탭에서 시스템을 끄거나 크래시가 나거나
그냥 잊어버리는 경우는 못 맡는다. KWin이 마지막에 저장한 배치를 복원하니
가상 화면이 켜진 채 겹쳐서 돌아오고 창 최대화가 안 되는 게
제일 먼저 눈에 띈다.

그래서 설치기가 `tabdisp-virtual-output.service` 유저 유닛도 enable 한다.
로그인마다 한 번 출력을 파킹한다. 세션이 어떻게 끝났든 다음 세션은 실제
화면만으로 시작한다.

```bash
systemctl --user status tabdisp-virtual-output.service
```

`ExecStart` 가 이 체크아웃을 가리킨다. 저장소를 옮기거나 지우면 깨지니 새
위치에서 `install.sh --apply` 를 다시 돌린다. `--no-output-reset` 은 유닛을
깔되 enable 하지 않는다.

---

## 요구 사항

| 구성 | 모델 | 비고 |
|------|------|------|
| 호스트 | Galaxy Book Ultra 3 | Intel Core i7 + RTX 4050 Max-Q. HDMI 포트가 dGPU가 아닌 Intel iGPU에 연결됨 |
| 클라이언트 | Galaxy Tab S9 Ultra | 2960×1848, 120 Hz, AV1 하드웨어 디코드 |
| 링크 | USB-C 케이블(검증됨) 또는 Wi-Fi 6E(미검증) | |

- Arch Linux, 커널 `linux` 또는 `linux-zen` 6.x 이상
- KDE Plasma 6 (Wayland). 다른 컴포지터는 미검증
- AUR의 [Sunshine](https://github.com/LizardByte/Sunshine): `sunshine`(소스) 또는 `sunshine-bin`(프리빌트, 기본). `--sunshine-pkg` 로 선택
- 탭에 [Moonlight](https://moonlight-stream.org/)
- `intel-media-driver` — **하드웨어 인코딩에 필수.** 없으면 libva 초기화가 안 되고 Sunshine이 경고 없이 `libx264` 로 떨어진다
- `edid-decode` — 선택. `verify.sh` 가 설치된 블롭 검증에 쓴다

---

## 저장소 구조

```
install.sh            진입점 — 기본 dry-run, --apply 로 적용
lib/
  util.sh             로깅, dry-run 실행기, 문자열 헬퍼
  bootstrap.sh        플랫폼 감지 + 어댑터 로딩. 두 진입점이 공유
  ports.sh            자동 감지 + 포트 디스패처
  core.sh             설치 단계 (EDID → 커널 → initramfs → Sunshine → 세션 유닛 → udev)
adapters/
  bootloader/         systemd_boot.sh · grub.sh
  initramfs/          mkinitcpio.sh · dracut.sh
  pkg/                yay.sh · paru.sh · pacman.sh
edid/
  generate.py         CVT-RB2 EDID 1.4 생성기. 출력은 edid-decode로 검증
  generated/          생성된 .bin 블롭 (설치기 출력 경로)
udev/                 uinput 접근 규칙 (sunshine-uinput 그룹)
systemd/
  tabdisp-virtual-output.service.in   로그인 시 가상 출력을 파킹하는 유닛
scripts/
  session.sh          일상 사용: 출력 언파킹, Sunshine 기동, 준비상태 보고
  virtual-output.sh   가상 출력을 실제 화면과 안 겹치게 켜거나 파킹
  verify.sh           설치 후 읽기 전용 점검
  uninstall.sh        install.sh 역순 복원. 기본 dry-run
docs/
  troubleshooting.md  실측한 고장 양상과 해결
```

---

## 보안 주의사항

**이 스택은 권한 상승 지점이 여럿이다. 신뢰할 수 없는 네트워크나 공개망에서 그대로 쓰지 말 것.**

1. `setcap cap_sys_admin+p sunshine` 은 Sunshine 바이너리에 커널급 능력을 영구 부여한다. 업스트림 RCE가 나면 즉시 루트급이다. [Sunshine Security Advisories](https://github.com/LizardByte/Sunshine/security) 를 지켜보고 최소 검증 버전을 로컬에 고정할 것.
2. Moonlight 페어링은 **4자리 PIN 기반 TOFU** 다. 믿을 만한 링크에서만.
3. Sunshine은 기본으로 `0.0.0.0` + UPnP다. USB 테더링 NIC이나 WireGuard 인터페이스로 방화벽을 한정한다. nftables 규칙을 그 NIC으로 묶을 때는 `iif` 가 아니라 **`iifname` + 와일드카드**. `iif` 는 로드 시점에 이름을 해석하므로 부팅 때 USB NIC이 없거나 다른 포트로 잡히면 룰셋 전체가 안 올라와 방화벽이 통째로 없어진다. [`docs/troubleshooting.md`](docs/troubleshooting.md) 참조.
4. `uinput` 을 열면 로그인 세션의 모든 프로세스가 가상 입력 장치를 만들 수 있다. 잠재적 키로거·자동화 표면이다. 이 저장소의 udev 규칙은 노드를 전용 `sunshine-uinput` 그룹에 넣지만 Sunshine 패키지가 자체 규칙에 `TAG+="uaccess"` 를 걸어 로그인 사용자에게 ACL을 준다. 그룹은 경계가 아니라 정돈이다. `verify.sh` 가 패키지 규칙을 감지하면 알려주고 실제로 강제하는 법은 [`docs/troubleshooting.md`](docs/troubleshooting.md) 에 있다.
5. 캡처는 `xdg-desktop-portal` 을 거친다. "sudo로 우회"는 하지 말 것.

**절대 커밋하지 말 것** (`.gitignore` 가 막는다): `~/.config/sunshine/sunshine_state.json` 과 `~/.config/sunshine/credentials/`(페어링 키·클라이언트 인증서), 실제 Samsung 패널에서 덤프한 EDID(PnP ID·상표 문자열이 들어 있을 수 있음), 개인 네트워크 식별자(실제 IP·MAC·호스트명·WireGuard 키).

취약점 보고: [`SECURITY.md`](./SECURITY.md).

---

## 라이선스

MIT — [`LICENSE`](./LICENSE).

## 상표 고지

"Galaxy", "Galaxy Tab", "Galaxy Book", "DeX", "Super Display"는 Samsung Electronics Co., Ltd.의 상표다. 이 프로젝트는 Samsung과 무관한 독립 오픈소스이며 해당 용어는 호환성 설명에만 쓴다. "Moonlight"과 "Sunshine"은 각각 Moonlight Stream과 LizardByte 프로젝트의 이름이다.

## 크레딧

- [Sunshine](https://github.com/LizardByte/Sunshine) — self-hosted game streaming host
- [Moonlight](https://github.com/moonlight-stream) — NVIDIA GameStream compatible client
- [edid-decode](https://git.linuxtv.org/edid-decode.git) — EDID 검증 레퍼런스
- [linuxhw/EDID](https://github.com/linuxhw/EDID) — 실사용 EDID 참조 (직접 포함 없음)
