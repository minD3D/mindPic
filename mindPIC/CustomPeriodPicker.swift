import Photos
import SwiftUI

// MARK: - '직접 선택' 기간 (정리 추천, 비슷한 사진 공통)
// 시작·끝 날짜와, 연도·월·최근 N년을 한 번에 고르는 빠른 선택 메뉴
struct CustomPeriodPicker: View {
    @Binding var start: Date
    @Binding var end: Date
    // 연도 목록의 시작. 보관함에서 가장 오래된 사진의 연도로 채운다.
    @State private var firstYear: Int?

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    private var years: [Int] { Array(stride(from: currentYear, through: firstYear ?? currentYear - 9, by: -1)) }

    var body: some View {
        HStack(spacing: 8) {
            DatePicker("시작", selection: $start, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
            Text(verbatim: "~")
                .foregroundStyle(AppTheme.textSecondary)
            DatePicker("끝", selection: $end, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
            Spacer(minLength: 0)
            quickMenu
        }
        .task { firstYear = await Self.oldestPhotoYear() }
    }

    private var quickMenu: some View {
        Menu {
            Section("최근") {
                button(.recentMonths(3)) { Text("최근 3개월") }
                button(.recentMonths(6)) { Text("최근 6개월") }
                ForEach([2, 3, 5], id: \.self) { n in
                    button(.recentYears(n)) { Text("최근 \(n)년") }
                }
            }
            Menu("연도") {
                ForEach(years, id: \.self) { year in
                    button(.year(year)) { Text(yearLabel(year)) }
                }
            }
            Menu("월") {
                ForEach(years, id: \.self) { year in
                    Menu(yearLabel(year)) {
                        ForEach(months(in: year), id: \.self) { month in
                            button(.month(year: year, month: month)) { Text(monthLabel(year, month)) }
                        }
                    }
                }
            }
        } label: {
            Label("빠른 선택", systemImage: "calendar.badge.clock")
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(AppTheme.accentDark)
        }
        .accessibilityLabel("기간 빠른 선택")
        .accessibilityIdentifier("period.quick")
    }

    private func button(_ quick: QuickDateRange, @ViewBuilder label: () -> Text) -> some View {
        Button {
            let range = quick.range()
            start = range.start
            end = range.end
        } label: {
            label()
        }
    }

    // 올해는 이번 달까지만, 최신 월부터
    private func months(in year: Int) -> [Int] {
        let last = year == currentYear ? Calendar.current.component(.month, from: Date()) : 12
        return Array((1...last).reversed())
    }

    private func yearLabel(_ year: Int) -> String {
        date(year, 1).formatted(.dateTime.year())
    }

    private func monthLabel(_ year: Int, _ month: Int) -> String {
        date(year, month).formatted(.dateTime.month(.wide))
    }

    private func date(_ year: Int, _ month: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
    }

    private nonisolated static func oldestPhotoYear() async -> Int? {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.fetchLimit = 1
        guard let date = PHAsset.fetchAssets(with: .image, options: options).firstObject?.creationDate else { return nil }
        return Calendar.current.component(.year, from: date)
    }
}
