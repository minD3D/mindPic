# 출시 체크리스트 (v1.0)

코드·문서·스크린샷은 준비 완료. 아래는 Apple 계정이 필요한 작업으로, 순서대로 진행하면 됩니다.

## 1. 계정 (최초 1회)

- [ ] [Apple Developer Program](https://developer.apple.com/programs/enroll/) 가입 (연 $99)
- [ ] Xcode > Settings > Accounts에 해당 Apple ID 로그인
- [ ] Xcode > mindPIC 타깃 > Signing & Capabilities > Team이 유료 계정 팀인지 확인
  - 프로젝트와 `scripts/ExportOptions.plist`의 팀 ID는 `JN62W93TAZ`. 다르면 두 곳 모두 바꿔 주세요.

## 2. App Store Connect에 앱 만들기

[App Store Connect](https://appstoreconnect.apple.com) > 앱 > ＋ > 신규 앱

| 항목 | 값 |
|---|---|
| 플랫폼 | iOS |
| 이름 | mind PIC - 스와이프 사진 정리 |
| 기본 언어 | 한국어 |
| 번들 ID | mind3d.mindPIC |
| SKU | mindpic-ios |
| 사용자 액세스 | 전체 액세스 |

## 3. 빌드 업로드

```bash
scripts/release.sh
```

단위 테스트 → Archive → 업로드까지 한 번에 진행합니다. 빌드 번호는 시각으로 자동 지정됩니다.
업로드 후 10~30분 뒤 **TestFlight** 탭에 빌드가 나타나면 **실제 아이폰**에 설치해 확인합니다.

- [ ] 실제 사진이 많은 라이브러리에서 로딩 속도
- [ ] 스와이프 / 실행 취소 / 필터
- [ ] 휴지통 비우기 시 시스템 삭제 확인 창 표시
- [ ] 권한 거부 → 설정 열기 → 허용 후 복귀

## 4. 앱 정보 입력

### 앱 정보 (일반)

| 항목 | 값 |
|---|---|
| 부제 | `docs/app-store-description.md` 참고 |
| 카테고리 | 기본: 사진 및 비디오 / 보조: 유틸리티 |
| 콘텐츠 권한 | 제3자 콘텐츠 없음 |
| 연령 등급 | 설문 전 항목 "없음 / 아니요" → 4+ |

### 앱 개인정보 보호

| 항목 | 값 |
|---|---|
| 개인정보처리방침 URL | https://github.com/minD3D/mindPic/blob/main/docs/privacy-policy.md |
| 데이터 수집 | **데이터를 수집하지 않음** |

### 가격 및 사용 가능 여부

- 가격: 무료
- 국가: **EU 27개국 제외** 전체
  - 가격 및 사용 가능 여부 > 국가 또는 지역 > EU 국가 체크 해제
  - EU에서 판매하려면 DSA 판매자 정보(주소·연락처) 공개가 필요해 v1.0에서는 제외
- [ ] App Store Connect에서 DSA(판매자 상태) 질문이 나오면 EU에 배포하지 않는다는 선택지로 응답

### 버전 1.0 — 한국어 (기본)

| 항목 | 값 |
|---|---|
| 스크린샷 (6.9") | `docs/screenshots/ko-01` ~ `ko-06` |
| 프로모션 텍스트 / 설명 / 키워드 | `docs/app-store-description.md` |
| 지원 URL | https://github.com/minD3D/mindPic/blob/main/docs/support.md |
| 저작권 | 2026 minD3D |

### 버전 1.0 — English (U.S.)

언어 메뉴(오른쪽 위)에서 **English (U.S.)** 추가 후 입력

| 항목 | 값 |
|---|---|
| 스크린샷 (6.9") | `docs/screenshots/en-01` ~ `en-06` |
| 이름 / 부제 / 프로모션 텍스트 / 설명 / 키워드 | `docs/app-store-description-en.md` |
| 지원 URL | https://github.com/minD3D/mindPic/blob/main/docs/support.md#mind-pic-support-english |

### 빌드

- 업로드한 빌드 선택
- 수출 규정 질문은 나오지 않음 (`ITSAppUsesNonExemptEncryption = NO` 설정됨)

### 앱 심사 정보

| 항목 | 값 |
|---|---|
| 로그인 필요 | 체크 해제 (로그인 기능 없음) |
| 연락처 | 본인 이름 / 전화번호 / 이메일 (심사팀에만 공개) |
| 메모 | 아래 내용 복사 |

```
This app helps users review and clean up their photo library. It requires photo library access ("Full Access" recommended) to function. All processing happens on-device; no data is collected or transmitted.

How to test: Tap "Start Reviewing" (사진 탐색 시작) → allow photo access → swipe right to favorite, swipe left to move to the in-app trash, tap to keep. Deleting from the in-app trash ("Empty Trash" / 휴지통 비우기) calls PhotoKit deletion, which shows the system confirmation dialog. Deleted photos go to "Recently Deleted" in the Photos app.
```

## 5. 심사 제출

- [ ] 버전 페이지 오른쪽 위 **심사에 추가** → **심사 제출**
- 보통 1~3일. 거절되면 사유를 그대로 공유해 주세요.
- 출시 방식: "심사 승인 후 자동 출시" 또는 "수동 출시" 중 선택
