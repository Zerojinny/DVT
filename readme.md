# Deploy via torrent (DVT)

DVT는 토렌트 네트워크를 이용해 Windows 이미지(WIM)를 다수의 클라이언트에
배포하고 복원하는 도구입니다. [확인: 대상 환경 예) 동일 LAN의 교육장·사내 PC]

> ⚠️ **경고: 이 도구는 디스크를 초기화합니다.**
> - 대상 디스크의 **모든 파티션과 데이터가 삭제**됩니다. (디스크 전체를 `clean` 한 뒤
>   GPT로 다시 구성하므로, 같은 디스크의 D: 등 다른 파티션도 모두 사라집니다.)
> - 초기화는 이미지 다운로드 **전에** 수행됩니다. 다운로드나 복원 도중
>   실패하거나 전원이 차단되면 클라이언트는 **부팅 불가 상태**가 되며,
>   복구 도구(별도 제공 예정) 또는 외부 부팅 매체가 필요합니다.
> - `makeboot.bat`는 마지막에 **키 입력 후 10초 뒤 PC를 강제 재부팅**(`shutdown /r /f`)합니다.
>   실행 전에 열려 있는 작업을 모두 저장하십시오.
> - 재부팅 전에 반드시 백업하고, 시더가 정상 동작하는지 확인하십시오.

## 1. 구성 및 라이선스

DVT 본체는 The 3-Clause BSD License를 따릅니다. (`\license\license.txt`)

외부 프로그램은 각각 별도 라이선스이며 `license` 폴더의 파일을 참고하십시오.

- aria2c — https://aria2.github.io/
- NirCmd — https://www.nirsoft.net/utils/nircmd.html
- wimlib — https://wimlib.net/
- qBittorrent — https://www.qbittorrent.org/

각 스크립트의 역할은 [부록 A](#부록-a-파일-구성과-스크립트-역할)를 참고하십시오.

## 2. 요구사항

**작성용 PC (WinPE 생성)**

- Windows ADK 에 대한 Windows PE 추가 기능
  (기본 설치 경로 `C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64`
  를 사용하며, 경로가 다르면 `makePE.bat`의 `srdir`를 수정해야 합니다.)
- Windows가 `C:`에 설치되어 있어야 합니다. (`dism.exe` 경로가 `C:\Windows\System32\dism.exe`로 고정)
- 관리자 권한, 그리고 `%SystemDrive%\WinPE_LocalBuild`에 쓸 수 있는 충분한 로컬 여유 공간
- WinPE는 **en-us** `winpe.wim`을 기반으로 만들어집니다.

**클라이언트**

- Windows 10 이상 64비트 (PowerShell `Get-NetAdapter`, `pnputil /export-driver`, DISM 사용)
- **UEFI 부팅 전용**: 대상 디스크를 GPT로 변환하고 EFI 시스템 파티션(256MB)을 만듭니다.
  레거시 BIOS(MBR) 환경은 지원하지 않습니다.
- **유선 LAN** 환경을 전제로 합니다. (기본 WinPE는 Wi-Fi를 지원하지 않음)
- 관리자 권한으로 `makeboot.bat` 실행 가능해야 함
- RAM / 디스크 여유 공간: [확인: 최소 RAM, `C:\temp\boot` 및 이미지 크기에 따른 여유 공간]
- BitLocker 사용 PC: [확인: BCD 변경 시 복구 키 요구 여부 — 사전에 해제 권장]
- 클라이언트의 DISM이 WinPE(ADK) 이미지 버전보다 낮으면 마운트·드라이버 추가가 실패할 수 있습니다.
  [확인]

**네트워크**

- 클라이언트의 **기본 게이트웨이가 ping에 응답**해야 합니다. (미응답 시 중단)
- 클라이언트에서 시더(및 트래커)에 접근 가능해야 합니다.
- **DHT·PEX·LPD가 모두 비활성화**되어 있으므로, 토렌트에 클라이언트가 접근 가능한
  **트래커 주소(announce)가 반드시 포함**되어야 합니다.


## 3. 배포 흐름

### 3-1. 사전 준비

Windows ADK에 대한 Windows PE 추가 기능은 본 프로그램에 포함되어 있지 않습니다.
Microsoft 공식 페이지에서 다운로드하여 미리 설치하십시오.

https://learn.microsoft.com/ko-kr/windows-hardware/get-started/adk-install

### 3-2. WinPE 생성

`makePE.bat`를 관리자 권한으로 실행하면 `boot` 폴더에 `boot.sdi`와
`boot.wim`이 생성됩니다.

`makePE.bat`와 같은 폴더에는 다음이 준비되어 있어야 합니다.

| 폴더 / 파일 | 용도 |
|---|---|
| `system32\` | WinPE의 `\Windows\System32`로 복사 (`startnet.cmd` 등) |
| `pe_files\` | WinPE의 `X:\restore\`로 복사 (DVT 스크립트, `aria2c.exe`, `wimlib-imagex.exe`와 필요한 DLL, `aria2.conf.100`, `aria2.conf.1G`) |
| `nircmd-x64\nircmd.exe` | WinPE `System32`로 복사 (필수, 없으면 중단) |
| `drivers\` | (선택) 모든 클라이언트 공통으로 넣을 드라이버. 하위 폴더 포함 주입 |
| `source\` | 자동 생성. ADK의 `winpe.wim`, `boot.sdi` 사본 보관 |

동작 요약: ADK의 `winpe.wim`을 로컬 작업 폴더(`%SystemDrive%\WinPE_LocalBuild`)에서
마운트 → ScratchSpace 512MB 설정 → 파일 복사 → 레지스트리(NumLock 초기 상태) 설정 →
드라이버 주입 → 저장 후 `boot\boot.wim`으로 이동합니다. 작업이 로컬 드라이브에서
이루어지므로 OneDrive 등 동기화 폴더 안에서 실행해도 마운트 폴더가 꼬이지 않습니다.
(최종 `boot` 폴더만 `makePE.bat` 위치에 생성)

> 중간에 실패한 뒤 재실행할 때 이미지가 마운트된 채로 남아 있으면
> `dism /Cleanup-Wim`을 실행하고, 필요하면 `%SystemDrive%\WinPE_LocalBuild\workdir`
> 폴더를 삭제한 뒤 다시 실행하십시오.

### 3-3. 배포 이미지 및 토렌트 생성

`DVT_backup` 폴더 구성은 다음과 같습니다.

| 경로 | 필수 | 설명 |
|---|---|---|
| `DVT_backup\backup.wim` | 필수 | 배포할 이미지. **인덱스 1**이 적용됩니다. UEFI/GPT로 부팅 가능한 Windows 이미지여야 합니다. |
| `DVT_backup\dvt_check.txt` | 필수 | 시더 확인용 작은 텍스트 파일(수 KB) |
| `DVT_backup\drivers\` | 선택 | 있으면 복원 직후 DISM으로 `/Recurse` 주입 |
| `DVT_backup\files\` | 선택 | 있으면 내용물을 복원된 OS의 `\temp\`로 이동 |
| `DVT_backup\files\setpc.bat` | 선택 | 있으면 복원된 OS의 **첫 로그인 시 자동 실행**(RunOnce 등록) |

1. 배포할 `backup.wim`과 필요한 파일을 위 구성대로 `DVT_backup` 폴더에 복사합니다.
2. **시더 확인용 파일 `dvt_check.txt`(수 KB의 작은 텍스트 파일)를 `DVT_backup`
   폴더에 함께 넣습니다.** 이 파일은 디스크 초기화 전에 시더 접속을
   확인하는 데 사용되며, 토렌트에 포함되어 있지 않으면 확인이 실패합니다.
3. `DVT_backup` 폴더에 대한 토렌트 파일을 생성합니다. (기본 파일명 `DVT_backup.torrent`)
   - 토렌트의 **최상위 폴더 이름이 `DVT_backup`** 이어야 합니다. (복원 스크립트가
     `<드라이브>:\DVT_backup\backup.wim` 경로를 찾습니다.)
   - **클라이언트가 접근 가능한 트래커를 반드시 지정**합니다. (DHT/PEX/LPD 비활성)
4. 시더에서 `DVT_backup` 폴더를 시딩합니다. (시딩 방법은 별도 문서 참조)

> 복원되는 이미지에는 `\temp` 폴더가 있는 것을 권장합니다. 복원 스크립트가 IP 정보(`ip.txt`)와
> `files` 폴더의 내용을 `\temp`로 복사·이동하는데, 폴더가 없으면 실패할 수 있습니다. [확인]

### 3-4. 클라이언트 배포

**재부팅 전 점검 (필수)**

- [ ] 시더와 트래커가 실행 중이며 클라이언트에서 접근 가능한가
- [ ] 대상 디스크의 중요 데이터를 백업했는가
- [ ] 열려 있는 작업을 모두 저장했는가 (`makeboot.bat`가 마지막에 강제 재부팅)
- [ ] 대상이 아닌 디스크 중 **이동식 디스크(USB, SD 카드 등)** 가 연결되어 있지 않은가
      (`DVT.tag`를 찾지 못한 경우 파일시스템이 RAW인 첫 볼륨이 대상이 되므로, 포맷되지 않은
      이동식 매체는 반드시 분리)
- [ ] 다른 로컬 디스크가 있다면, 그 디스크에 **`\DVT_backup` 폴더가 없는지**(다운로드 전에 삭제됨) 확인했는가
- [ ] 이전 실행에서 남은 `C:\temp\ip.txt`가 없는가 (DHCP 환경에서도 이전 파일이 그대로
      복사되어 고정 IP로 설정될 수 있음)

**절차**

1. 클라이언트에 다음과 같이 파일을 배치합니다. (`makeboot.bat`가 이 경로를 사용합니다.)

   ```
   C:\temp\
   ├─ backup.torrent
   └─ boot\
      ├─ boot.wim, boot.sdi            ← makePE.bat 결과
      ├─ makeboot.bat, setbcd.bat
      └─ getip.bat, getlinkspeed.bat, getnetdrv.bat, printip.bat
   ```
   [확인: `makePE.bat`는 위 보조 스크립트를 `boot` 폴더에 복사하지 않으므로, 배포 패키지에서 함께 넣는지 확인]

   - **클라이언트마다 원본(가공 전) `boot` 폴더를 새로 복사**하십시오. 한 번 `makeboot.bat`를
     실행한 `boot.wim`에는 이미 `aria2.conf`가 만들어져 있어 다시 실행하면 실패합니다.
2. 클라이언트에서 `makeboot.bat`를 실행합니다. 이 스크립트는 다음을
   수행합니다.
   - 시스템 드라이브의 `DVT.tag` 마커 생성 (다른 드라이브의 기존 `DVT.tag`는 먼저 삭제)
   - **고정 IP인 경우에만** 현재 IP를 `C:\temp\ip.txt`에 저장 (DHCP이면 저장하지 않음)
   - 링크 속도를 감지하여 aria2 설정 선택 (3-5절 참조)
   - 연결된 물리 어댑터의 **네트워크 드라이버를 추출**(`boot\netdrv`).
     **Realtek 어댑터는 제외**되며, 이 경우 드라이버 주입을 건너뛰고 WinPE 기본 드라이버에 의존합니다.
   - 추출한 드라이버·`ip.txt`·`C:\temp\backup.torrent`를 `boot.wim`에 통합
   - BCD에 WinPE 부팅 항목을 추가하고 **다음 부팅 1회만** WinPE로 부팅하도록 설정
     (부팅 메뉴 대기 시간도 5초로 변경됨)
   - 완료 화면에 IP 마지막 자리를 크게 표시하고, 키 입력 후 **10초 뒤 자동 재부팅**
3. 재부팅되면 다음 순서로 자동 진행됩니다.

   | 단계 | 내용 | 비고 |
   |---|---|---|
   | 0 | WinPE 부팅(`wpeinit`), 방화벽 해제, 고성능 전원 관리, 문제 확인용 최소화 명령 창 열기 | |
   | 1 | **대상 디스크 탐색** (아직 초기화하지 않음) | 4절 규칙. 대상이 없으면 오류 메시지 후 **5초 뒤 자동으로** 기존 OS로 재부팅 |
   | 2 | IP 설정 | `ip.txt`가 있으면 고정 IP, 없으면 DHCP (3-6절). DHCP를 약 1분 기다려도 실패하면 **아무 키나 누르면** 기존 OS로 재부팅 |
   | 3 | 게이트웨이 ping 확인 | 실패하면 **디스크 초기화 없이** 10초 뒤 기존 OS로 재부팅 |
   | 4 | 시더 접속 확인 (`check_seeder.bat`) | 확인용 파일 `dvt_check.txt`를 받아 봄. 실패하면 **디스크 초기화 없이** 10초 뒤 기존 OS로 재부팅 |
   | 5 | **대상 디스크 초기화** (`makedisk.bat`) | 이 시점부터 기존 OS 사용 불가. GPT 변환, EFI(FAT32, 256MB, `S:`) + Windows(NTFS, 나머지, `T:`) |
   | 6 | 이미지 다운로드 | 4절의 규칙으로 고른 드라이브의 기존 `\DVT_backup`을 지우고 aria2c로 다운로드. 진행 상황 표시. 시더 접속 불가 시 접속될 때까지 무한 대기 |
   | 7 | WIM 복원 (`restore.bat`) | 다운로드 완료 시 자동 실행. 3-7절 참조 |
   | 8 | 재부팅 | 복원된 OS로 부팅 |

> `makeboot.bat`가 만든 `boot.wim`에는 해당 클라이언트의 IP·드라이버 정보가
> 들어 있습니다. **클라이언트마다 별도로 실행**해야 하며, 가공된 `boot.wim`을
> 다른 PC에 복사하거나 외부로 반출하지 마십시오.

> 시더 확인 실패 등으로 기존 OS에 돌아오면, WinPE 부팅 항목은 기존 OS의 다음 부팅 때
> 작업 스케줄러 작업(`WinPE_BCD_Cleanup`)이 자동으로 삭제합니다.

### 3-5. 링크 속도에 따른 aria2 설정

`getlinkspeed.bat`가 사용 중인 첫 번째 물리 어댑터의 링크 속도를 읽어 설정 파일을 고릅니다.
(어댑터가 여러 개이면 기본 경로를 쓰는 어댑터가 아닌 다른 어댑터가 선택될 수 있습니다. [확인])

| 링크 속도 | 설정 파일 | 주요 설정 |
|---|---|---|
| 1 Gbps 이상 | `aria2.conf.1G` | 업로드 제한 없음, 최대 피어 100, 디스크 캐시 128MB, `falloc` |
| 100 Mbps / 10 Mbps | `aria2.conf.100` | 업로드 제한 8M, 최대 피어 30, `file-allocation=none` |
| 판별 실패 | `aria2.conf.100` | `getlinkspeed.bat`가 오류를 반환하면 `makeboot.bat`가 중단됨 |

공통: DHT·PEX·LPD 비활성, 다운로드 완료 시 `start_restore.bat` 실행, 완료 후 시딩 `seed-time=60`(분).
클라이언트도 다운로드 중에 다른 클라이언트에게 업로드(피어 공유)합니다.
완료 후에는 복원 스크립트가 `aria2c.exe`를 종료하므로 시딩은 이어지지 않습니다.

`makeboot.bat` 완료/실패 화면의 배경색은 링크 속도를 나타냅니다. (1G 이상 초록, 100M 회색,
10M 빨강) 실패 화면도 빨강이므로, 빨간 화면에서는 메시지를 확인하십시오.

### 3-6. IP 설정 규칙

- **고정 IP 클라이언트** (`ip.txt` 있음): DNS `8.8.8.8` / `8.8.4.4`로 **고정 적용**합니다. 
- 연결된 어댑터를
  차례로 시도하여 게이트웨이에 ping이 되는 어댑터를 선택합니다.
- **DHCP 클라이언트** (`ip.txt` 없음): DHCP로 받은 기본 경로의 IP를 사용합니다.
- 고정 IP 적용에 실패하면 해당 어댑터를 DHCP로 되돌립니다. 이후 단계는 계속 진행되므로,
  DHCP로 게이트웨이가 확보되면 **의도한 고정 IP가 아닌 DHCP 주소로 배포가 진행될 수 있습니다.**
  

### 3-7. 복원 단계 동작

다운로드가 끝나면 `restore.bat`가 다음을 수행합니다. 각 단계의 성공 여부는 검사하지 않고
끝까지 진행합니다.

1. `wimlib-imagex`로 `backup.wim`의 인덱스 1을 `T:`에 적용
2. `DVT_backup\drivers\`가 있으면 DISM으로 드라이버 주입
3. `bcdboot`로 `S:`(EFI)에 부팅 파일 생성 (로캘 `ko-kr` 고정)
4. `aria2c.exe` 종료, `backup.wim` 삭제
5. `X:\restore\ip.txt`가 있으면 `T:\temp\ip.txt`로 복사 (복원된 OS에서 `C:\temp\ip.txt`)
6. `DVT_backup\files\`의 파일을 `T:\temp\`로 이동, `T:\temp\setpc.bat`이 있으면 첫 로그인 시
   실행되도록 RunOnce 등록
7. `DVT_backup` 폴더 삭제 후 재부팅

### 시더 접속 확인에 대하여

`check_seeder.bat`는 초기화 직전에 토렌트 안의 `dvt_check.txt`만 내려받아
시더에 실제로 접속할 수 있는지 확인합니다. 다운로드 속도가 0인 상태가 제한 시간(기본 60초)
동안 지속되면 실패로 보고, **총 2회(최초 1회 + 재시도 1회)** 시도한 뒤 실패로 처리합니다.

- 이 확인은 **확인 시점에** 시더가 접속 가능하다는 것만 보장합니다.
  초기화 이후 다운로드 도중 시더가 꺼질 수 있으므로 5절의 장애 대응을
  참고하십시오.
- 본 다운로드에 DHT·트래커 관련 옵션을 사용한다면 `check_seeder.bat`의
  `EXTRA_OPTS`에도 같은 옵션을 지정해야 확인 결과가 의미를 갖습니다.
  (확인 단계는 `--enable-dht=false`만 적용하며 `aria2.conf`는 사용하지 않습니다.)

| 반환 코드 | 의미 |
|---|---|
| 0 | 시더 접속 성공 |
| 1 | 다운로드 실패 또는 시간 초과 |
| 2 | `aria2c.exe` 또는 토렌트 파일 없음 |
| 3 | 토렌트에 `dvt_check.txt`가 포함되어 있지 않음 |

## 4. 대상 디스크 선택 규칙

**초기화 대상 디스크**는 `get_disk.bat`가 다음 순서로 **하나만** 고르며, 선택된 디스크는
**디스크 전체가 초기화**됩니다.

1. 루트에 `DVT.tag`가 있는 드라이브를 포함한 디스크
   (`makeboot.bat` 실행 시 **시스템 드라이브(보통 C:)** 루트에 생성. 파일명은 `duhelp.tag`가 아니라 `DVT.tag`)
2. 1번이 없을 때만: 파일시스템이 **RAW**인 **첫 번째 볼륨**을 포함한 디스크

- **검색 범위**: 드라이브 문자 `C`~`W`를 검색합니다. 이 단계는 **이동식 디스크(USB 등)를
  제외하지 않습니다.** RAW 규칙은 포맷되지 않은 USB/SD 카드도 선택할 수 있으므로 분리하십시오.
- **복수 디스크**: 사양을 알고 있는 PC를 대상으로 하는 것을 전제로 합니다.
  `DVT.tag`가 있으면 항상 그 디스크가 선택되고, RAW 규칙에서는 목록상 첫 RAW 볼륨의 디스크 하나만
  선택됩니다. 그래도 사전에 디스크 구성을 확인하십시오.
- **대상 디스크 없음**: 오류 메시지를 출력하고, **5초 뒤 자동으로** 기존 OS로 재부팅합니다.

**다운로드 드라이브 선택** (`get_target.bat`, 초기화 이후)

- 이미지는 `T:`(새 Windows 파티션)이 아니라, **`T:`·`S:`·`X:`를 제외한 로컬 고정 디스크 중
  여유 공간이 가장 큰 드라이브**에 내려받습니다. 그 드라이브의 기존 `\DVT_backup` 폴더와
  `DVT_backup.aria2`는 **삭제**됩니다. 해당하는 드라이브가 없으면(단일 디스크 PC) `T:`에
  내려받습니다.
- 단일 디스크 PC에서는 `T:`에 **이미지 크기 + 복원된 OS 크기**를 합친 여유 공간이 필요합니다.
  부족하면 다운로드 또는 복원이 실패합니다. [확인: 이미지 크기 기준 필요 용량]

## 5. 장애 시 대응

| 상황 | 동작 | 복구 방법 |
|---|---|---|
| 대상 디스크 없음 | 오류 메시지 출력 후 5초 뒤 자동으로 이전 OS로 재부팅 | `DVT.tag` 파일 또는 디스크 구성을 확인 |
| DHCP IP 획득 실패 (IP 설정 단계) | 약 1분 대기 후 "Press any key to Reboot!" 표시, 키 입력 시 이전 OS로 재부팅. 디스크는 초기화하지 않음 | 네트워크 환경(DHCP, 케이블)을 점검한 뒤 재시도 |
| 고정 IP 적용 실패 | 어댑터를 DHCP로 되돌리고 다음 단계로 진행 | `ip.txt`에서 ip, subnet, gateway를 불러옴 |
| 게이트웨이 응답 없음 | 디스크를 초기화하지 않고 10초 뒤 이전 OS로 재부팅 | 네트워크 환경을 점검한 뒤 재시도 |
| 시더 접속 확인 실패 (초기화 이전) | 디스크를 초기화하지 않고 10초 뒤 이전 OS로 재부팅 | 시더·트래커 실행 여부, 방화벽, `dvt_check.txt` 포함 여부를 점검한 뒤 재시도 |
| 시더 접속 불가 (초기화 이후) | 접속될 때까지 무한 대기·재시도 | 시더를 복구하면 자동으로 이어서 진행 |
| aria2c 오류 종료 (디스크 공간 부족 등, 초기화 이후) | "Download failed" 후 10초 뒤 재부팅 → **부팅 불가** | 복구 도구(별도 제공 예정) 또는 외부 부팅 매체 사용 |
| 다운로드 중 전원 차단 | **부팅 불가** | 복구 도구(별도 제공 예정) 또는 외부 부팅 매체 사용 |
| 복원 실패 | 오류를 검사하지 않고 끝까지 진행하므로 **부팅 불가**가 될 수 있음 | 복구 도구(별도 제공 예정) 또는 외부 부팅 매체 사용 |
| `makeboot.bat` 실패 | 빨간 화면 표시. 마운트된 이미지는 자동으로 폐기(Discard) | 메시지 확인 후 **원본 `boot` 폴더를 새로 복사**하여 재실행. 마운트가 남았으면 `dism /Cleanup-Wim` |

부팅 불가 상태가 되면 BCD 항목이 함께 초기화되므로 WinPE로도 진입할 수
없습니다. 복구 도구가 제공되기 전에는 Windows 설치 미디어 등 외부 부팅
매체로 OS를 재설치하십시오.

**점검 방법**

- 클라이언트: 네트워크 드라이버 추출 로그는 `C:\temp\boot\netdrv\backup.log`에 남습니다.
  Realtek 어댑터는 PE용 드라이버가 따로 있어 추출 대상에서 제외됩니다. 
  PE생성단계에서 자동으로 추가됩니다.
  
- WinPE: 화면 뒤에 최소화된 명령 창이 열려 있어 문제 확인에 사용할 수 있습니다.

## 6. 보안 권고

- 이미지에 계정이나 라이선스 정보가 포함될 수 있으므로 **비공개 토렌트·사설
  네트워크에서만** 사용하십시오.
- `.torrent` 파일은 신뢰할 수 있는 경로로만 전달하십시오.
- WinPE 단계에서는 **방화벽이 해제**됩니다(`wpeutil DisableFirewall`). 신뢰할 수 있는
  네트워크에서만 실행하십시오.
- 토렌트 전송은 암호화·서명 검증을 별도로 하지 않으므로, 이미지의 신뢰성은 토렌트 파일의
  신뢰성에 의존합니다.

## 7. 라이선스

본 프로그램은 The 3-Clause BSD License를 따릅니다. `\license\license.txt`를
참고하십시오.

## 부록 A. 파일 구성과 스크립트 역할

**클라이언트에서 실행 (`C:\temp\boot`)**

| 파일 | 역할 |
|---|---|
| `makeboot.bat` | 전체 준비 흐름 (관리자 권한 상승, `DVT.tag`, `boot.wim` 가공, BCD 등록, 재부팅) |
| `getip.bat` | 고정 IP이면 `C:\temp\ip.txt`에 저장, DHCP면 저장하지 않음 |
| `getlinkspeed.bat` | 링크 속도 감지 → aria2 설정·화면 색 결정 |
| `getnetdrv.bat` | 연결된 물리 어댑터의 드라이버를 `netdrv`로 추출 (Realtek 제외) |
| `setbcd.bat` | WinPE 부팅 항목 추가, 다음 부팅 1회만 적용, 다음 Windows 부팅 시 항목 자동 삭제 |
| `printip.bat` | 완료/실패 화면에 IP 마지막 자리를 크게 표시 (`ip.txt`가 없으면 오류 메시지가 보일 수 있음) |

**WinPE에서 실행 (`X:\restore`, `pe_files`에 포함)**

| 파일 | 역할 |
|---|---|
| `startnet.cmd` | WinPE 시작 시 `startDVT.bat` 호출 (`system32`에 포함) |
| `startDVT.bat` | WinPE 전체 흐름 제어 |
| `get_disk.bat` | 대상 디스크 번호 탐색 |
| `set_ip.bat` / `get_ip.bat` | 고정 IP 설정 / DHCP IP 확인 |
| `check_gateway.bat` | 게이트웨이 ping 확인 |
| `check_seeder.bat` | 시더 접속 확인 (`dvt_check.txt`) |
| `makedisk.bat` | 디스크 초기화 및 파티션 생성 |
| `get_target.bat` | 다운로드 드라이브 선택 |
| `start_restore.bat` / `restore.bat` | 다운로드 완료 훅 / 이미지 복원 |
| `aria2.conf.100`, `aria2.conf.1G` | 링크 속도별 aria2 설정 (`makeboot.bat`가 하나를 `aria2.conf`로 변경) |
| `aria2c.exe`, `wimlib-imagex.exe`, `nircmd.exe` | 외부 프로그램 |

`get_wim.bat`는 현재 `startDVT.bat`에서 호출되지 않는 이전 버전 파일입니다.

## 문의

zerojinny@gmail.com
