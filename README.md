# mind PIC

**스와이프로 빠르게 끝내는 사진 정리 앱** (iOS)

사진첩에 쌓인 사진을 한 장씩 넘기면서 남길 사진과 지울 사진을 빠르게 고릅니다.

| 동작 | 결과 |
|---|---|
| 👉 오른쪽으로 밀기 | 좋아요 ('사진' 앱 즐겨찾기에 추가) |
| 👈 왼쪽으로 밀기 | 앱 휴지통으로 이동 (실행 취소 가능) |
| 👆 탭 | 보관하고 다음 사진으로 |

## 주요 기능

- **다양한 필터**: 랜덤 100장, 랜덤 1개월, N년 전 오늘, 최근 7/30일, 월 선택, 스크린샷, 연사, 인물 사진, 즐겨찾기 안 된 사진
- **안 본 사진만 보기**: 이미 확인한 사진은 건너뛰기
- **안전한 삭제**: 앱 휴지통에서 다시 확인·복원 → 비우면 '최근 삭제된 항목'으로 이동 (30일 보관)
- **개인정보 보호**: 모든 처리는 기기 안에서만. 회원가입·서버·광고·분석 도구 없음
- 한국어 / 영어 지원, Dynamic Type, VoiceOver 라벨

## 요구 사항

- iPhone, iOS 17.0 이상
- 개발: Xcode 16 이상

## 빌드

```bash
git clone https://github.com/minD3D/mindPic.git
open mindPic/mindPIC.xcodeproj
```

1. Xcode에서 **Signing & Capabilities > Team**을 본인 개발자 계정으로 설정합니다.
2. `mindPIC` 스킴으로 실행(⌘R), 테스트(⌘U)합니다.
3. 시뮬레이터에서는 사진 앱에 사진을 드래그해 넣어 테스트할 수 있습니다.

## 구조

```
mindPIC/
├── MindPICApp.swift            앱 진입점
├── ContentView.swift           스플래시 → 홈
├── HomeView.swift              홈 화면
├── HomeSheets.swift            설정 / 사용법 시트
├── PhotoReviewView.swift       스와이프 리뷰 화면, 필터 시트
├── PhotoReviewViewModel.swift  필터별 사진 조회(백그라운드), 이동/좋아요/삭제/실행 취소, 프리히팅
├── TrashView.swift             휴지통 (복원, 비우기)
├── AssetImageView.swift        썸네일 → 고해상도 단계 로딩
├── ReviewStateStore.swift      본 사진 / 휴지통 ID 저장 (UserDefaults)
├── PhotoModels.swift           PhotoItem, PhotoFilterType
├── PhotoHelpers.swift          권한 요청, 이미지 요청 스펙
├── Theme.swift                 색상, 폰트, 공통 컴포넌트
├── Localizable.xcstrings       화면 문구 (ko, en)
├── InfoPlist.xcstrings         권한 안내 문구 (ko, en)
└── PrivacyInfo.xcprivacy       개인정보 매니페스트
```

- **UI**: SwiftUI
- **사진**: PhotoKit (`PHAsset`, `PHCachingImageManager`)
- **테스트**: Swift Testing (`mindPICTests`)

## 문서

- [지원 / 자주 묻는 질문](docs/support.md)
- [개인정보처리방침](docs/privacy-policy.md)

## 문의

[GitHub Issues](https://github.com/minD3D/mindPic/issues)에 남겨 주세요.

---

# mind PIC (English)

**Swipe through your camera roll and clean it up fast.** An iOS app for reviewing photos one at a time: swipe right to favorite, swipe left to trash (with undo), tap to keep.

- Filters: random 100, random month, on this day N years ago, last 7/30 days, any month, screenshots, bursts, portraits, non-favorites
- Safe deletion: review and restore from the in-app trash; emptying it moves photos to "Recently Deleted" (kept for 30 days)
- Private by design: everything runs on-device — no account, server, ads, or analytics
- Korean and English, Dynamic Type, VoiceOver labels
- Requires iPhone with iOS 17.0+; built with SwiftUI and PhotoKit

[Support & FAQ](docs/support.md#mind-pic-support-english) · [Privacy Policy](docs/privacy-policy.md#mind-pic-privacy-policy-english)
