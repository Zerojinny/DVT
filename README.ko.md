# DVT — Deploy Via Torrent

[English](README.md) | **한국어**

DVT는 하나의 Windows 이미지를 로컬 네트워크로 실습실 전체 PC에 한 번에 복원하는
도구입니다. 각 PC는 작은 WinPE로 부팅해 백업 이미지를 BitTorrent(aria2)로 내려받고
wimlib로 적용합니다. 조각을 이미 받은 PC가 다른 PC에게도 올려 주기 때문에, PC 수가
늘어나도 파일 서버 한 대로 배포할 때처럼 느려지지 않습니다.

모든 스크립트는 일반 Windows 배치 파일입니다. WinPE 안에서 실행되는 스크립트는
WinPE 기본 도구(WMIC, WMI, PowerShell, findstr 미사용)와 aria2c, wimlib-imagex,
NirCmd만 사용합니다.

> [!WARNING]
> DVT는 실행되는 모든 PC의 **디스크 하나를 통째로 지웁니다**. 먼저 여분의 PC에서
> 테스트하세요.

📖 **전체 매뉴얼:** [doc/manual.ko.md](doc/manual.ko.md) ·
[PDF](doc/manual.ko.pdf) · [English](doc/manual.md) ·
[English PDF](doc/manual.pdf)

## 동작 방식

```
빌드 PC       01_make_pe.bat  →  _output\boot\ (boot.wim + 클라이언트 스크립트)
클라이언트    C:\temp\boot\make_boot.bat  →  1회용 부팅 항목으로 WinPE 재시작
WinPE         디스크, 네트워크, 게이트웨이, 시더, 디스크 공간 확인
              → 디스크 삭제 → 토렌트 다운로드 → 이미지 적용
              → 복원된 Windows로 재부팅
```

Windows가 동작하지 않는 PC는 `02_make_media.bat`으로 만든 **USB / CD**로 부팅할 수
있습니다. 이때는 작업자가 PC마다 IP 주소와 디스크를 입력합니다.

## 주요 특징

- **토렌트 배포** — 다운로드가 끝나는 즉시 복원을 시작하고, 이미지를 적용하는
  동안에도 계속 시딩합니다.
- **모든 점검을 통과하기 전에는 아무것도 지우지 않음** — 대상 디스크, 네트워크,
  게이트웨이, 시더로부터의 실제 다운로드, 디스크 공간. 실패하면 기존 Windows로
  돌아갑니다.
- **정확한 디스크 판별** — Windows에서 읽은 디스크 ID(BitLocker에서도 동작), 다음으로
  표식 파일로 찾으며, 조금이라도 애매하면 멈춥니다.
- **UEFI와 BIOS**, **고정 IP(DNS 포함) 또는 DHCP**, 실행 중인 PC의 네트워크
  드라이버 사용, 100 Mbps / 1 Gbps별 aria2 프로필.
- **테스트 이미지** — 디스크를 건드리지 않고 모든 PC의 네트워크와 시더 연결을 점검해
  FTP로 보고서를 올립니다.
- **복원 기록** — `HKLM\SOFTWARE\DVT`(버전, 이미지, 날짜).

## Veyon 같은 PC 관리 프로그램과 함께 쓰기

WinPE로 넘어가기 전에 DVT가 각 클라이언트에 필요로 하는 것은 두 가지입니다.
토렌트와 함께 둔 `C:\temp\boot` 폴더, 그리고 `make_boot.bat` 한 번 실행. 이 일을
PC마다 직접 하는 것이 배포에서 가장 시간이 많이 드는 부분입니다.
[Veyon](https://veyon.io)(무료, 오픈 소스) 같은 실습실·PC 관리 프로그램을 쓰면 한
화면에서 실습실 전체를 처리할 수 있습니다.

| DVT 단계 | 관리 프로그램 없이 | Veyon과 함께 |
|---|---|---|
| PC 켜기 | PC마다 가서 전원 켜기 | 모든 PC를 **전원 켜기**(Wake-on-LAN) |
| `C:\temp\boot`와 토렌트 복사 | PC마다 USB로 복사 | 모든 PC에 **파일 전송** 후 **프로그램 실행**으로 `C:\temp`에 배치 |
| `make_boot.bat` 실행 | PC마다 로그인해서 실행 | 모든 PC에서 **프로그램 실행**을 한 번에 |
| IP와 링크 속도 확인 | 모니터를 하나씩 확인 | `make_boot.bat`이 IP를 큰 글씨로, 링크 속도를 콘솔 색으로 보여 주므로 Veyon **모니터링** 화면에서 한눈에 확인 |
| WinPE로 재시작 | PC마다 키 누르기 | **원격 제어**로 키 입력, 또는 모든 PC **재시작** |
| 복원 완료 확인 | 다시 한 바퀴 돌기 | 복원된 PC가 Veyon에 다시 나타남(이미지에 Veyon 서비스가 있을 때) |

**테스트 이미지**에도 똑같이 쓸 수 있습니다. 먼저 실습실 전체에서 테스트 이미지를
돌려 FTP로 `<ip>.txt` 보고서를 모으고, 실패한 PC를 고친 뒤 실제 배포를 하세요.

주의할 점:

- `make_boot.bat`은 **관리자 권한**이 필요합니다. 권한 상승 창을 Veyon 원격 제어로
  승인하거나, 관리자 계정으로 실행하세요.
- Veyon은 전송한 파일을 기본적으로 사용자 프로필 폴더에 저장합니다. **프로그램
  실행**으로 작은 스크립트를 돌리는 등의 방법으로 `C:\temp`로 옮기세요.
- PC가 **WinPE**에 있는 동안에는 Veyon 서비스가 실행되지 않아 Veyon에서 보이지
  않습니다. PC 화면을 직접 보거나 테스트 이미지의 FTP 보고서를 활용하세요.
- **백업 이미지**에 Veyon 서비스를 포함해 두면(필요하면 `setpc.bat`에서 설정)
  복원된 PC를 바로 관리할 수 있습니다.

## 빠른 시작

1. **빌드 PC:** Windows ADK와 WinPE 추가 기능을 설치하고, `aria2c.exe`,
   `wimlib-imagex.exe`(+ DLL)를 `pe_tools\`에, `nircmd.exe`를 `nircmd-x64\`에 넣은 뒤
   `01_make_pe.bat`을 실행합니다.
2. **시더:** `DVT_backup` 폴더에 `backup.wim`과 내용이 있는 `dvt_check.txt`를 넣고
   `DVT_backup.torrent`(V1)를 만든 뒤 qBittorrent 내장 트래커로 시딩합니다.
3. **클라이언트:** `_output\boot`를 `C:\temp\boot`로, 토렌트를 `C:\temp`로 복사하고
   `C:\temp\boot\make_boot.bat`을 실행합니다 — 직접 또는 Veyon으로.

자세한 내용, 설정, 문제 해결: [doc/manual.ko.md](doc/manual.ko.md)

## 요구 사항

- 빌드 PC: Windows 10/11 x64, Windows ADK와 WinPE 추가 기능
- 클라이언트: x64 PC, UEFI 또는 BIOS, 유선 네트워크
- BitTorrent 트래커와 시더 최소 한 대(qBittorrent 하나로 둘 다 가능, 설정 매뉴얼은
  qBittorrent 5.3.0 일반 설치 파일(libtorrent 2.1) 기준)

## 외부 도구

DVT에는 포함되어 있지 않습니다. 각 공식 사이트에서 내려받으세요.
[aria2](https://github.com/aria2/aria2) ·
[wimlib](https://wimlib.net/) ·
[NirCmd](https://www.nirsoft.net/utils/nircmd.html) ·
[Windows ADK](https://learn.microsoft.com/windows-hardware/get-started/adk-install) ·
선택: [qBittorrent](https://www.qbittorrent.org/),
[Veyon](https://veyon.io), [Rufus](https://rufus.ie)

## 라이선스

[BSD 3-Clause License](LICENSE) — Copyright (c) 2026, zerojinny.
DVT는 설계상 디스크를 지웁니다. 사용에 따른 책임은 사용자에게 있습니다.
