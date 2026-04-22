# arch-galaxytab-submonitor

[English](README.md) &nbsp;|&nbsp; **[한국어](README.ko.md)**

---

Galaxy Tab을 Arch Linux의 보조 디스플레이로 사용하기 위한 오픈 스택. 커스텀 EDID 가상 출력 + 저지연 게임스트리밍 기반 전송 + 터치/펜 리턴 인풋을 묶어, Windows의 Super Display / spacedesk에 해당하는 워크플로를 리눅스에서 재현한다.

Galaxy Tab을 리눅스에서 네이티브 해상도 보조 모니터로 쓸 수 있는 1급 솔루션이 없다는 사실 — 웹 기반 조악한 도구만 존재 — 에서 출발한 프로젝트다.

> **Status: alpha / personal.** Galaxy Book Ultra 3 (Intel + NVIDIA PRIME Optimus) 호스트와 Galaxy Tab S9 Ultra 클라이언트 조합에서만 검증 예정. 다른 하드웨어 조합은 미검증.

---

## 아키텍처

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

1. **가상 디스플레이** — `drm.edid_firmware` + `video=HDMI-A-1:e` 로 i915 드라이버에 2960×1848 @ 120 Hz 합성 커넥터를 활성화.
2. **캡처 / 인코드** — Sunshine이 PipeWire로 해당 출력만 스크랩, NVENC AV1 또는 HEVC 초저지연 프리셋으로 인코드.
3. **전송** — Wi-Fi 6E, 또는 USB-C 테더링 + `adb reverse` 조합 (지터 관점에서 권장).
4. **입력 리턴** — Moonlight의 네이티브 터치 / S펜 이벤트를 `uinput` 가상 장치로 호스트에 주입.

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
- [Sunshine](https://github.com/LizardByte/Sunshine) (AUR)
- [Moonlight](https://moonlight-stream.org/) Android 클라이언트

---

## 저장소 구조 (예정)

```
edid/        2960×1848 @ 120 Hz EDID 생성 스크립트 (CVT-RB2)
kernel/      kernel cmdline / mkinitcpio 스니펫
sunshine/    systemd 유닛 + 설정 템플릿 (시크릿 제외)
udev/        uinput 접근 규칙
scripts/     install / verify / uninstall (dry-run 기본)
docs/        latency tuning, security model, troubleshooting
```

현재 스켈레톤 단계. 아직 실사용 가능한 install 경로 없음.

---

## 보안 주의사항

**이 스택은 여러 권한 상승 포인트를 요구하므로 공개·신뢰 불가 네트워크에서 그대로 쓰지 말 것.**

### 반드시 인지할 것

1. `setcap cap_sys_admin+p sunshine` — Sunshine 바이너리에 커널급 능력을 영구 부여. 업스트림 RCE 발생 시 즉시 루트급 영향. [Sunshine Security Advisories](https://github.com/LizardByte/Sunshine/security) 주시하고 최소 검증 버전 로컬 배포에 명시.
2. Moonlight 페어링은 **4자리 PIN 기반 TOFU**. 신뢰 가능한 LAN에서만 페어링.
3. Sunshine 기본 바인딩은 `0.0.0.0` + UPnP. 방화벽으로 USB 테더링 NIC 또는 WireGuard 인터페이스만 허용.
4. `uinput` 접근 개방 시 로그인 세션 내 모든 프로세스가 가상 입력 장치를 만들 수 있음 — 잠재적 키로거 / 자동화 표면. udev 규칙을 전용 그룹(`sunshine-uinput`)으로 제한할 것.
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
