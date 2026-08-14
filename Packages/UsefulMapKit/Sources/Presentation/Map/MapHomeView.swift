import Domain
import MapKit
import SwiftUI

/// S01 地図ホーム。
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
            VStack(spacing: 12) {
                searchBar
                quickChips
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            VStack(spacing: 0) {
                Spacer()
                recentsCard
            }
        }
        .overlay(alignment: .bottomTrailing) { recenterButton }
        .task { await viewModel.onAppear() }
        .onChange(of: viewModel.currentCoordinate) { _, coordinate in
            guard let coordinate else { return }
            camera = .region(coordinate.region())
        }
        .sheet(isPresented: $router.isSearchPresented) {
            SearchView(dependencies: dependencies,
                       center: viewModel.currentCoordinate) { place in
                viewModel.refreshStoredData()
                router.showPlaceDetail(place)
            }
        }
        .sheet(item: $router.detailPlace) { place in
            PlaceDetailView(place: place, dependencies: dependencies)
                .presentationDetents([.medium, .large])
        }
    }

    private var map: some View {
        Map(position: $camera) {
            UserAnnotation()
            if let place = router.detailPlace {
                Marker(place.displayName, coordinate: place.coordinate.mapCoordinate)
                    .tint(.red)
            }
        }
        .mapControls { MapCompass() }
        .ignoresSafeArea(edges: .top)
        .accessibilityIdentifier("map.canvas")
        .accessibilityLabel("地図")
    }

    private var searchBar: some View {
        Button {
            router.isSearchPresented = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text("目的地を検索")
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
        .accessibilityLabel("目的地を検索")
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

    private var recenterButton: some View {
        Button {
            Task { await viewModel.refreshLocation() }
        } label: {
            Image(systemName: "location.fill")
                .font(.title3)
                .padding(14)
                .background(.background, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .padding(.bottom, recentsCardHeight + 24)
        .accessibilityIdentifier(A11y.recenterButton)
        .accessibilityLabel("現在地へ戻る")
    }

    private var recentsCardHeight: CGFloat {
        viewModel.recentSearches.isEmpty ? 0 : 180
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
                Text("最近の検索")
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 10, y: -2)
        .opacity(viewModel.recentSearches.isEmpty && viewModel.locationMessage == nil ? 0 : 1)
    }
}
