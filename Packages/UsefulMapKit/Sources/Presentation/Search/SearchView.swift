import Domain
import SwiftUI

/// S02 検索。
public struct SearchView: View {
    @StateObject private var viewModel: SearchViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFieldFocused: Bool
    private let onSelect: (Place) -> Void

    public init(dependencies: AppDependencies,
                center: Coordinate?,
                onSelect: @escaping (Place) -> Void) {
        _viewModel = StateObject(wrappedValue: SearchViewModel(dependencies: dependencies,
                                                              centerProvider: { center }))
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 0) {
            field
            Divider()
            content
        }
        .onAppear { isFieldFocused = true }
    }

    private var field: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("目的地を検索", text: Binding(
                    get: { viewModel.queryText },
                    set: { viewModel.updateQuery($0) }
                ))
                .focused($isFieldFocused)
                .submitLabel(.search)
                .onSubmit { viewModel.searchNow() }
                .accessibilityIdentifier(A11y.searchField)

                if !viewModel.queryText.isEmpty {
                    Button {
                        viewModel.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("入力を消去")
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color.secondary.opacity(0.12), in: Capsule())

            Button("キャンセル") { dismiss() }
                .accessibilityIdentifier(A11y.searchCancel)
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isSearching && viewModel.results.isEmpty {
            ProgressView("検索中")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("search.progress")
        } else if let message = viewModel.errorMessage {
            ContentUnavailableView("検索できませんでした", systemImage: "exclamationmark.triangle", description: Text(message))
                .accessibilityIdentifier("search.error")
        } else if viewModel.showsEmptyState {
            ContentUnavailableView("検索結果なし",
                                   systemImage: "magnifyingglass",
                                   description: Text("別のキーワードで試してください。"))
                .accessibilityIdentifier(A11y.searchEmpty)
        } else {
            List {
                Section("検索結果") {
                    ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, place in
                        Button {
                            viewModel.select(place)
                            onSelect(place)
                            dismiss()
                        } label: {
                            row(for: place)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(A11y.searchResult(index))
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func row(for place: Place) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .foregroundStyle(.tint)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.displayName)
                    .font(.body)
                if let address = place.address {
                    Text(address)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}
