//
//  ScreenshotTests.swift
//  mindPICUITests
//
//  App Store용 스크린샷을 찍는 UI 테스트.
//  보통은 scripts/take-screenshots.sh로 실행한다. (권한 부여, 샘플 사진, 상태바 정리를 같이 해 준다)
//
//  환경 변수 (xcodebuild에서는 TEST_RUNNER_ 접두사를 붙여 전달)
//  - SCREENSHOT_LANG: ko / en (기본 ko)
//  - SCREENSHOT_DIR:  PNG를 저장할 Mac 경로. 없으면 테스트 결과(xcresult) 첨부로만 남는다.
//

import XCTest

final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!
    private var language = "ko"

    @MainActor
    func testAppStoreScreenshots() throws {
        continueAfterFailure = false
        language = ProcessInfo.processInfo.environment["SCREENSHOT_LANG"] ?? "ko"

        app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", language == "ko" ? "ko_KR" : "en_US",
            "-uiTestResetState",
        ]
        app.launch()

        // 1. 홈 (스플래시가 끝날 때까지 대기)
        let start = app.buttons["home.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        waitUntilHittable(start)
        snapshot("01-home")

        // 2. 리뷰 화면
        start.tap()
        allowPhotoAccessIfNeeded()
        let deleteButton = app.buttons["review.delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 20),
                      "리뷰할 사진이 없습니다. 시뮬레이터 사진 앱에 사진을 넣어 주세요.")
        pause(2) // 고해상도 이미지 로딩 대기
        snapshot("02-review")

        // 3. 휴지통으로 이동 + 실행 취소 토스트
        deleteButton.tap()
        XCTAssertTrue(app.buttons["review.undo"].waitForExistence(timeout: 3))
        pause(0.8) // 가운데 휴지통 아이콘이 사라지고 토스트만 남을 때까지
        snapshot("03-undo")

        // 휴지통 화면에 보여 줄 사진을 몇 장 더 넣어 둔다 (실제 삭제 아님, 앱 휴지통에만 담김)
        for _ in 0..<5 where deleteButton.waitForExistence(timeout: 3) {
            deleteButton.tap()
            pause(0.4)
        }

        // 4. 필터
        app.buttons["review.filter"].tap()
        XCTAssertTrue(app.buttons["sheet.close"].waitForExistence(timeout: 3))
        pause(0.8)
        snapshot("04-filters")
        app.buttons["sheet.close"].tap()

        // 5. 휴지통
        goBack()
        let trash = app.buttons["home.trash"]
        XCTAssertTrue(trash.waitForExistence(timeout: 5))
        waitUntilHittable(trash) // 뒤로 가기 애니메이션 중에 누르면 무시된다
        trash.tap()
        pause(2) // 썸네일 로딩 대기
        snapshot("05-trash")

        // 6. 사용법
        goBack()
        let info = app.buttons["home.info"]
        XCTAssertTrue(info.waitForExistence(timeout: 5))
        waitUntilHittable(info) // 뒤로 가기 애니메이션 중에 누르면 무시된다
        info.tap()
        XCTAssertTrue(app.buttons["sheet.close"].waitForExistence(timeout: 3))
        pause(0.8)
        snapshot("06-guide")
    }

    // MARK: - Helpers

    @MainActor
    private func snapshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(language)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(language)-\(name).png")
            do {
                try screenshot.pngRepresentation.write(to: url)
            } catch {
                XCTFail("스크린샷 저장 실패: \(url.path) (\(error))")
            }
        }
    }

    // 스크립트가 권한을 미리 부여하지만, 그렇지 않은 경우를 위해 시스템 알림을 처리한다.
    @MainActor
    private func allowPhotoAccessIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Full Access' OR label CONTAINS '전체 접근'")
        ).firstMatch
        if allow.waitForExistence(timeout: 3) {
            allow.tap()
        }
    }

    @MainActor
    private func goBack() {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 3))
        back.tap()
    }

    @MainActor
    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 5) {
        let predicate = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTWaiter().wait(for: [expectation], timeout: timeout)
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
