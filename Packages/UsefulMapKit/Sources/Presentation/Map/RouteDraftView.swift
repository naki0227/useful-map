import Domain
import SwiftUI

/// 検索する前に条件を決めるためのフォーム。
///
/// 出発地と時刻条件を先に指定してから目的地を探せる。
/// 目的地が決まった時点で経路の取得が始まる。
struct RouteDraftView: View {
    @ObservedObject var viewModel: MapHomeViewModel
    let dependencies: AppDependencies
    let onStart: (Place) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            originRow
            Divider()
            destinationRow
            Divider()
            TimeConditionPicker(preference: viewModel.draftTimePreference,
                                date: viewModel.draftDate,
                                now: { Date() },
                                onChange: { preference, date in
                                    viewModel.setDraftTimePreference(preference, date: date)
                                })
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    // MARK: - 出発地

    @ViewBuilder
    private var originRow: some View {
        if viewModel.editingDraftField == .origin {
            InlinePlaceField(index: 0,
                             title: L10n.string("editor.origin"),
                             placeholder: L10n.string("editor.origin"),
                             allowsCurrentLocation: true,
                             dependencies: dependencies,
                             center: viewModel.currentCoordinate,
                             onSelect: { place in
                                 viewModel.draftOrigin = place
                                 viewModel.editingDraftField = nil
                             },
                             onUseCurrentLocation: { viewModel.useCurrentLocationAsDraftOrigin() },
                             onPickOnMap: {},
                             onCancel: { viewModel.editingDraftField = nil })
        } else {
            Button {
                viewModel.editingDraftField = .origin
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "smallcircle.filled.circle")
                        .foregroundStyle(.tint)
                        .frame(width: 20)
                    Text(viewModel.draftOriginName)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    if viewModel.draftOrigin != nil {
                        Button {
                            viewModel.useCurrentLocationAsDraftOrigin()
                        } label: {
                            Image(systemName: "location.fill")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.string("editor.useCurrentLocation"))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(A11y.draftOrigin)
        }
    }

    // MARK: - 目的地

    @ViewBuilder
    private var destinationRow: some View {
        if viewModel.editingDraftField == .destination {
            InlinePlaceField(index: 1,
                             title: L10n.string("editor.destination"),
                             placeholder: L10n.string("search.placeholder"),
                             allowsCurrentLocation: false,
                             dependencies: dependencies,
                             center: viewModel.currentCoordinate,
                             onSelect: { place in
                                 viewModel.editingDraftField = nil
                                 onStart(place)
                             },
                             onUseCurrentLocation: {},
                             onPickOnMap: {},
                             onCancel: { viewModel.editingDraftField = nil })
        } else {
            Button {
                viewModel.editingDraftField = .destination
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(l10n: "search.placeholder")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(A11y.searchField)
        }
    }
}
