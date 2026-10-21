#!/usr/bin/env bash
#
# 테스트 → Archive → App Store Connect 업로드를 한 번에 실행한다.
#
# 사용법:
#   scripts/release.sh
#
# 준비:
#   - Xcode > Settings > Accounts에 Apple Developer Program 계정으로 로그인
#   - App Store Connect에 번들 ID mind3d.mindPIC 앱이 만들어져 있어야 업로드됨
#
# 환경 변수:
#   BUILD_NUMBER  빌드 번호 (기본: 현재 시각 YYYYMMDD.HHMM — 업로드마다 달라야 함)
#   DEVICE        테스트용 시뮬레이터 (기본: iPhone 17 Pro Max)
#   SKIP_TESTS=1  테스트 생략
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/mindPIC.xcodeproj"
SCHEME="mindPIC"
BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/mindPIC.xcarchive"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d.%H%M)}"
DEVICE="${DEVICE:-iPhone 17 Pro Max}"

VERSION="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ MARKETING_VERSION = /{print $2; exit}')"
echo "▶ mind PIC $VERSION ($BUILD_NUMBER)"

if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
    echo "▶ 단위 테스트 ($DEVICE)"
    xcodebuild test \
        -project "$PROJECT" -scheme "$SCHEME" \
        -destination "platform=iOS Simulator,name=$DEVICE" \
        -only-testing:mindPICTests \
        -quiet
fi

rm -rf "$BUILD_DIR"

echo "▶ Archive"
xcodebuild archive \
    -project "$PROJECT" -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    -quiet

echo "▶ App Store Connect 업로드"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$ROOT/scripts/ExportOptions.plist" \
    -exportPath "$BUILD_DIR/export" \
    -allowProvisioningUpdates

echo "✅ 업로드 완료: $VERSION ($BUILD_NUMBER)"
echo "   App Store Connect > TestFlight에서 처리 완료(보통 10~30분) 후 빌드를 선택할 수 있습니다."
