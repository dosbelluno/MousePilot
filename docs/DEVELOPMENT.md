# 개발·배포

## 개발 환경

- macOS 14 이상
- Swift 6 이상과 macOS SDK가 포함된 개발 환경
- `codesign`, `iconutil`, `ditto`를 포함한 macOS 기본 도구

외부 Swift 패키지는 사용하지 않습니다. 아래 명령은 저장소 루트에서 실행합니다.

```sh
swift test
./scripts/build-app.sh
```

디버그 앱이 필요하면 `./scripts/build-app.sh debug`를 사용합니다. 빌드 스크립트는 앱을 실행하지 않습니다.
앱 실행은 `./scripts/run.sh`로 별도로 수행합니다.

## 프로젝트 구조

| 경로 | 역할 |
| --- | --- |
| `Sources/MousePilotCore/` | 매핑 모델, 제스처 판정, 설정 검증·저장·이전 |
| `Sources/MousePilot/` | SwiftUI 화면, 마우스 이벤트 처리, 단축키 전송, 스크롤 반전 |
| `Tests/MousePilotCoreTests/` | 입력 판정과 설정 테스트 |
| `Tests/MousePilotRuntimeTests/` | 권한 판정, 키·스크롤 이벤트 생성, 진단 기록 테스트 |
| `Resources/Info.plist` | 앱 식별자, 버전, 최소 macOS 버전 |
| `scripts/` | 앱 빌드, 아이콘 생성, 실행, 진단 |
| `docs/images/` | 테스트 설정으로 렌더링한 문서용 화면 이미지 |
| `docs/examples/macos-ci.yml` | 선택적으로 사용할 GitHub Actions 자동 빌드 예제 |

## 테스트

`swift test`는 실제 CGEvent를 생성하지만, 단축키 전송 함수를 가짜 구현으로 바꿔 시스템에 입력을 보내지 않습니다.
설정 테스트는 임시 폴더를 사용합니다. 앱 실행과 사용자 설정 변경은 테스트에 포함하지 않습니다.

자동 빌드 설정은 `docs/examples/macos-ci.yml`에 예제로 보관하며, 현재 저장소에서 자동으로 실행되지 않습니다.
필요하면 `.github/workflows/ci.yml`로 옮겨 활성화할 수 있습니다. GitHub CLI의 OAuth 인증으로 이 경로를 업로드하려면 `workflow` 권한이 필요합니다.

예제는 `macos-15`에서 테스트와 release 앱 빌드를 수행합니다. `MOUSEPILOT_SIGN_IDENTITY=-`로 ad hoc 서명을 사용하고, ZIP을 임시 폴더에 풀어 서명을 검사합니다.
인증서나 macOS 입력 권한을 등록할 필요가 없습니다. 이 방식으로 생성한 앱은 공증된 배포본이 아닙니다.

실제 사용 검증은 별도로 진행합니다. 휠 클릭, 네 방향 제스처, 원래 옆면 버튼 동작, 마우스 스크롤 반전과 트랙패드 방향 유지를 확인하세요.

## 화면 이미지 갱신

```sh
swift build
mousepilot_bin_dir="$(swift build --show-bin-path)"
"$mousepilot_bin_dir/MousePilot" --render-preview "$PWD/build/preview"
cp build/preview/main-light.png docs/images/gestures-light.png
cp build/preview/main-dark.png docs/images/gestures-dark.png
cp build/preview/settings-light.png docs/images/settings-light.png
cp build/preview/settings-dark.png docs/images/settings-dark.png
```

이 모드는 테스트 설정으로 화면을 렌더링한 뒤 종료합니다. 창이나 마우스 이벤트 필터를 만들지 않고, 사용자 설정을 읽거나 변경하지 않습니다.

## 서명과 패키징

빌드 스크립트는 다음 순서로 서명을 선택합니다.

1. `MOUSEPILOT_SIGN_IDENTITY`에 지정한 서명
2. 사용 가능한 Developer ID Application 인증서
3. 사용 가능한 Apple Development 인증서
4. 인증서가 없으면 ad hoc 서명

서명을 직접 선택하려면:

```sh
MOUSEPILOT_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./scripts/build-app.sh
```

인증서 없이 패키징만 확인하려면:

```sh
MOUSEPILOT_SIGN_IDENTITY=- ./scripts/build-app.sh
```

서명된 앱은 시스템 임시 폴더에서 만들고 검증한 뒤 `build/`로 옮깁니다. ZIP은 Finder 메타데이터를 제외해 만듭니다.
프로젝트가 파일 제공자에서 관리되는 경우, 출력된 `.app`에 메타데이터가 다시 붙을 수 있으므로 설치에는 ZIP을 사용하세요.

같은 서명과 앱 식별자를 유지하는 것이 권한 재등록을 줄이는 데 도움이 됩니다. ad hoc 서명이나 다른 인증서로 바뀌면 손쉬운 사용 권한을 다시 등록해야 할 수 있습니다.
기본 빌드는 현재 Mac의 아키텍처를 사용하며, universal binary를 자동으로 만들지 않습니다.

## 설정과 진단

설정은 `~/Library/Application Support/MousePilot/settings.json`에 저장합니다.
이전 형식은 읽을 때 자동으로 이전하고, 원본을 `settings.before-gestures-<UUID>.json`에 백업합니다.
손상된 설정은 `settings.invalid-<UUID>.json`에 백업하고 매핑이 꺼진 기본 설정으로 시작합니다.

일반 사용에서는 입력 기록을 수집하지 않습니다. 앱에서 진단 기록을 직접 켠 동안에만 최근 입력과 상태를 표시합니다.
권한·연결 문제는 **설정 → 문제 해결 → 진단 정보 → 복사**에서 확인합니다.

개발용 명령도 제공합니다.

```sh
./scripts/diagnose.sh
```

이 명령은 LaunchServices를 통해 앱의 진단 모드를 실행하고 종료합니다. 창을 띄우거나 시스템에 입력을 보내지 않습니다.
보고서는 `~/Library/Application Support/MousePilot/last-diagnostic.txt`에 저장되며, 앱 경로·버전·권한·연결 상태를 포함합니다. 입력 기록은 포함하지 않습니다.
보고서를 공유할 때는 앱 경로에 포함된 사용자 이름을 확인하세요.

`accessibility`, `postEvents`, `mouseTapCreated`가 모두 `true`인지 확인합니다. `inputMonitoring`이 `false`여도 마우스 매핑을 막지 않습니다.
진단 명령은 자동 테스트와 CI에서 실행하지 않습니다.

## 저장소와 릴리스

소스, 테스트, 리소스, 스크립트, 문서를 Git에 포함합니다. 생성된 앱·ZIP·빌드 캐시·서명 키는 `.gitignore`로 제외합니다.

라이선스를 결정하면 루트에 `LICENSE`를 추가하고 README의 라이선스 안내를 갱신하세요.

릴리스를 준비할 때는:

1. `Resources/Info.plist`의 버전·빌드 번호와 화면의 버전 표기를 함께 갱신합니다.
2. `CHANGELOG.md`에 사용자에게 달라지는 내용을 기록하고, 화면이 바뀌었다면 문서 이미지를 갱신합니다.
3. `swift test`와 앱 패키징을 수행하고, 실제 마우스 동작은 별도로 확인합니다.
4. 다른 Mac에 배포할 앱은 Developer ID 서명과 공증을 별도로 준비합니다. 빌드 스크립트는 공증을 수행하지 않습니다.
5. 배포용 ZIP을 릴리스 파일로 첨부하고 설치 안내를 갱신합니다. 빌드 결과를 Git 소스에 넣지 않습니다.

자동 빌드 예제를 활성화하면 검사만 수행하며, 릴리스를 게시하거나 저장소에 커밋하지 않습니다.

CI 구성 참고: [actions/checkout](https://github.com/actions/checkout), [macOS 15 러너 이미지](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md).
