# DVT — Deploy Via Torrent

[English](README.md) | **한국어**

DVT는 로컬 네트워크에서 여러 대의 PC에 Windows 이미지를 한꺼번에 복원하는 도구입니다.
각 PC는 작은 WinPE 이미지로 부팅한 뒤, 백업 이미지를 BitTorrent(aria2)로 내려받고
wimlib로 적용합니다. 다운로드를 마친 PC는 다른 PC에게 업로드도 하기 때문에,
파일 서버 한 대로 배포할 때와 달리 PC 수가 늘어나도 배포 속도가 크게 떨어지지 않습니다.

클라이언트 PC에서 DVT를 시작하는 방법은 두 가지입니다.

- **클라이언트 로컬부팅** — 클라이언트의 Windows에서 `host\make_boot.bat`을 실행하면 그 PC에
  맞게 WinPE 이미지를 준비하고 WinPE로 재시작합니다. PC 앞에서 입력할 것이 없습니다.
- **USB / CD 미디어** — `make_media.bat`으로 부팅 USB 드라이브나 ISO를 만듭니다.
  Windows가 시작되지 않는 PC나, 클라이언트의 Windows에서 미리 아무것도 실행하고
  싶지 않을 때 사용합니다. 작업자가 PC마다 IP 주소와 디스크를 입력합니다.

모든 스크립트는 순수 Windows 배치 파일입니다. WinPE 안에서 실행되는 스크립트는
WinPE 기본 도구만 사용하며(WMIC, WMI, PowerShell, findstr 사용 안 함),
추가로 aria2c, wimlib-imagex, NirCmd를 사용합니다.

> [!WARNING]
> DVT는 실행되는 클라이언트 PC의 **디스크 하나를 통째로 지웁니다.**
> [지울 디스크 선택](#지울-디스크-선택) 항목을 먼저 읽고, 실습실이나 사무실에서
> 사용하기 전에 여분의 PC로 반드시 테스트하세요.

---

## 목차

- [동작 방식](#동작-방식)
- [주요 기능](#주요-기능)
- [요구 사항](#요구-사항)
- [저장소 구성](#저장소-구성)
- [빠른 시작 — 클라이언트 로컬부팅](#빠른-시작--클라이언트-로컬부팅)
- [빠른 시작 — USB / CD 미디어](#빠른-시작--usb--cd-미디어)
- [테스트 이미지](#테스트-이미지)
- [토렌트 준비](#토렌트-준비)
- [지울 디스크 선택](#지울-디스크-선택)
- [네트워크](#네트워크)
- [USB / CD 미디어 세부 사항](#usb--cd-미디어-세부-사항)
- [설정](#설정)
- [스크립트 목록](#스크립트-목록)
- [문제 해결](#문제-해결)
- [제한 사항](#제한-사항)
- [외부 도구](#외부-도구)
- [라이선스](#라이선스)

---

## 동작 방식

| | 클라이언트 로컬부팅 | USB / CD 미디어 |
|---|---|---|
| 빌드 PC | `make_pe.bat` → `boot\` 폴더 | `make_media.bat` → ISO 또는 USB 드라이브 |
| WinPE 전 클라이언트 PC | Windows에서 `host\make_boot.bat` 실행 (PC마다 한 번) | 없음 — 미디어로 부팅 |
| WinPE 주 스크립트 | `pe\start_dvt.bat` | `Media\pe\start_media.bat` |
| IP 주소 | Windows에서 확인 (고정 IP → `ip.txt`) | `ip.txt`의 고정 IP(끝자리는 작업자 입력) 또는 DHCP, 순서는 `DHCP_ENABLE` |
| 지울 디스크 | 자동 판별 (`DVT.tag`) | 작업자가 입력 |
| 지우기 전 실패 시 | 기존 Windows로 재부팅 | 키 입력을 기다린 뒤 재부팅 |
| WinPE 설정 | `pe\config.cmd` (`boot.wim` 안) | `Media\pe\config.cmd` (미디어에도 복사, USB에서 수정 가능) |

두 방법 모두 무엇이든 지우기 **전에** 게이트웨이와 시더를 확인하며, 같은 토렌트,
aria2 프로필, 다운로드, 복원(`restore.bat`, `setpc.bat`)을 사용합니다.

### 클라이언트 로컬부팅

```
[1] 빌드 PC ── make_pe.bat
      ADK winpe.wim + DVT 스크립트 + aria2c, wimlib
      → boot\ 폴더 (boot.wim, boot.sdi, host 스크립트)
         │
         │  boot\ 폴더 → 클라이언트의 C:\temp\boot 로 복사
         ▼
[2] 클라이언트 PC (Windows) ── host\make_boot.bat
      • IP 주소와 링크 속도 확인
      • 네트워크 드라이버 추출
      • boot.wim에 드라이버, ip.txt, 토렌트, aria2.conf 추가
      • Windows 드라이브에 DVT.tag 기록
      • 1회용 부팅 항목 추가
         │
         │  재부팅
         ▼
[3] 클라이언트 PC (WinPE) ── start_dvt.bat
      • 대상 디스크 확인 (DVT.tag)
      • 네트워크 설정
      • 게이트웨이·시더 확인        ← 여기까지 실패하면 디스크를 건드리지 않고
                                       기존 Windows로 재부팅
      • 디스크 삭제, 파티션 생성
      • 토렌트 다운로드 (aria2c)
         │
         │  다운로드 완료 (aria2c는 계속 시딩)
         ▼
    restore.bat
      • WIM 적용, 드라이버, bcdboot, setpc.bat
         │
         ▼
    복원된 Windows로 재부팅
```

### USB / CD 미디어

```
[1] 빌드 PC ── make_media.bat
      source\winpe.wim (ADK 원본 사본)
      + pe_tools, drivers, nircmd
      + Media\pe  (이 스크립트만 사용)
      → media_out\boot.wim
      + Media\adk_media, Media\config, Media\pe\config.cmd
      → ISO (oscdimg) 또는 USB 드라이브
         │
         │  USB / CD로 부팅
         ▼
[2] 클라이언트 PC (WinPE) ── startnet.cmd
      • <미디어>\config\* → X:\restore 복사
         ▼
    start_media.bat
      • 네트워크 순서 결정 (DHCP_ENABLE: 고정 IP 우선 / DHCP 우선)
      • 디스크 목록 표시, "150.0" 입력 (IP 끝자리.디스크 번호)
      • 게이트웨이 확인
      • link.exe → 링크 속도별 aria2.conf
      • 시더 확인                   ← 여기까지 실패하면 아무것도 지우지 않음
      • 디스크 삭제, 파티션 생성
      • 다운로드 드라이브 선택, 토렌트 다운로드 (aria2c)
         │
         │  다운로드 완료 (aria2c는 계속 시딩)
         ▼
    restore.bat
      • WIM 적용, 드라이버, bcdboot
      • 파일 이동, setpc.bat
         │
         ▼
    재부팅 (USB / CD를 빼세요)
```

미디어 이미지는 `boot\boot.wim`이나 `pe` 폴더를 **사용하지 않습니다**.
`X:\restore`에는 `pe_tools`의 도구와 `Media\pe`의 파일만 들어갑니다.

## 주요 기능

- **BitTorrent 배포**: aria2c를 사용하며, 다운로드가 끝나는 즉시 복원을 시작하고
  이미지를 적용하는 동안에도 계속 시딩합니다.
- **삭제 전 안전 점검**: 대상 디스크, 네트워크, 게이트웨이, 그리고 시더로부터의
  실제 다운로드를 먼저 확인합니다. 하나라도 실패하면 아무것도 지우지 않습니다.
- **대상 디스크 자동 판별**: 실행 중인 Windows에서 기록한 표식 파일(`DVT.tag`)로
  찾으며, 직접 지정과 신중한 대체 규칙도 제공합니다. 조금이라도 애매하면 오류로
  처리합니다. USB / CD 미디어에서는 작업자가 디스크를 고르며, 부팅 미디어는 고를 수
  없습니다.
- **UEFI와 레거시 BIOS 지원**: GPT/MBR 구성과 `bcdboot` 펌웨어 유형을 자동으로
  선택합니다. ISO와 USB 드라이브도 둘 다에서 부팅됩니다.
- **고정 IP 또는 DHCP**: Windows에서 쓰던 고정 IP를 WinPE로 가져와,
  게이트웨이에 연결되는 어댑터에 적용합니다. 미디어는 고정 IP와 DHCP 중 하나를
  먼저 시도하고(`DHCP_ENABLE`) 실패하면 다른 쪽을 사용합니다.
- **실행 중인 PC의 네트워크 드라이버 사용**: 드라이버를 추출해 WinPE에 넣으므로,
  WinPE가 기본으로 지원하지 않는 랜카드도 동작합니다.
- **링크 속도별 프로필**: 100 Mbps와 1 Gbps 링크에 각각 다른 aria2 설정을 사용합니다.
- **복원 후 작업**: 추가 파일을 `C:\temp`로 복사하고, 선택적으로 `setpc.bat`을
  Windows 첫 시작 시 한 번 실행합니다.
- **1회용 부팅 항목**: 사용 후 자동으로 삭제됩니다.
- **USB / CD 미디어**: Windows가 동작하지 않는 PC용. USB 드라이브라면 다시 빌드하지
  않고 설정을 바꿀 수 있습니다.
- **큰 글씨 IP 표시**: 멀리서도 어느 PC인지 알아볼 수 있습니다.

## 요구 사항

**빌드 PC**

- Windows 10/11 x64, 관리자 권한
- [Windows ADK](https://learn.microsoft.com/windows-hardware/get-started/adk-install)와
  **Windows PE 추가 기능**(amd64). USB / CD 미디어는 ADK의 **Deployment Tools**도
  필요합니다(처음 실행할 때만, 아래 참고).
- `aria2c.exe`, `wimlib-imagex.exe`(DLL 포함) — `pe_tools\` 또는 `system32\`에 배치
- `nircmd.exe`(x64) — `nircmd-x64\`에 배치
- USB / CD 미디어만: `Media\pe`의 64비트 `link.exe`. 컴파일하지 않고 그대로
  사용하며, 없으면 `make_media.bat`이 중단됩니다.

`make_media.bat`은 ADK의 `Media` 폴더를 `Media\adk_media`에, oscdimg·부트 섹터
파일·bootsect를 `Media\adk_tools`에 보관하고, 이후에는 보관본(과 `make_pe.bat`과
함께 쓰는 `source\winpe.wim`)만 사용합니다. `make_pe.bat`을 먼저 실행할 필요는
없습니다.

**클라이언트 PC**

- 클라이언트 로컬부팅: Windows 10/11 x64, 관리자 권한(`make_boot.bat` 실행용)
- USB / CD 미디어: USB나 CD로 부팅할 수 있는 PC (UEFI 또는 BIOS)
- 배포 네트워크에 유선으로 연결

**배포 네트워크**

- 클라이언트에서 접근 가능한 BitTorrent **트래커**. aria2 프로필에서 DHT,
  피어 교환(PEX), 로컬 피어 탐색(LPD)을 꺼 두었기 때문에 피어는 트래커로만 찾습니다.
- 완전한 `DVT_backup` 폴더를 가진 **시더**가 최소 한 대

## 저장소 구성

```
dvt/
├─ make_pe.bat              WinPE 이미지 빌드 (빌드 PC)
├─ make_test_pe.bat         테스트용 WinPE 이미지 빌드 (빌드 PC)
├─ make_media.bat           USB / CD 미디어 빌드: ISO, 새 USB 드라이브,
│                           USB 드라이브 갱신 (빌드 PC)
├─ host/                    Windows 쪽 스크립트 (클라이언트 PC)
│  ├─ config.cmd            host 스크립트와 make_pe.bat 설정
│  ├─ make_boot.bat         클라이언트 PC 준비 후 WinPE로 재시작
│  ├─ get_host_ip.bat       IP 주소, 고정/DHCP 판별
│  ├─ get_link_speed.bat    링크 속도 -> aria2 프로필
│  ├─ export_net_drivers.bat
│  ├─ prepare_mount_dir.bat
│  ├─ set_bcd.bat           1회용 WinPE 부팅 항목
│  └─ show_ip.bat           IP 주소를 큰 글씨로 표시
├─ pe/                      WinPE 스크립트 (X:\restore로 복사됨)
│  ├─ config.cmd            WinPE 스크립트 설정
│  ├─ startnet.cmd          WinPE 시작 지점
│  ├─ start_dvt.bat         주 흐름
│  ├─ restore.bat           이미지 적용, 부팅 파일, 정리
│  ├─ start_restore.bat     다운로드 완료 시 aria2c가 호출
│  ├─ aria2.conf.100        100 Mbps 링크용 aria2 프로필
│  ├─ aria2.conf.1G         1 Gbps 링크용 aria2 프로필
│  └─ ...                   보조 스크립트 (스크립트 목록 참고)
├─ Media/                   USB / CD 미디어
│  ├─ config.cmd            make_media.bat 설정 (host\config.cmd를 불러옴)
│  ├─ link.au3              link.exe의 소스 (참고용)
│  ├─ config/               <미디어>\config로 복사됨
│  │  ├─ DVT_backup.torrent
│  │  ├─ aria2.conf.100
│  │  ├─ aria2.conf.1G
│  │  ├─ ip.txt             고정 IP (ip.txt.example 참고)
│  │  └─ ip.txt.example
│  ├─ pe/                   미디어의 모든 WinPE 스크립트 -> X:\restore
│  │  ├─ config.cmd         미디어 WinPE 스크립트 설정
│  │  │                     (<미디어>\config에도 복사됨)
│  │  ├─ startnet.cmd       미디어 찾기, config\ 복사, start_media.bat 실행
│  │  ├─ start_media.bat    주 흐름
│  │  ├─ get_input.bat      디스크 목록, IP 끝자리와 디스크 번호 입력
│  │  ├─ getdiskinfo.bat    디스크 목록
│  │  ├─ set_ip.bat         인수(ip, mask, gateway)로 고정 IP 설정
│  │  ├─ get_target.bat     다운로드 드라이브 선택, 부팅 미디어는 제외
│  │  ├─ restore.bat        적용, 파일 이동, 미디어 제거 안내
│  │  ├─ link.exe           링크 속도별 aria2.conf 선택 (64비트, 필수)
│  │  └─ ...                pe 스크립트의 사본: check_gateway, check_seeder,
│  │                        get_firmware, get_ip, make_disk, ping_host,
│  │                        start_restore, wait
│  ├─ adk_media/            ADK WinPE "Media" 폴더 보관본
│  └─ adk_tools/            oscdimg.exe, etfsboot.com, bootsect.exe,
│                           efisys.bin (= ADK efisys_noprompt.bin 이름 변경) 보관본
├─ test/                    테스트 이미지 스크립트 (테스트 이미지 참고)
│  ├─ test_config.cmd       FTP 서버와 테스트 설정
│  ├─ startnet.cmd          테스트 WinPE 시작 지점
│  ├─ start_test.bat        테스트 흐름: 네트워크, 게이트웨이, 시더, 업로드
│  └─ upload_ftp.bat        FTP 업로드 (curl.exe 또는 ftp.exe)
│
│  ── 저장소에 포함되지 않음, 직접 준비 ──
├─ pe_tools/                aria2c.exe, wimlib-imagex.exe, DLL -> X:\restore
├─ system32/                선택 사항, X:\Windows\System32로 복사
├─ drivers/                 선택 사항, 모든 WinPE 이미지에 추가할 드라이버
├─ nircmd-x64/nircmd.exe
│
│  ── 빌드 스크립트가 생성 ──
├─ source/                  ADK의 원본 winpe.wim과 boot.sdi
├─ boot/                    make_pe.bat 결과: boot.wim + boot.sdi + host 스크립트
│                           (클라이언트의 C:\temp\boot로 복사)
├─ boot_test/               make_test_pe.bat 결과 (boot/와 같은 방식으로 사용)
└─ media_out/               make_media.bat 결과: 미디어용 boot.wim, DVT_media.iso
```

## 빠른 시작 — 클라이언트 로컬부팅

### 1. WinPE 이미지 빌드 (빌드 PC)

1. Windows ADK와 WinPE 추가 기능을 설치합니다.
2. `aria2c.exe`, `wimlib-imagex.exe`와 DLL을 `pe_tools\`에,
   `nircmd.exe`를 `nircmd-x64\`에 넣습니다.
3. 필요하면 `drivers\`에 드라이버를 넣습니다(예: 신형 하드웨어용 스토리지 드라이버,
   [Realtek 랜카드](#realtek-랜카드)용 WinPE 드라이버).
4. `pe\config.cmd`를 확인합니다([설정](#설정) 참고).
5. `make_pe.bat`을 실행합니다. 필요하면 관리자 권한을 요청합니다.

결과물은 `boot\` 폴더입니다. 이 폴더에는 `boot.wim`, `boot.sdi`, 그리고 `host\`의
모든 파일이 복사되어 있어, 토렌트를 제외하면 클라이언트 PC에 필요한 것이 모두 들어 있습니다.

> 마운트 폴더와 작업 폴더는 로컬 시스템 드라이브(`C:\WinPE_LocalBuild`)에 있습니다.
> OneDrive, Dropbox 등으로 동기화되는 폴더로 옮기지 마세요. 동기화 프로그램이
> 마운트 해제 후 삭제된 파일을 되살릴 수 있습니다.

### 2. 토렌트와 시더 준비

[토렌트 준비](#토렌트-준비)를 참고하세요. 트래커와 시더를 실행해 둡니다.

### 3. 각 클라이언트 PC 준비

빌드 PC의 `boot\` 폴더를 클라이언트의 `C:\temp\boot`로, 토렌트를 `C:\temp`로 복사합니다.

```
C:\temp\
├─ boot\
│  ├─ boot.wim
│  ├─ boot.sdi
│  ├─ make_boot.bat
│  ├─ config.cmd
│  └─ ...             (나머지 host 스크립트)
└─ DVT_backup.torrent
```

`C:\temp\boot\make_boot.bat`을 실행하면 다음 작업을 합니다.

1. IP 주소를 확인합니다(고정 IP이면 ip, 서브넷, 게이트웨이를 한 줄에 하나씩
   `ip.txt`에 저장).
2. 링크 속도를 읽어 `aria2.conf.100` 또는 `aria2.conf.1G`를 고릅니다.
3. 연결된 네트워크 어댑터의 드라이버를 추출합니다.
4. `boot.wim`을 마운트하고 드라이버, `ip.txt`, 토렌트, `aria2.conf`를 넣습니다.
5. Windows 드라이브에 `DVT.tag`를 기록합니다.
6. 1회용 WinPE 부팅 항목을 추가합니다.
7. IP 주소를 큰 글씨로 보여 주고, 키를 누르면 재시작합니다.

### 4. 진행 확인

PC가 WinPE로 부팅해 스스로 복원합니다. 콘솔 색으로 상태를 알 수 있습니다.

| 콘솔 | 의미 |
|---|---|
| 밝은 회색 배경 | 점검, 파티션 생성, 다운로드 중 |
| 녹색 배경 (새 "DVT Restore" 창) | 복원 진행 중, 이어서 완료 후 재부팅 |
| 빨간색 배경 | 실패 — 화면의 메시지를 확인하세요 |

디스크를 지우기 **전에** 점검이 실패하면 몇 초 뒤 기존 Windows로 다시 부팅합니다.
디스크를 지운 **후에** 문제가 생기면 오류를 읽을 수 있도록 키 입력을 기다립니다.

## 빠른 시작 — USB / CD 미디어

1. 토렌트와 시더를 준비합니다([토렌트 준비](#토렌트-준비) 참고).
2. `Media\config`에 파일을 넣습니다: `DVT_backup.torrent`, `aria2.conf.100`,
   `aria2.conf.1G`, 고정 IP를 쓸 때 `ip.txt`([네트워크](#네트워크) 참고).
3. `Media\pe\config.cmd`를 확인합니다([설정](#설정) 참고).
4. 빌드 폴더의 `make_media.bat`을 관리자 권한으로 실행하고 선택합니다.
   - `1` ISO → `media_out\DVT_media.iso`, CD / DVD로 굽기
   - `2` USB → 선택한 **USB** 디스크를 지우고 부팅 가능하게 만듦
     (디스크 전체를 FAT32로, `Media\config.cmd`의 `USB_FS`, `USB_PART_MB`)
   - `3` 갱신 → 기존 DVT USB 드라이브에 새 파일 복사

   `make_media.bat iso`, `make_media.bat usb`, `make_media.bat update`로 메뉴를
   건너뛸 수 있습니다.
5. 클라이언트 PC를 미디어로 부팅하고 디스크 목록을 확인한 뒤, 고정 IP라면
   `<IP 끝자리>.<디스크>`(예: `150.0`), DHCP라면 디스크 번호만 입력하고 `Y`를
   누릅니다.
6. 복원이 끝나면 15초 후 재부팅합니다 — 미디어를 빼세요.

> [!WARNING]
> 입력한 번호의 디스크는 **지워집니다**. 디스크 목록을 잘 확인하세요. 부팅에
> 사용한 USB 드라이브의 디스크는 선택할 수 없습니다.

작업자가 있으므로 미디어에서는 실패하면 항상 키 입력을 기다립니다.

## 테스트 이미지

`make_test_pe.bat`은 디스크를 전혀 건드리지 않고 클라이언트 PC를 처음부터 끝까지
점검하는 **테스트용** WinPE 이미지를 만듭니다. 실제 복원 전에 네트워크, 드라이버,
시더 문제를 찾는 데 사용합니다. 클라이언트 로컬부팅과 같은 방법(`make_boot.bat`)으로
시작합니다.

테스트 이미지는 WinPE에서 다음을 수행합니다.

1. 복원 이미지와 똑같이 네트워크를 설정(`ip.txt`가 있으면 고정 IP, 없으면 DHCP)하고
   게이트웨이를 확인합니다.
2. 시더 점검을 합니다(`dvt_check.txt`만 메모리로 다운로드).
3. 보고서 `<ip>.txt`를 만듭니다(IP, 게이트웨이, 어댑터, 링크 프로필, 시더, 펌웨어,
   감지된 대상 디스크, 모델, `diskpart list disk`, 대상 디스크의 `detail disk`,
   `ipconfig /all`).
4. FTP 서버에 업로드한 뒤 Windows로 재부팅합니다.

디스크를 지우거나 복원하는 스크립트(`make_disk.bat`, `restore.bat`,
`start_restore.bat`, `start_dvt.bat`)는 테스트 이미지에 **복사되지 않습니다**.

사용 순서:

1. `test\test_config.cmd`에 FTP 서버를 설정합니다:
   `FTP_HOST`, `FTP_PORT`, `FTP_USER`, `FTP_PASS`, 필요하면 `FTP_DIR`
   (로그인 폴더 기준 상대 경로). 값에 `!`와 `"`는 쓸 수 없습니다.
2. 빌드 PC에서 `make_test_pe.bat`을 실행합니다. 결과물은 `boot_test\` 폴더입니다.
3. 클라이언트에서 `boot\` 대신 `boot_test\`를 `C:\temp\boot`로 복사하고, 토렌트를
   `C:\temp`에 둔 뒤 평소처럼 `make_boot.bat`을 실행합니다.

| 화면 | 의미 |
|---|---|
| 녹색 "PASS" | 게이트웨이·시더 정상, `<ip>.txt` 업로드 완료, 재부팅 |
| 빨간색 "TEST FAILED" | 점검 또는 업로드 실패. `FAIL_REBOOT_SEC` 후 재부팅(`TEST_FAIL_REBOOT=1`, 기본값). `TEST_FAIL_REBOOT=0`이면 키 입력 대기 |

`TEST_UPLOAD_FAIL=1`이면 IP가 설정된 경우 실패 시에도 `<ip>_FAIL.txt`를 업로드합니다.
FTP 클라이언트는 `curl.exe`(패시브 모드, `FTP_DIR` 자동 생성)를 우선 쓰고, 없으면
`ftp.exe`(액티브 모드만 지원, `FTP_DIR`이 미리 있어야 함)를 씁니다. WinPE에는 둘 다
없으므로 `pe_tools\`나 `system32\`에 넣지 않으면 `make_test_pe.bat`이 빌드 PC에서
복사합니다. FTP 설정은 이미지 안에 들어가므로 바꾼 뒤에는 다시 빌드해야 합니다.

## 토렌트 준비

토렌트에는 `DVT_backup`(`DL_NAME`)이라는 최상위 폴더 하나만 있어야 합니다.

```
DVT_backup\
├─ backup.wim        Windows 이미지 (1번 인덱스를 적용)           필수
├─ dvt_check.txt     시더 점검용 작은 파일 (수 KB)                 필수
├─ drivers\          복원된 Windows에 추가할 드라이버              선택
└─ files\            복원된 Windows의 C:\temp로 복사               선택
   └─ setpc.bat      Windows 첫 시작 시 한 번 실행                 선택
```

- `dvt_check.txt`는 토렌트를 만들기 **전에** 넣어야 합니다. WinPE는 무엇이든 지우기
  전에 이 파일만 내려받아 시더에 연결되는지 확인합니다.
- 토렌트에 트래커 URL을 넣습니다. 또는 `pe\config.cmd`나 `Media\pe\config.cmd`에서
  `SEEDER_EXTRA_OPTS=--bt-tracker=http://...`를 지정할 수 있습니다(이 값은 시더 점검에만
  쓰이며, 본 다운로드는 토렌트와 `aria2.conf`의 설정을 따릅니다).
- 토렌트 파일 이름은 `DVT_backup.torrent`로 저장합니다. 클라이언트 로컬부팅은 각 클라이언트의
  `C:\temp`에, 미디어는 `Media\config`에 둡니다.
- 클라이언트가 고정 IP를 쓰면 `ip.txt`(ip, 서브넷, 게이트웨이)도 복원된 Windows의
  `C:\temp`로 복사되므로, `setpc.bat`에서 주소를 다시 설정할 수 있습니다.

> [!WARNING]
> `dvt_check.txt`는 **비어 있는 0바이트 파일이면 안 됩니다.** 받을 데이터가
> 없으므로 aria2c는 시더에 연결되지 않아도 다운로드를 "완료"하고, 점검이 의미가
> 없어집니다. 그래서 `check_seeder.bat`은 토렌트 안의 `dvt_check.txt`가 0바이트이면
> 디스크를 지우기 전에 점검을 실패로 처리합니다("The seeder check file in the
> torrent is empty"). 반드시 내용이 있는 파일(수 KB)을 넣고 토렌트를 만드세요.
> 파일을 바꿨다면 토렌트도 다시 만들어야 합니다.

## 지울 디스크 선택

### 클라이언트 로컬부팅

`get_disk.bat`은 다음 순서로 지울 디스크를 정합니다.

1. `pe\config.cmd`의 **`FORCE_DISK`** (지정된 경우)
2. **`DVT.tag`** 가 있는 볼륨의 디스크. `make_boot.bat`이 실행 중인 Windows
   드라이브에 이 파일을 쓰고, 다른 드라이브에 있는 것은 모두 지웁니다.
3. `AUTO_DISK_FALLBACK=1`일 때만:
   1. 포맷되지 않은(RAW) 볼륨이 **하나뿐**이면 그 볼륨의 디스크
   2. PC에 디스크가 **하나뿐**이면 그 디스크

태그가 여러 디스크에 있거나, RAW 볼륨이 여러 개이거나, 태그 없이 디스크가 여러 개이면
오류로 처리합니다. DVT는 절대 추측하지 않습니다. 태그 파일을 반드시 요구하려면
`AUTO_DISK_FALLBACK=0`으로 설정하세요.

복원된 Windows에서는 태그가 삭제되므로 다음 실행은 깨끗한 상태에서 시작합니다.

### USB / CD 미디어

`DVT.tag`가 없습니다. `get_input.bat`이 디스크 목록을 보여 주고 작업자가 디스크
번호를 입력합니다(`R`은 디스크를 다시 검색). 존재하는 디스크여야 하며, 부팅
미디어의 디스크는 선택할 수 없습니다. `MEDIA_CONFIRM=1`(기본값)이면 디스크를
지우기 전에 `Y`로 한 번 더 확인합니다.

## 네트워크

### 클라이언트 로컬부팅

- **DHCP**(기본): WinPE가 주소를 받을 때까지 기다리고(`DHCP_WAIT_TRIES` × 2초),
  메트릭이 가장 낮은 기본 경로를 사용합니다.
- **고정 IP**: Windows가 고정 IP를 쓰고 있었다면 `make_boot.bat`이 주소, 서브넷
  마스크, 게이트웨이를 한 줄에 하나씩 이미지 안의 `ip.txt`에 저장합니다.
  ```
  192.168.0.10
  255.255.255.0
  192.168.0.1
  ```
  WinPE는 이 세 값과 `NET_DNS1/2`로 적용하며(주소만 있는 `ip.txt`는
  `NET_MASK`와 게이트웨이 `x.x.x.1` 사용), 연결된 어댑터를 모두 시도해
  게이트웨이(와 지정된 경우 `NET_TEST_HOST`)에 응답하는 첫 어댑터를 사용하고
  나머지는 DHCP로 되돌립니다.
- **링크 속도**: `make_boot.bat`이 측정합니다. 1 Gbps 이상이면 `aria2.conf.1G`,
  그 밖에는 `aria2.conf.100`을 사용합니다. 클라이언트의 콘솔 색으로 어떤 프로필이
  선택되었는지 알 수 있습니다(`host\config.cmd`의 `COLOR_LINK_*`).

### USB / CD 미디어

순서는 `Media\pe\config.cmd`의 `DHCP_ENABLE`로 정합니다.

| `DHCP_ENABLE` | `ip.txt` | 동작 |
|---|---|---|
| `0` 또는 없음 (기본값) | 있음 | **고정 IP 우선.** 작업자가 IP 끝자리와 디스크 번호를 입력하면 주소를 설정하고 게이트웨이를 테스트합니다. 실패하면 모든 어댑터를 DHCP로 바꿔 DHCP 게이트웨이를 다시 테스트합니다. 성공하면 고정 IP는 실패했지만 DHCP는 성공했다는 메시지를 보여 주고, 앞서 선택한 디스크로 DHCP를 사용해 계속합니다(`DHCP_FALLBACK_CONFIRM=1`이면 먼저 묻고, `N`이면 중단). |
| `1` | 있음 | **DHCP 우선.** 최대 `DHCP_FIRST_TRIES` × 2초(20초) 동안 DHCP 주소를 기다리고 게이트웨이를 테스트합니다. 둘 다 성공하면 디스크 번호만 묻습니다. 아니면 고정 IP를 사용합니다. 작업자가 IP 끝자리와 디스크 번호를 입력하면 주소를 설정하고 테스트합니다. |
| 상관없음 | 없음 | **DHCP만 사용.** 디스크 번호만 묻습니다. |

어느 방법도 성공하지 못하면 아무것도 지우지 않고 키 입력 후 재부팅합니다.

`Media\config`의 `ip.txt`는 위와 같은 3행 형식이지만, 1행은 기준 주소입니다.
앞 세 옥텟만 사용하며(`ipr`) 끝자리는 작업자가 입력합니다.

```
192.168.0.0
255.255.255.0
192.168.0.1
```

2행(subnet)과 3행(gateway)은 생략할 수 있습니다(`NET_MASK`, `ipr.1`). 그래서
주소만 있는 `ip.txt`도 쓸 수 있습니다. `#`으로 시작하는 줄은 무시합니다. BOM 있는
UTF-8이 아니라 ANSI / ASCII로 저장하세요.

고정 IP가 성공하면 실제로 적용한 값(ip, subnet, gateway)으로 `ip.txt`를 새로 만들어
`setpc.bat`용으로 `T:\temp\ip.txt`에 옮깁니다. DHCP일 때는(전환된 경우 포함)
`ip.txt`를 만들지 않습니다.

링크 속도는 WinPE에서 `link.exe`가 측정해 `aria2.conf.1G` 또는 `aria2.conf.100`의
이름을 `aria2.conf`로 바꿉니다(`link.exe`가 없거나 실패하면 `LINK_FALLBACK`).

### Realtek 랜카드

`make_boot.bat`은 기본적으로 **Realtek 네트워크 드라이버를 추출하지 않습니다**
(`NETDRV_EXCLUDE=Realtek`). Realtek은 **WinPE용 드라이버를 따로 제공**하며, 일반
Windows용 드라이버를 WinPE에 넣으면 다운로드 중 **연결이 끊기는** 등의 오류가 생길
수 있기 때문입니다. USB / CD 미디어는 드라이버를 전혀 추출하지 않으므로, WinPE가
기본 지원하지 않는 랜카드의 드라이버는 모두 `drivers\`에 있어야 합니다.

> [!IMPORTANT]
> Realtek 랜카드를 쓰는 PC가 있다면 Realtek의 **WinPE용 드라이버**를 빌드 PC의
> `drivers\` 폴더(예: `drivers\realtek\`)에 넣고 `make_pe.bat`과 `make_media.bat`으로
> 다시 빌드하세요. `drivers\`의 드라이버는 모든 WinPE 이미지에 들어갑니다.
>
> `NETDRV_EXCLUDE`를 비워 Realtek의 Windows용 드라이버를 추출하는 것은 권장하지
> 않습니다.

## USB / CD 미디어 세부 사항

### config 폴더

`make_media.bat`은 `Media\config`의 파일과 `Media\pe\config.cmd`를 `<미디어>\config`로
복사합니다. WinPE가 시작되면 `startnet.cmd`가 `<미디어>\config`를 `X:\restore`로
복사하므로, USB 드라이브라면 다시 빌드하지 않고 바꿀 수 있습니다.
`<미디어>\config\config.cmd`는 `boot.wim` 안의 `config.cmd`를 덮어쓰므로, 그
설정(`DHCP_ENABLE`, `MEDIA_CONFIRM` 등)은 다음 부팅부터 적용됩니다. CD는
`Media\config`나 `Media\pe\config.cmd`를 고친 뒤 다시 빌드해야 합니다.

| 파일 | 용도 |
|---|---|
| `DVT_backup.torrent` | 필수. 안의 `dvt_check.txt`가 비어 있으면 안 됨([토렌트 준비](#토렌트-준비) 참고) |
| `aria2.conf.1G`, `aria2.conf.100` | 필수. `link.exe`가 링크 속도에 맞는 파일을 `aria2.conf`로 이름 변경 |
| `ip.txt` | 고정 IP 기본값. 우선 또는 대체로 사용(`DHCP_ENABLE`) |
| `config.cmd` | `Media\pe\config.cmd` 사본. WinPE 설정 |

빌드 PC의 `Media\pe\config.cmd`가 원본입니다. USB 드라이브를 새로 만들거나
갱신하면(`2`, `3`) USB에서 고친 `config.cmd`는 이 원본으로 덮어써집니다.

### USB 드라이브와 ISO

- 새 USB 드라이브에는 **FAT32** 파티션(`USB_FS=fat32`) 하나를 만듭니다. UEFI와
  BIOS(`bootsect`) PC 모두에서 부팅됩니다. 파티션 크기는 `USB_PART_MB`(MB)이며,
  비워 두면(기본값) 디스크 전체를 사용합니다.
- 빌드 26300 이전 Windows는 32GB를 넘는 FAT32 포맷을 할 수 없습니다(26300
  이후는 2TB까지). 이런 빌드 PC에서 더 큰 USB를 쓰고 `USB_PART_MB`가 비어 있으면
  `make_media.bat`은 디스크를 지우기 **전에** 중단합니다.
- **빌드 26300 이전 빌드 PC에서는 권장:** ISO(`1`)를 만든 뒤
  [Rufus](https://rufus.ie)로 USB에 쓰세요. Rufus는 용량과 관계없이 디스크 전체를
  FAT32로 포맷하며, UEFI와 BIOS PC 모두에서 부팅됩니다. Rufus에서 USB 드라이브와
  `media_out\DVT_media.iso`를 선택하고, 파일 시스템은 **FAT32**로 둔 채 ISO 이미지
  모드로 쓰면 됩니다. `config` 폴더도 ISO에 들어 있으므로 `2`로 만든 USB와 같은
  파일이 들어가며, 이후에는 `3`으로 갱신할 수 있습니다.
- 이런 빌드 PC의 다른 방법: `USB_PART_MB=32000`(나머지 공간은 사용하지 않음) 또는
  `USB_FS=exfat`(디스크 전체, 하지만 많은 UEFI 펌웨어가 exFAT로 부팅하지 못함).
- `make_media.bat`은 유형이 **USB**인 디스크에만 쓰며, `%SystemDrive%`가 있는
  디스크에는 절대 쓰지 않고, `YES`를 입력해야 진행합니다.

### WinPE에서의 동작

- **재부팅 반복**: 복원 후 PC가 다시 USB로 부팅되어도 입력 화면에서 멈출 뿐,
  입력 없이는 아무것도 지우지 않습니다. ISO는 키 입력을 묻지 않는 UEFI 부트
  섹터(`efisys_noprompt.bin`을 `efisys.bin`으로 보관)를 사용하므로, CD를 넣어 둔
  채 재부팅하면 다시 CD로 부팅됩니다 — 복원 후 카운트다운 동안 CD를 빼세요.
- 다운로드 드라이브는 자동으로 선택합니다(`get_target.bat`): 여유 공간이 가장
  큰 고정 볼륨, 없으면 `T:`. 부팅 미디어는 USB 하드디스크라도 쓰지 않습니다.

### 유지 관리

`Media\pe`에 있는 `pe` 스크립트의 사본은 `pe` 쪽이 바뀌면 직접 갱신해야 합니다.

## 설정

스크립트가 아니라 다음 파일의 값을 수정하세요.

| 파일 | 사용처 |
|---|---|
| `host\config.cmd` | 클라이언트 PC(`make_boot.bat`)와 빌드 PC(`make_pe.bat`) |
| `pe\config.cmd` | 클라이언트 로컬부팅의 WinPE |
| `Media\config.cmd` | `make_media.bat` (`host\config.cmd`를 먼저 불러옴) |
| `Media\pe\config.cmd` | USB / CD 미디어의 WinPE |

### `host\config.cmd` (클라이언트 PC와 빌드 PC)

| 변수 | 기본값 | 설명 |
|---|---|---|
| `WORK_DIR` | `C:\temp` | 클라이언트 PC의 작업 폴더 |
| `BOOT_WIM` | `%WORK_DIR%\boot\boot.wim` | 수정하고 부팅할 WinPE 이미지 |
| `TORRENT` | `%WORK_DIR%\DVT_backup.torrent` | 이미지에 넣을 토렌트 |
| `NETDRV_EXCLUDE` | `Realtek` | 정규식. 일치하는 네트워크 드라이버는 추출하지 않음. 비우면 모두 추출. Realtek은 WinPE용 드라이버를 `drivers\`에 넣어 사용([Realtek 랜카드](#realtek-랜카드) 참고) |
| `BOOT_MOUNT_DIR` | `%SystemDrive%\DVT_BootMount` | 로컬 마운트 폴더 |
| `TAG_FILE` | `DVT.tag` | 지울 디스크 표식 파일 (`pe\config.cmd`와 같아야 함) |
| `BOOT_ENTRY_NAME` | `DVT WinPE` | 부팅 메뉴 항목 이름 |
| `BCD_CLEANUP_MODE` | `2` | 부팅 항목 삭제 방식: `1` WinPE에서, `2` 다음 Windows 부팅 시(예약 작업), `0` 삭제 안 함 |
| `REBOOT_DELAY_SEC` | `10` | WinPE로 재시작하기 전 대기 시간 |
| `ADK_PE_DIR`, `PE_LANG` | ADK amd64, `en-us` | `winpe.wim` 원본 위치 |
| `BUILD_LOCAL` | `%SystemDrive%\WinPE_LocalBuild` | 로컬 빌드 폴더 |
| `PE_SCRATCH_MB` | `512` | WinPE 스크래치 공간 |

### `pe\config.cmd` (WinPE, 클라이언트 로컬부팅)

| 변수 | 기본값 | 설명 |
|---|---|---|
| `DL_NAME` | `DVT_backup` | 토렌트 안의 최상위 폴더 |
| `WIM_NAME` | `backup.wim` | 그 폴더 안의 이미지 파일 |
| `FORCE_DISK` | *(비어 있음)* | 지울 디스크 번호. 비우면 자동 판별 |
| `AUTO_DISK_FALLBACK` | `1` | RAW 볼륨 / 단일 디스크 대체 규칙 허용 |
| `TDRV`, `SDRV` | `T`, `S` | 새 Windows·시스템 파티션의 드라이브 문자 |
| `EFI_SIZE_MB`, `MSR_SIZE_MB`, `BIOS_SYS_SIZE_MB` | `260`, `16`, `500` | 파티션 크기 |
| `NET_MASK` | `255.255.255.0` | `ip.txt`에 서브넷 줄이 없을 때 쓰는 서브넷 마스크 |
| `NET_DNS1`, `NET_DNS2` | `8.8.8.8`, `8.8.4.4` | 고정 IP의 DNS |
| `NET_TEST_HOST` | *(비어 있음)* | 추가로 응답해야 하는 호스트 (트래커나 시더 권장) |
| `SET_IP_RETRIES`, `SET_IP_RETRY_SEC` | `3`, `10` | 고정 IP: 게이트웨이에 닿는 어댑터가 없으면 이 시간(초) 후 모든 어댑터를 이 횟수만큼 다시 시도 |
| `DHCP_WAIT_TRIES` | `30` | DHCP 대기 횟수 (2초 단위) |
| `CHECK_FILE` | `dvt_check.txt` | 시더 점검용 파일 |
| `SEEDER_TIMEOUT_SEC` | `60` | 시더 점검 1회당 제한 시간 |
| `SEEDER_TRIES_1G`, `SEEDER_TRIES_100` | `2`, `5` | 시더 점검 시도 횟수: 1 Gbps 이상 / 100 Mbps 이하(속도를 모를 때 포함). `make_boot.bat`이 링크 프로필을 이미지 안의 `link_profile.txt`에 기록 |
| `SEEDER_EXTRA_OPTS` | *(비어 있음)* | 시더 점검 시 추가할 aria2c 옵션 |
| `BCD_LOCALE` | `ko-kr` | `bcdboot`에 전달할 로캘 |
| `FAIL_REBOOT_SEC`, `DONE_REBOOT_SEC` | `10`, `5` | 재부팅 대기 시간 |

### `Media\config.cmd` (make_media.bat)

| 변수 | 기본값 | 설명 |
|---|---|---|
| `MEDIA_LABEL` | `DVT` | ISO와 USB 드라이브의 볼륨 레이블 |
| `USB_FS` | `fat32` | 새 USB 드라이브의 파일 시스템: `fat32` 또는 `exfat` |
| `USB_PART_MB` | *(비어 있음)* | USB 파티션 크기(MB). 비우면 디스크 전체 |
| `MEDIA_OUT_DIR` | 빌드 폴더의 `media_out` | 결과 폴더 (`boot.wim`, `DVT_media.iso`) |

### `Media\pe\config.cmd` (WinPE, USB / CD 미디어)

`FORCE_DISK`와 `AUTO_DISK_FALLBACK`(작업자가 디스크를 고르므로)을 제외하면
`pe\config.cmd`와 같은 변수를 가지며, 다음 변수가 추가됩니다.

| 변수 | 기본값 | 설명 |
|---|---|---|
| `DHCP_ENABLE` | `0` | `0` / 없음 = 고정 IP(`ip.txt`) 우선, `1` = DHCP 우선 |
| `DHCP_FIRST_TRIES` | `10` | `DHCP_ENABLE=1`이고 `ip.txt`가 있을 때 고정 IP로 넘어가기 전 DHCP 대기 횟수(2초 단위) |
| `DHCP_FALLBACK_CONFIRM` | `0` | 고정 IP 우선에서 고정 IP 실패·DHCP 성공 시: `0` = 묻지 않고 DHCP로 진행, `1` = Y/N 확인 |
| `LINK_FALLBACK` | `100` | `link.exe`가 없거나 실패할 때 쓸 프로필 |
| `OCTET_MIN`, `OCTET_MAX` | `1`, `254` | 허용하는 IP 끝자리 |
| `MEDIA_CONFIRM` | `1` | 지우기 전에 Y/N 확인 |
| `DONE_REBOOT_SEC` | `15` | 미디어를 뺄 시간 |

### aria2 프로필

`pe\aria2.conf.100`과 `pe\aria2.conf.1G`(미디어는 `Media\config\aria2.conf.*`)는
일반 aria2 설정 파일입니다. 두 프로필 모두 다운로드 후 최대 60분간 시딩하고,
DHT/PEX/LPD를 끄며, 다운로드가 끝나면 `start_restore.bat`을 실행합니다. 1 Gbps
프로필은 더 많은 피어를 허용하고, 업로드 제한을 없애며, 디스크 캐시를 사용합니다.

## 스크립트 목록

### 빌드 PC

| 스크립트 | 역할 |
|---|---|
| `make_pe.bat` | ADK `winpe.wim`으로 `boot\boot.wim` 생성(스크립트, 도구, 드라이버, Num Lock 켜기) 후 host 스크립트를 `boot\`에 복사 |
| `make_test_pe.bat` | 테스트 이미지 `boot_test\boot.wim` 생성(네트워크·게이트웨이·시더 점검, `<ip>.txt` FTP 업로드, 디스크 접근 없음) |
| `make_media.bat` | ADK `winpe.wim`과 `Media\pe`로 `media_out\boot.wim`을 만든 뒤 ISO, 새 USB 드라이브, USB 드라이브 갱신 중 하나를 수행(`iso`, `usb`, `update`) |

### 클라이언트 PC (Windows, 클라이언트 로컬부팅)

| 스크립트 | 역할 |
|---|---|
| `make_boot.bat` | 주 스크립트: PC를 준비하고 WinPE로 재시작 (`C:\temp\boot`에서 실행) |
| `get_host_ip.bat` | 기본 경로 어댑터 확인, 고정 IP일 때만 `ip.txt`(ip, 서브넷, 게이트웨이) 기록 |
| `get_link_speed.bat` | 링크 속도 → aria2 프로필과 콘솔 색 |
| `export_net_drivers.bat` | 연결된 물리 랜카드의 드라이버를 `pnputil`로 추출 |
| `prepare_mount_dir.bat` | 남아 있는 마운트를 버리고 마운트 폴더가 비었는지 확인 |
| `set_bcd.bat` | `boot.wim`용 램디스크 부팅 항목을 만들고 다음 부팅에만 사용 |
| `show_ip.bat` | IP 주소의 마지막 자리를 큰 글씨로 표시 |

### WinPE (공통)

| 스크립트 | 역할 |
|---|---|
| `get_firmware.bat` | UEFI / BIOS 판별 |
| `get_ip.bat` / `set_ip.bat` | DHCP / 고정 IP |
| `check_gateway.bat` | 기본 게이트웨이에 ping |
| `check_seeder.bat` | `dvt_check.txt`만 내려받아 크기 확인 (0바이트 파일은 거부) |
| `make_disk.bat` | 디스크를 지우고 GPT 또는 MBR 파티션 생성 |
| `get_target.bat` | 다운로드 드라이브 선택 (여유 공간이 충분한 다른 로컬 볼륨, 없으면 `T:`. 미디어에서는 부팅 미디어 제외) |
| `start_restore.bat` | aria2c가 호출. `restore.bat`을 별도 창에서 한 번만 실행 |
| `restore.bat` | 이미지·드라이버·부팅 파일 적용, `setpc.bat` 등록, 정리 후 재부팅 |
| `ping_host.bat`, `wait.bat` | 보조 스크립트 (WinPE에는 `timeout.exe`가 없음) |

### WinPE, 클라이언트 로컬부팅 전용 (`pe\`)

| 스크립트 | 역할 |
|---|---|
| `startnet.cmd` | WinPE 시작 시 `start_dvt.bat` 실행 |
| `start_dvt.bat` | 주 흐름: 점검, 네트워크, 디스크 삭제, 다운로드 |
| `get_disk.bat` | 지울 디스크 판별 |

### WinPE, USB / CD 미디어 전용 (`Media\pe\`)

| 스크립트 | 역할 |
|---|---|
| `startnet.cmd` | 부팅 미디어를 찾아 `<미디어>\config`를 `X:\restore`로 복사하고 `start_media.bat` 실행 |
| `start_media.bat` | 주 흐름: 네트워크 순서, 입력, 점검, 디스크 삭제, 다운로드 |
| `get_input.bat` | 디스크 목록, IP 끝자리와 디스크 번호 입력 |
| `getdiskinfo.bat` | 디스크 목록 |
| `link.exe` | 링크 속도 → `aria2.conf` |

## 문제 해결

| 증상 | 확인할 것 |
|---|---|
| 몇 초 뒤 기존 Windows로 다시 부팅됨 | 클라이언트 로컬부팅: 디스크 삭제 전 점검이 실패한 것입니다. 화면 메시지에 원인(디스크, 네트워크, 게이트웨이, 시더)이 나옵니다. |
| "The target disk could not be determined" | `DVT.tag`가 없거나 여러 디스크에 있습니다. `make_boot.bat`을 다시 실행하거나 `FORCE_DISK`를 지정하세요. |
| "No seeder is reachable" | 트래커와 시더가 실행 중인지, 토렌트에 `dvt_check.txt`가 있는지 확인하세요. 로그: `%TEMP%\dvt_seeder.log` |
| "The seeder check file in the torrent is empty" | 토렌트 안의 `dvt_check.txt`가 0바이트 파일입니다. 내용을 넣고 토렌트를 다시 만드세요. |
| WinPE에서 네트워크가 안 됨 | 랜카드 드라이버가 없을 수 있습니다. `NETDRV_EXCLUDE`를 확인하거나, 드라이버를 `drivers\`에 넣고 다시 빌드하세요. Realtek은 WinPE용 드라이버가 필요합니다. |
| Realtek 랜카드 PC에서 다운로드 중 연결이 끊김 | WinPE에 Windows용 Realtek 드라이버가 들어갔을 수 있습니다. `NETDRV_EXCLUDE=Realtek`을 유지하고, Realtek의 WinPE용 드라이버를 `drivers\`에 넣어 다시 빌드하세요. |
| 미디어: "The IP settings in ...\config\ip.txt are invalid" | 3행 형식을 확인하고 `ip.txt`를 ANSI / ASCII로 저장하세요. |
| 미디어: 복원 후 다시 미디어로 부팅됨 | 카운트다운 동안 USB / CD를 빼세요. 입력 없이는 아무것도 지우지 않습니다. |
| `make_media.bat`이 큰 USB를 지우기 전에 중단됨 | 빌드 26300 이전 PC에서는 32GB를 넘는 FAT32를 만들 수 없습니다. Rufus, `USB_PART_MB`, `USB_FS=exfat` 중 하나를 쓰세요([USB 드라이브와 ISO](#usb-드라이브와-iso) 참고). |
| `make_boot.bat`에서 마운트 폴더가 비어 있지 않다고 나옴 | `dism /Cleanup-Mountpoints`를 실행하고 폴더를 비우세요. |
| 디스크 삭제 후 복원 실패 | 빨간 메시지를 확인하세요. 원인을 해결한 뒤 "DVT Console" 창에서 `X:\restore\restore.bat`을 다시 실행하거나, 키를 눌러 재부팅하세요. |

WinPE에서는 문제 해결용으로 최소화된 "DVT Console" 창이 함께 열립니다.
diskpart 로그는 `%TEMP%\dvt_make_disk*.log`에 저장됩니다.

## 제한 사항

- x64 전용입니다(ADK `amd64` WinPE).
- IPv4만 지원합니다.
- `backup.wim`의 첫 번째 이미지(1번 인덱스)만 적용합니다.
- 클라이언트 로컬부팅 방식은 `make_boot.bat`을 실행할 수 있도록 클라이언트 PC에 동작하는
  Windows가 있어야 합니다. Windows가 없는 PC는 USB / CD 미디어를 사용하세요.

## 외부 도구

DVT에는 다음 도구가 포함되어 있지 않습니다. 각 공식 사이트에서 내려받으세요.
각 도구는 고유한 라이선스로 배포됩니다.

- [aria2](https://github.com/aria2/aria2) — BitTorrent 다운로드
- [wimlib](https://wimlib.net/) — WIM 이미지 적용
- [NirCmd](https://www.nirsoft.net/utils/nircmd.html) — aria2c 종료
- [Windows ADK 및 WinPE 추가 기능](https://learn.microsoft.com/windows-hardware/get-started/adk-install) — Microsoft
- [Rufus](https://rufus.ie) — 선택 사항, ISO를 USB 드라이브에 쓰기

## 라이선스

DVT는 [BSD 3-Clause License](LICENSE)로 배포됩니다.

위의 외부 도구는 DVT에 포함되지 않으며, 각자의 라이선스를 따릅니다.

## 면책 조항

DVT는 설계상 디스크를 지웁니다. 사용에 따른 책임은 사용자에게 있으며, 지워져도
괜찮은 하드웨어에서 먼저 테스트하세요.
