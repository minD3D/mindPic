#!/usr/bin/env bash
#
# App Store용 스크린샷을 한국어/영어로 자동 촬영한다.
#
# 사용법:
#   scripts/take-screenshots.sh [사진 폴더]
#
#   사진 폴더를 주면 시뮬레이터 사진 앱에 넣고 촬영한다. (실행할 때마다 추가되므로 처음 한 번만)
#   저작권 문제가 없는 사진(직접 찍은 사진 등)을 쓰세요.
#
# 환경 변수:
#   DEVICE   시뮬레이터 이름 (기본: iPhone 17 Pro Max — App Store 6.9인치 규격)
#   LANGS    촬영할 언어 (기본: "ko en")
#   OUT_DIR  저장 폴더 (기본: ./screenshots)
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${DEVICE:-iPhone 17 Pro Max}"
LANGS="${LANGS:-ko en}"
OUT_DIR="${OUT_DIR:-$ROOT/screenshots}"
PHOTOS_DIR="${1:-}"
BUNDLE_ID="mind3d.mindPIC"

UDID="$(xcrun simctl list devices available | grep -m1 -F "    $DEVICE (" | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' || true)"
if [[ -z "$UDID" ]]; then
    echo "시뮬레이터 '$DEVICE'를 찾을 수 없습니다. 사용 가능한 기기:" >&2
    xcrun simctl list devices available | grep -E '^\s+iPhone' >&2
    echo "예: DEVICE=\"iPhone 16 Pro Max\" $0" >&2
    exit 1
fi
echo "▶ 시뮬레이터: $DEVICE ($UDID)"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

# 상태바를 App Store 스크린샷 관례대로 정리 (9:41, 배터리 가득)
xcrun simctl status_bar "$UDID" override \
    --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

if [[ -n "$PHOTOS_DIR" ]]; then
    shopt -s nullglob nocaseglob
    photos=("$PHOTOS_DIR"/*.{jpg,jpeg,png,heic})
    shopt -u nullglob nocaseglob
    if (( ${#photos[@]} == 0 )); then
        echo "'$PHOTOS_DIR'에 사진(jpg/png/heic)이 없습니다." >&2
        exit 1
    fi
    echo "▶ 사진 ${#photos[@]}장 추가"
    xcrun simctl addmedia "$UDID" "${photos[@]}"
fi

# 권한 알림 없이 바로 시작하도록 사진 접근을 미리 허용
xcrun simctl privacy "$UDID" grant photos "$BUNDLE_ID" 2>/dev/null || true

mkdir -p "$OUT_DIR"
for lang in $LANGS; do
    echo "▶ 촬영: $lang"
    TEST_RUNNER_SCREENSHOT_DIR="$OUT_DIR" TEST_RUNNER_SCREENSHOT_LANG="$lang" \
    xcodebuild test \
        -project "$ROOT/mindPIC.xcodeproj" \
        -scheme mindPIC \
        -destination "id=$UDID" \
        -parallel-testing-enabled NO \
        -only-testing:mindPICUITests/ScreenshotTests \
        -quiet
done

xcrun simctl status_bar "$UDID" clear

echo "✅ 완료: $OUT_DIR"
ls -1 "$OUT_DIR"
