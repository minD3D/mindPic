#!/usr/bin/env bash
#
# 빌드 → 연결된 iPhone에 설치 → 실행을 한 번에 실행한다. (AltServer 불필요)
#
# 사용법:
#   scripts/install-device.sh
#
# 준비:
#   - Xcode > Settings > Accounts에 Apple ID 로그인 (서명은 Xcode가 자동 처리 — 비밀번호 입력 없음)
#   - iPhone을 USB 또는 같은 Wi-Fi로 연결하고 신뢰/개발자 모드 켜기
#
# 환경 변수:
#   DEVICE_ID      설치할 기기 identifier (기본: 첫 번째 연결된 iPhone)
#   CONFIGURATION  Debug | Release (기본: Release)
#   NO_LAUNCH=1    설치 후 실행 생략
#   TEAM           서명 팀 ID (무료 Apple ID 팀이 프로젝트 팀과 다를 때 지정)
#   BUNDLE_ID      번들 ID (무료 계정에서 기본 ID가 이미 사용 중일 때 변경)
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/mindPIC.xcodeproj"
SCHEME="mindPIC"
BUNDLE_ID="${BUNDLE_ID:-mind3d.mindPIC}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED="$ROOT/build/device"

if [[ -z "${DEVICE_ID:-}" ]]; then
    DEVICE_ID="$(xcrun devicectl list devices 2>/dev/null \
        | awk '/available/ && /iPhone/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F-]{36}$/) {print $i; exit}}')"
fi
if [[ -z "$DEVICE_ID" ]]; then
    echo "✗ 연결된 iPhone을 찾지 못했습니다. 'xcrun devicectl list devices'로 확인하세요." >&2
    exit 1
fi
echo "▶ 대상 기기: $DEVICE_ID"

echo "▶ 빌드 ($CONFIGURATION)"
xcodebuild build \
    -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    ${TEAM:+DEVELOPMENT_TEAM="$TEAM"} \
    -quiet

APP="$DERIVED/Build/Products/$CONFIGURATION-iphoneos/mindPIC.app"

echo "▶ 설치"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

if [[ "${NO_LAUNCH:-0}" != "1" ]]; then
    echo "▶ 실행"
    xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" || \
        echo "  (실행 실패 — 기기가 잠겨 있으면 잠금 해제 후 직접 실행하세요)"
fi

echo "✓ 완료"
