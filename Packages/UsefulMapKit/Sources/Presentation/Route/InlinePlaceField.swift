import Domain
import SwiftUI

/// その場で地点を選ぶための入力欄。
///
/// 別画面を出さずに、押したらキーボードが出て候補が下に並ぶ。
/// 「現在地」と「地図で選ぶ」も同じ場所から選べる。
struct InlinePlaceField: View {
    let index: Int
    let title: String
    let placeholder: String
    let allowsCurrentLocation: Bool
    let onSelect: (Place) -> Void
    let onUseCurrentLocation: () -> Void
    let onPickOnMap: () -> Void
    let onCancel: () -> Void

    @StateObject private var viewModel: SearchViewModel
    @FocusState private var isFocused: Bool

    init(index: Int,
         title: String,
         placeholder: String,
         allowsCurrentLocation: Bool,
         dependencies: AppDependencies,
         center: Coordinate?,
         onSelect: @escaping (Place) -> Void,
         onUseCurrentLocation: @escaping () -> Void,
         onPickOnMap: @escaping () -> Void,
         onCancel: @escaping () -> Void) {
        self.index = index
        self.title = title
        self.placeholder = placeholder
        self.allowsCurrentLocation = allowsCurrentLocation
        self.onSelect = onSelect
        self.onUseCurrentLocation = onUseCurrentLocation
        self.onPickOnMap = onPickOnMap
        self.onCancel = onCancel
        _viewModel = StateObject(wrappedValue: SearchViewModel(dependencies: dependencies,
                                                              centerProvider: { center }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            field
            shortcuts
            results
        }
        .padding(.vertical, 4)
        .onAppear { isFocused = true }
    }

    private var field: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: Binding(
                get: { viewModel.queryText },
                set: { viewModel.updateQuery($0) }
            ))
            .focused($isFocused)
            .textFieldStyle(.plain)
            .submitLabel(.search)
            .onSubmit { viewModel.searchNow() }
            .accessibilityIdentifier(A11y.nodeField(index))

            if viewModel.isSearching {
                ProgressView().controlSize(.small)
            }
            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("search.cancel"))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var shortcuts: some View {
        HStack(spacing: 8) {
            if allowsCurrentLocation {
                shortcutButton(title: L10n.string("endpoint.currentLocation"),
                               symbol: "location.fill",
                               identifier: A11y.currentLocationButton,
                               action: onUseCurrentLocation)
            }
            shortcutButton(title: L10n.string("route.pickOnMap"),
                           symbol: "mappin.and.ellipse",
                           identifier: A11y.pickOnMapButton,
                           action: onPickOnMap)
            Spacer()
        }
    }

    private func shortcutButton(title: String,
                                symbol: String,
                                identifier: String,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.footnote)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var results: some View {
        if viewModel.showsEmptyState {
            Text(l10n: "search.empty.title")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if let message = viewModel.errorMessage {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(viewModel.results.prefix(5).enumerated()), id: \.element.id) { position, place in
                    Button {
                        viewModel.select(place)
                        onSelect(place)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(place.displayName)
                                    .font(.subheadline)
                                if let address = place.address {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(A11y.searchResult(position))

                    if position < min(viewModel.results.count, 5) - 1 {
                        Divider()
                    }
                }
            }
        }
    }
}
