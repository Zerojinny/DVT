# DVT GUI (C#, 단일 실행파일)

[English](README.md) | **한국어**

`DVT_GUI.exe` 파일 하나로 동작하며 설치가 필요 없습니다. **DVT 스크립트는
수정하지 않고**, 설정 파일을 편집하고 기존 스크립트를 실행만 합니다.
`gui\` 의 PowerShell 버전과 기능이 같습니다.

## 빌드 (한 번만)

**`gui_cs\build_gui.bat`** 을 실행합니다. Windows 10/11의 .NET Framework 4.x에
들어 있는 C# 컴파일러로 `src\*.cs` 를 컴파일해서(Visual Studio·SDK·다운로드
불필요) **빌드 폴더에 `DVT_GUI.exe`** 를 만듭니다(`data\` 폴더가 있는 곳).
아이콘, 매니페스트(`asInvoker`, DPI 인식), 버전 정보가 포함됩니다.

`DVT_GUI.exe` 는 빌드 폴더에 있어야 합니다. Windows 10/11에 이미 있는
.NET Framework 4.x 외에는 필요한 것이 없습니다.

## 사용

`DVT_GUI.exe` 를 더블클릭합니다(관리자 권한 불필요). 각 빌드 스크립트는 자기
콘솔 창에서 관리자 권한을 요청하고, 질문(재빌드 Y/N, USB 디스크 번호, `YES`,
드라이브 문자)도 그 창에서 답합니다.

왼쪽 사이드바로 세 페이지를 전환하며, 페이지마다 머리글·주 버튼·탭 색이
다릅니다(파랑 / 청록 / 주황). 저장하지 않은 변경은 노란 점(사이드바)과
`●`(탭)로 표시됩니다.

| 페이지 | 실행 | 편집하는 설정 |
|---|---|---|
| **Client local boot** (클라이언트 로컬부팅) | `01_make_pe.bat` | `data\host\config.cmd`, `data\pe\config.cmd`, aria2 프로필(메모장) |
| **USB / CD media** | `02_make_media.bat iso` / `usb` / `update` | `data\Media\pe\config.cmd`, `data\Media\config\ip.txt`, `DVT_backup.torrent`, aria2 프로필, `data\Media\config.cmd` |
| **Test boot** | `03_make_test_pe.bat` | `data\test\test_config.cmd` |

- **기존 DVT USB 수정:** *USB / CD media* 탭의 *Media settings in* 에서 USB를
  고르면 WinPE 설정, `ip.txt`, 토렌트를 `<USB>:\config` 에서 직접 읽고 씁니다.
  다음 부팅부터 적용됩니다.
- **Copy client package…** 는 `_output\boot`(또는 `boot_test`)를 지정한 폴더로
  복사합니다.
- 상태 표시줄에 스크립트 종료 시각과 결과가 표시됩니다.

## 필수 구성 요소 페이지

네 번째 페이지에는 **Windows ADK** 와 **WinPE 도구** 두 탭이 있습니다.

### WinPE 도구 (aria2, wimlib, NirCmd)

WinPE 이미지에 들어가는 외부 도구를 공식 사이트에서 받아
`data\host\config.cmd` 에 설정된 폴더로 복사합니다:

| 도구 | 복사 위치 | 파일 |
|---|---|---|
| aria2 1.37.0 (github.com/aria2/aria2) | `PE_TOOLS_DIR` | `aria2c.exe` |
| wimlib 1.14.5 (wimlib.net) | `PE_TOOLS_DIR` | `wimlib-imagex.exe`, `libwim-15.dll` |
| NirCmd x64 2.87 (nirsoft.net) | `PE_TOOLS_DIR` (`NIRCMD_SRC`) | zip 안의 모든 파일 (`nircmd.exe`, `nircmdc.exe`, `NirCmd.chm`) |

- URL, 허용 호스트, SHA256 해시는 `gui_cs\tools.ini` 에 있습니다(Scoop
  매니페스트 값, aria2와 NirCmd는 Npackd / Chocolatey 값과도 일치).
  해시가 다른 zip은 사용하지 않습니다. 단 NirCmd는 다운로드 주소에 버전이
  없으므로 해시를 보여 주고 사용자가 결정합니다.
- 바뀌는 파일은 먼저 `_output\tools_backup\<시각>\` 에 복사하고, zip 파일은
  `_output\tools_download\` 에 남깁니다.
- 일부 백신은 NirCmd를 "잠재적으로 원치 않는" 도구로 탐지합니다.

### Windows ADK

Windows ADK 탭은 빌드에 필요한 것만 Microsoft에서 설치합니다. Windows ADK의
**배포 도구**와 **Windows PE 추가 기능**입니다. 설치 상태도 보여 줍니다
(`ADK_PE_DIR` 에서 `winpe.wim` 을 찾는지, 첫 빌드 뒤 DVT가 보관하는 `source`
폴더의 복사본이 모두 있는지 — 모두 있으면 ADK가 더 이상 필요 없음).

- **설치할 버전:** 목록에서 ADK 릴리스(와 같은 버전의 WinPE 추가 기능)를
  고릅니다. Windows 10 1809(10.1.17763.7320)부터 최신(기본값)까지 있으며,
  설치된 버전에는 `[설치됨]` 이 붙습니다. 다른 버전이 설치되어 있으면
  *먼저 제거* 가 자동으로 체크됩니다(ADK 설치 프로그램은 다른 버전을
  덮어쓰지 못함, 오류 2008).
- **다운로드 후 설치:** `data\adk.ini` 에 있는 선택한 릴리스의 링크를 씁니다(루트
  링크를 `download.microsoft.com` 의 폴더로 확인, 실패하면 직접 링크).
  `adksetup.exe` 와 `adkwinpesetup.exe` 는 **Microsoft Authenticode 서명**이
  있어야 하고 **SHA256** 이 선택한 릴리스의 값과 같아야 합니다(다른 릴리스의
  파일이나 모르는 해시 — Microsoft가 링크를 옮기거나 다시 게시한 경우 — 는
  동의할 때만 사용). 관리자 권한을 한 번 묻고 `DVT_GUI.exe --adk-helper` 가 서명을
  다시 확인한 뒤 두 설치 프로그램을 `/quiet /norestart /ceip off /features ...`
  로 실행합니다. 선택: 설치된 ADK와 추가 기능을 먼저 제거(버전을 바꿀 때 필요).
- **오프라인 패키지 만들기:** 선택한 릴리스의 설치 프로그램을 `/layout` 으로 실행해
  `<폴더>\ADK`, `<폴더>\WinPE` 를 만듭니다. 인터넷이 안 되는 빌드 PC용.
- **오프라인 패키지로 설치:** 그렇게 만든 폴더로 설치합니다.
- 로그: `_output\adk_setup\` (`status.txt`, `adk_install.log`, `winpe_install.log`)
- 새 ADK 릴리스: `data\adk.ini` 에 `[release <버전>]` 구역(이름, 링크, 두
  해시)을 추가합니다(다시 빌드할 필요 없음). `[known <버전>]` 구역은 더 이상
  받을 수 없는 파일의 버전 이름에만 쓰입니다.

다운로드 방법과 해시는 [p0w3rsh3ll/ADK](https://github.com/p0w3rsh3ll/ADK)
(MIT 라이선스, © Emin Atac)를 참고했습니다.

## 언어

화면의 모든 문구(이름, 메시지, 모든 설정의 설명)는
**`gui_cs\lang\<코드>.ini`** 에 있습니다: `en.ini`(영어), `ko.ini`(한국어).
사이드바 아래에서 언어를 고르며, 선택은 `data\gui_settings.ini` 에
저장됩니다. 선택한 적이 없으면 Windows 표시 언어의 파일이 있을 때 그 언어,
없으면 영어를 씁니다.

- `build_gui.bat` 이 이 파일들을 `DVT_GUI.exe` 에 넣으므로 exe만 있어도
  동작합니다. 언어 파일은 **`DVT_GUI.exe` 와 같은 폴더의 `lang\`**,
  `gui_cs\lang\`, exe에 내장된 파일 순서로 찾아 처음 찾은 파일을 씁니다.
  다음 실행 때 적용되므로 다시 빌드하지 않고 문구를 고칠 수 있습니다.
- `en.ini` 가 기준입니다. 다른 파일에 없는 문구는 영어로 표시됩니다(어디에도
  없는 키는 `[key]` 로 표시).
- **새 언어 추가:** `en.ini` 를 예를 들어 `ja.ini` 로 복사하고 `[meta]` 의
  `name`, `font` 를 바꾼 뒤 `=` 뒤의 문구를 번역하면 목록에 나타납니다.
- 형식: `key = 문구`, `key += 문구` 는 줄 추가, `{0}`, `{1}` 은 유지,
  `;` 는 주석, UTF-8로 저장. 설정 설명은 `[setting 파일:이름]` 의 `summary`,
  `details`, `choice <값>` 입니다(값과 `advanced` 는 `en.ini` 기준).

## 설정 저장 방식

- 줄 맨 앞의 `set "NAME=VALUE"` 줄만 바꾸고, 주석·다른 줄·줄바꿈은 그대로 둡니다.
- 스크립트가 계산하는 값(`%~dp0`, 두 번 설정되는 이름)은 표시하지 않습니다.
- 모든 설정에 설명이 있습니다(언어 파일). 표에는 짧은 설명, 표 아래에는 자세한
  도움말(기능, 선택지, 파일의 주석)이 표시됩니다.
- 선택지가 정해진 설정은 각 값의 의미가 붙은 드롭다운으로 고릅니다
  (예: `1 - suspend for one restart`).
- 보통 바꾸지 않는 설정(경로, 도구 위치, 색 등)은 *advanced* 로 표시되고
  **Show advanced** 를 체크해야 보입니다.
- `"`, `!`, 한글 등 ASCII가 아닌 문자, 짝이 없는 `%` 는 쓸 수 없습니다(`%%` 로 입력).
- 저장할 때마다 이전 파일을 `_output\gui_backup\` 에 복사합니다.

## 백신

압축·난독화하지 않은 작은 exe를 `src\` 소스로 사용자 PC에서 직접 빌드합니다.
그래도 검사기가 탐지하면 오탐으로 제출하세요(Microsoft Defender는 Microsoft
Security Intelligence 제출 포털). 배포용 exe에 코드 서명을 하면 가장 효과가
큽니다.

## 파일

```
DVT_GUI.exe            결과물 (빌드 폴더)
gui_cs\build_gui.bat   빌드 스크립트
gui_cs\app.manifest    asInvoker, DPI 인식, Windows 8.1/10/11
gui_cs\DVT.ico         아이콘
data\adk.ini           ADK 릴리스: 다운로드 링크와 설치 파일 해시
                       (시작할 때 읽음, build_gui.bat이 exe에 넣음)
gui_cs\tools.ini       aria2 / wimlib / NirCmd 다운로드 링크와 해시
gui_cs\lang\en.ini     영어 문구 (기준, 전체)
gui_cs\lang\ko.ini     한국어 문구
gui_cs\src\*.cs        소스 (C# 5, .NET Framework 4.x, WinForms)
                       Lang.cs = 언어 파일 읽기
```
