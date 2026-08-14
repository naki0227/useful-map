import Domain
import SwiftUI

/// S06 保存・履歴。
public struct SavedView: View {
    @StateObject private var viewModel: SavedViewModel
    @EnvironmentObject private var router: AppRouter
    private let dependencies: AppDependencies

    public init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: SavedViewModel(dependencies: dependencies))
    }

    public var body: some View {
        NavigationStack {
            List {
                savedSection
                routesSection
                searchesSection
            }
            .navigationTitle(L10n.string("saved.title"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.string("saved.clearHistory")) { viewModel.clearHistory() }
                        .accessibilityIdentifier("saved.clearHistory")
                        .disabled(viewModel.recentRoutes.isEmpty && viewModel.recentSearches.isEmpty)
                }
            }
        }
        .onAppear { viewModel.refresh() }
    }

    @ViewBuilder
    private var savedSection: some View {
        Section(L10n.string("saved.section.places")) {
            if viewModel.savedPlaces.isEmpty {
                Text(l10n: "saved.empty")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("saved.empty")
            } else {
                ForEach(Array(viewModel.savedPlaces.enumerated()), id: \.element.id) { index, saved in
                    HStack(spacing: 12) {
                        Button {
                            router.selectedTab = .map
                            router.showPlaceDetail(saved.place)
                        } label: {
                            savedRow(saved)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(A11y.savedPlace(index))

                        labelMenu(for: saved, index: index)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        viewModel.remove(id: viewModel.savedPlaces[index].id)
                    }
                }
            }
        }
    }

    private func savedRow(_ saved: SavedPlace) -> some View {
        HStack(spacing: 12) {
            Image(systemName: saved.label.symbolName)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(saved.place.displayName)
                if let address = saved.place.address {
                    Text(address)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if saved.label != .other {
                    Label(saved.label.displayName, systemImage: saved.label.symbolName)
                        .font(.caption)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    /// ラベルの付け替えと削除（モックの「・・・」メニュー）。
    private func labelMenu(for saved: SavedPlace, index: Int) -> some View {
        Menu {
            Picker(L10n.string("saved.label"), selection: Binding(
                get: { saved.label },
                set: { viewModel.setLabel($0, for: saved.place) }
            )) {
                ForEach(SavedPlace.Label.allCases, id: \.self) { label in
                    Label(label.displayName, systemImage: label.symbolName)
                        .tag(label)
                        .accessibilityIdentifier(A11y.savedLabelOption(label.rawValue))
                }
            }
            Divider()
            Button(L10n.string("saved.remove"), systemImage: "trash", role: .destructive) {
                viewModel.remove(id: saved.id)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier(A11y.savedPlaceMenu(index))
        .accessibilityLabel(L10n.string("saved.menu", saved.place.displayName))
    }

    @ViewBuilder
    private var routesSection: some View {
        Section(L10n.string("saved.section.routes")) {
            if viewModel.recentRoutes.isEmpty {
                Text(l10n: "saved.noHistory")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(viewModel.recentRoutes.enumerated()), id: \.element.id) { index, route in
                    Button {
                        router.selectedTab = .map
                        router.showRoute(viewModel.plan(from: route), dependencies: dependencies)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Formatters.routeTitle(origin: route.origin, destination: route.destination))
                                .font(.body)
                            HStack(spacing: 8) {
                                Label(route.transportMode.displayName, systemImage: route.transportMode.symbolName)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Formatters.historyTimestamp(route.usedAt))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(A11y.recentRoute(index))
                }
            }
        }
    }

    @ViewBuilder
    private var searchesSection: some View {
        if !viewModel.recentSearches.isEmpty {
            Section(L10n.string("saved.section.searches")) {
                ForEach(Array(viewModel.recentSearches.enumerated()), id: \.element.id) { index, recent in
                    Button {
                        router.selectedTab = .map
                        router.showPlaceDetail(recent.place)
                    } label: {
                        HStack {
                            Text(recent.place.displayName)
                            Spacer()
                            Text(Formatters.historyTimestamp(recent.searchedAt))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(A11y.recentSearch(index))
                }
            }
        }
    }
}
