# Touch_1pUPS_335_bat vs Touch_1pUPS_335_bypass

`Touch_1pUPS_335_bypass`는 `Touch_1pUPS_335_bat`와 같은 1상 UPS 3.35인치 터치 디스플레이를 기반으로 한다.  
메뉴·키패드·계측·히스토리·제어 ON/OFF 흐름은 거의 같고, **메인 다이어그램의 전단(입력·바이패스) 전원선**을 분리해 그린 것이 핵심 차이이다.

| 항목 | `Touch_1pUPS_335_bat` | `Touch_1pUPS_335_bypass` |
|------|------------------------|--------------------------|
| 성격 | 기존(배터리 포함) 표준 화면 | 바이패스 고장(`bypass_failure`)을 독립적으로 표시 |
| 전단 전원선 | `hex_data[12]` D07 하나로 입력+바이패스를 같이 켬/끔 | 입력과 바이패스를 따로 그림 |
| 후단(Converter~출력) | `hex_data[10]` | `hex_data[10]` (동일) |
| 규모 | 약 3948행 | 약 4168행 (약 +220행) |

---

## 한 줄 정리

- **`_bat`**: “정전 여부”(`hex_data[12]` D07) 하나로 전단(입력선+바이패스선)을 묶어서 그린다.
- **`_bypass`**: 바이패스 고장(`hex_data[11]` D14)을 별도 신호로 받아 **입력선과 바이패스선을 따로** 표시한다.

```
입력 AC ──┬── Converter ── DC ── Inverter ── Transfer ── 출력
          └── Bypass ──────────────────────────────────────┘

후단(Converter~출력):  둘 다 hex_data[10]
전단 입력선:           _bat    = hex_data[12] D07
                       _bypass = hex_data[12] D07 (faultStatus)
전단 바이패스선:       _bat    = 입력과 묶여서 같이 움직임
                       _bypass = hex_data[11] D14 (bypass_failure)로 독립
```

---

## 1. 메인 화면: 입력/바이패스 전원선 (가장 큰 차이)

### `_bat` — 한 비트로 묶음

`hex_data[12] >> 7` (utility line failure)만 보고, **입력선과 바이패스선을 같이** 그린다.

- 정전 아님 (D07 = 0) → 입력 1·3 + 바이패스 1·2 **전부 GREEN**
- 정전 (D07 = 1) → **전부 LIGHT_GRAY**

바이패스만 고장이거나, 입력만 살아 있는 상태를 **따로 표시할 수 없다.**

### `_bypass` — 두 비트를 분리

`drawMainPowerLine()`을 새로 두고 아래처럼 나눈다.

| 구간 | 데이터 | 의미 |
|------|--------|------|
| 바이패스 1·2 | `hex_data[11]` D14 → `hwStatus.bypass_failure` | 바이패스 고장 |
| 입력 1·3 | `hex_data[12]` D07 → `faultStatus.utility_line_failure` | Utility 정전 |
| 입력 중심 | 위 둘 **모두** 1일 때만 회색 | 입력·바이패스 동시 이상 |

**입력은 살아 있고 바이패스만 죽은** 상태를 화면에 표현할 수 있다.

관련 위치 (`Touch_1pUPS_335_bypass.ino`):

- `drawMainPowerLine()` — 약 2997~3037행
- `main_next`에서 호출 — 약 3341행

---

## 2. Transfer STOP일 때 출력 쪽 바이패스 선

`hex_data[10]` D03 = 0 (Transfer STOP, 바이패스 경로)일 때:

| 버전 | 동작 |
|------|------|
| `_bat` | bypass 3·4, out center, out 2를 **항상 GREEN** |
| `_bypass` | `hwStatus.bypass_failure == 1`이면 그 구간을 **LIGHT_GRAY** |

바이패스가 고장인데도 출력 바이패스 선이 녹색으로 남는 문제를 막기 위한 수정이다.  
위치: `main_next` 약 3453행.

---

## 3. `hex_data[11]` D14를 살림 (마스크 변경)

수신 후 마스크가 다르다.

```cpp
// _bat
hex_data[11] = hex_data[11] & 0x3FFF;   // D14, D15 삭제 → Bypass Failure 버려짐

// _bypass
hex_data[11] = hex_data[11] & 0x7FFF;   // D15만 삭제 → D14 Bypass Failure 유지
hwStatus.value = hex_data[11];
faultStatus.value = hex_data[12];
```

`_bat`는 그래픽에 쓰려고 해도 **D14가 수신 단계에서 지워진다.**  
`_bypass`는 이 비트를 남기고 `hwStatus`에 넣는다.

### 알람 비트 카운트

| 버전 | 마스크 | 결과 |
|------|--------|------|
| `_bat` | `alarm_data2 & 0x3FFF` | Bypass Failure는 알람 개수에 안 들어감 |
| `_bypass` | `alarm_data2 & 0x7FFF` | Bypass Failure를 알람으로 셀 수 있음 |

참고: `eeprom_set()` 부저 조건은 둘 다 `0x3FFF`라서, 부저 쪽은 아직 `_bat`와 같다.

---

## 4. 화면 다시 그리기 조건

| 항목 | `_bat` | `_bypass` |
|------|--------|-----------|
| 스냅샷 | `hex_data[10]`, `[12]`만 | `[10]`, `[11]`, `[12]` |
| 의미 | 바이패스 고장만 바뀌어도 메인 화면이 안 바뀜 | `[11]` 변화(바이패스 고장 등)에도 `main_next`로 재그림 |

```cpp
// _bypass main_next 종료 시
main_system_check1 = hex_data[10];
main_system_check3 = hex_data[11];
main_system_check2 = hex_data[12];

// _bypass main_i
if ((main_system_check1 != hex_data[10]) || (main_system_check2 != hex_data[12])
    || (main_system_check3 != hex_data[11]))
    page_num = main_next;
```

---

## 5. `_bypass`에만 있는 코드 정리

동작과 직접 관련 없는 정리·문서 포함:

- 색상 매크로 (`GREEN`, `LIGHT_GRAY`, `BLUEGREEN` 등) — `_bat`는 RGB를 직접 씀
- 비트필드 구조체: `ups_converter_status`, `ups_hw_status`, `ups_operation_fault_status`
- `hwStatus` / `faultStatus`에 수신값 대입
- `drawMainPowerLine()`
- `README.md` (hex_data[10]/[11]/[12] 화면 제어 설명)

메뉴·키패드·계측·히스토리·제어 ON/OFF 흐름은 거의 동일하다.

---

## 관련 소스 위치

| 내용 | `_bat` | `_bypass` |
|------|--------|-----------|
| 수신 마스크 | `serial_rx()` 약 1444행 (`0x3FFF`) | `serial_rx()` 약 1586행 (`0x7FFF`) |
| 전단 전원선 | `main_next` 약 3150~3171행 (인라인) | `drawMainPowerLine()` 약 2997행 |
| Transfer/출력 바이패스 | `main_next` 약 3243~3274행 | `main_next` 약 3447~3490행 |
| 화면 갱신 비교 | `main_i` 약 3385행 (10, 12만) | `main_i` 약 3602행 (10, 11, 12) |
| 구조체 정의 | 없음 | 약 263~365행 |

---

## hex_data 역할 (공통 + bypass 추가분)

| 번지 | 공통 | `_bypass`에서 추가된 화면 역할 |
|------|------|--------------------------------|
| `hex_data[10]` | Converter·DC/DC·Inverter·Transfer RUN/STOP, 후단 파워라인 | 동일 |
| `hex_data[11]` | 알람·부저·EEPROM (`eeprom_set`, `alarm_set`) | **D14 Bypass Failure → 전단 바이패스선**, 화면 갱신 트리거 |
| `hex_data[12]` | 알람·부저, `_bat`에서는 전단 입력+바이패스 묶음 | 전단 **입력선만** (`utility_line_failure`) |
