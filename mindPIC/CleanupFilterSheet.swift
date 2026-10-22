import SwiftUI

// MARK: - 정리 추천·비슷한 사진 필터
// 정렬, 사진 종류, 검토 상태를 고른다. 바꾸는 즉시 목록에 반영된다 (다시 분석하지 않음).
struct CleanupFilterSheet: View {
    @Binding var filter: CleanupFilter
    var kindsFooter: LocalizedStringKey = "아무것도 고르지 않으면 모든 사진을 보여줘요. 스크린샷은 위쪽 이유 칩에서 고를 수 있어요."
    // 내용(기기 분석) 섹션. 사진마다 분류 결과가 있는 화면에서만 켠다.
    var showsCategories = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("정렬") {
                    Picker("정렬", selection: $filter.sort) {
                        ForEach(CleanupSort.allCases) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    ForEach(CleanupPhotoKind.allCases) { kind in
                        kindRow(kind)
                    }
                } header: {
                    Text("사진 종류")
                } footer: {
                    Text(kindsFooter)
                }

                if showsCategories {
                    Section {
                        ForEach(PhotoCategory.allCases) { category in
                            checkRow(LocalizedStringKey(category.title), systemImage: category.systemImage,
                                     isOn: filter.categories.contains(category)) {
                                filter.categories.formSymmetricDifference([category])
                            }
                        }
                    } header: {
                        Text("내용 (기기 분석)")
                    } footer: {
                        Text("기기 안에서 사진을 분석해 찾아요. 여러 개를 고르면 하나라도 해당하는 사진을 보여줘요.")
                    }
                }

                Section {
                    Toggle("안 본 사진만", isOn: $filter.unseenOnly)
                    Toggle("앨범에 없는 사진만", isOn: $filter.notInAlbumOnly)
                } header: {
                    Text("상태")
                } footer: {
                    Text("앨범에 넣은 사진은 남기려는 사진일 가능성이 높아요.")
                }
            }
            .tint(AppTheme.accentDark)
            .navigationTitle("필터")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("초기화") { filter = CleanupFilter() }
                        .disabled(filter == CleanupFilter())
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }

    private func kindRow(_ kind: CleanupPhotoKind) -> some View {
        checkRow(kind.title, systemImage: kind.systemImage, isOn: filter.kinds.contains(kind)) {
            filter.kinds.formSymmetricDifference([kind])
        }
    }

    private func checkRow(_ title: LocalizedStringKey, systemImage: String, isOn: Bool,
                          toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.accentDark)
                }
            }
        }
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}
