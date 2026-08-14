import Domain
import MapKit
import SwiftUI

/// 地図画面。検索・場所詳細・経路をすべてこの 1 枚で扱う。
///
/// 上のシート = 検索欄、または経路の連鎖編集。
/// 下のシート = 履歴、場所詳細、経路の要約。
/// タブで地図と経路を行き来しないので、地図の文脈が切れない。
public struct MapHomeView: View {
    private let dependencies: AppDependencies
    @StateObject private var viewModel: MapHomeViewModel
    @EnvironmentObject private var router: AppRouter
    @State private var camera: MapCameraPosition = .automatic

    public init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: MapHomeViewModel(dependencies: dependencies))
    }

    public var body: some View {
        ZStack(alignment: .top) {
            map
            topSheet
            VStack(spacing: 0) {
                Spacer()
                bottomSheet
            }
        }
        .overlay(alignment: .bottomTrailing) { recenterButton }
        .task { await viewModel.onAppear() }
        .onChange(of: viewModel.currentCoordinate) { _, coordinate in
            guard let coordinate, router.planViewModel == nil else { return }
            camera = .region(coordinate.region())
        }
    }

    // MARK: - 地図

    private var map: some View {
        MapReader { proxy in
            Map(position: $camera) {
                UserAnnotation()

                if let plan = router.planViewModel?.plan {
                    ForEach(Array(plan.nodes.enumerated()), id: \.element.id) { index, node in
                        Marker(node.displayName, coordinate: node.place.coordinate.mapCoordinate)
                            .tint(index == plan.nodes.count - 1 ? .red : .accentColor)
                    }
                    ForEach(plan.segments) { segment in
                        if let geometry = segment.leg?.geometry, geometry.count > 1 {
                            MapPolyline(coordinates: geometry.map(\.mapCoordinate))
                                .stroke(segment.mode == .walking ? Color.secondary : Color.accentColor,
                                        style: StrokeStyle(lineWidth: 5,
                                                           dash: segment.mode == .walking ? [6, 6] : []))
                        }
                    }
                } else if let place = router.detailPlace {
                    Marker(place.displayName, coordinate: place.coordinate.mapCoordinate)
                        .tint(.red)
                }
            }
            .mapControls { MapCompass() }
            .ignoresSafeArea(edges: .top)
            .accessibilityIdentifier("map.canvas")
            .accessibilityLabel(L10n.string("map.canvas"))
            .onTapGesture { position in
                // 編集中に地図を触ったら入力を閉じる。
                guard router.mapPickTarget != nil else {
                    router.planViewModel?.editingNodeIndex = nil
                    router.planViewModel?.cancelAddingWaypoint()
                    return
                }
                guard let coordinate = proxy.convert(position, from: .local) else { return }
                Task { await pickPlace(at: Coordinate(latitude: coordinate.latitude,
                                                      longitude: coordinate.longitude)) }
            }
        }
    }

    private func pickPlace(at coordinate: Coordinate) async {
        guard let target = router.mapPickTarget else { return }
        let place = await dependencies.placeResolver.place(at: coordinate)
        router.planViewModel?.commitPlace(place, at: target)
        router.mapPickTarget = nil
    }

    // MARK: - 上のシート

    @ViewBuilder
    private var topSheet: some View {
        VStack(spacing: 12) {
            if let planViewModel = router.planViewModel {
                RoutePlanChainView(viewModel: planViewModel,
                                   dependencies: dependencies,
                                   center: viewModel.currentCoordinate,
                                   onPickOnMap: { index in router.mapPickTarget = index },
                                   onClose: { router.closeRoute() })
                if router.mapPickTarget != nil {
                    mapPickHint
                }
            } else {
                searchBar
                quickChips
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var mapPickHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap")
            Text(l10n: "route.pickOnMap.hint")
                .font(.footnote)
            Spacer()
            Button(L10n.string("search.cancel")) { router.mapPickTarget = nil }
                .font(.footnote)
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.1), radius: 6, y: 1)
    }

    private var searchBar: some View {
        Button {
            router.isSearchPresented = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(l10n: "search.placeholder")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(.background, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(A11y.searchField)
        .accessibilityLabel(L10n.string("search.placeholder"))
        .sheet(isPresented: $router.isSearchPresented) {
            SearchView(dependencies: dependencies,
                       center: viewModel.currentCoordinate) { place in
                viewModel.refreshStoredData()
                router.showPlaceDetail(place)
            }
        }
    }

    private var quickChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(viewModel.savedPlaces.prefix(4).enumerated()), id: \.element.id) { index, saved in
                    Button {
                        router.showPlaceDetail(saved.place)
                    } label: {
                        Label(saved.label == .other ? saved.place.displayName : saved.label.displayName,
                              systemImage: saved.label.symbolName)
                            .font(.subheadline)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(.background, in: Capsule())
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(A11y.savedPlace(index))
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: viewModel.savedPlaces.isEmpty ? 0 : 48)
        .opacity(viewModel.savedPlaces.isEmpty ? 0 : 1)
    }

    // MARK: - 下のシート

    @ViewBuilder
    private var bottomSheet: some View {
        Group {
            if let planViewModel = router.planViewModel {
                RoutePlanSummaryView(viewModel: planViewModel)
            } else if let place = router.detailPlace {
                PlaceDetailView(place: place,
                                dependencies: dependencies,
                                onClose: { router.detailPlace = nil })
            } else {
                recentsCard
            }
        }
        .frame(maxWidth: .infinity)
        .background(.background)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 10, y: -2)
    }

    @ViewBuilder
    private var recentsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message = viewModel.locationMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .accessibilityIdentifier("map.locationMessage")
            }

            if !viewModel.recentSearches.isEmpty {
                Text(l10n: "map.recentSearches")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                ForEach(Array(viewModel.recentSearches.prefix(3).enumerated()), id: \.element.id) { index, recent in
                    Button {
                        router.showPlaceDetail(recent.place)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock")
                                .foregroundStyle(.tint)
                                .frame(width: 32, height: 32)
                                .background(Color.accentColor.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recent.place.displayName)
                                    .font(.body)
                                if let address = recent.place.address {
                                    Text(address)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(A11y.recentSearch(index))
                }
                .padding(.bottom, 8)
            }
        }
        .opacity(viewModel.recentSearches.isEmpty && viewModel.locationMessage == nil ? 0 : 1)
    }

    private var recenterButton: some View {
        Button {
            Task {
                await viewModel.refreshLocation()
                if let coordinate = viewModel.currentCoordinate {
                    camera = .region(coordinate.region())
                }
            }
        } label: {
            Image(systemName: "location.fill")
                .font(.title3)
                .padding(14)
                .background(.background, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .padding(.bottom, 220)
        .accessibilityIdentifier(A11y.recenterButton)
        .accessibilityLabel(L10n.string("map.recenter"))
    }
}
