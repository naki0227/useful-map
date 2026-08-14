import Domain
import MapKit
import SwiftUI

/// S03 場所詳細。主要 CTA は「経路」。運賃・乗換・路線情報は表示しない（仕様書 S03）。
public struct PlaceDetailView: View {
    private let place: Place
    private let dependencies: AppDependencies
    /// 下のシートに埋め込まれるため、閉じる動作は呼び出し側が持つ。
    private let onClose: () -> Void
    @StateObject private var viewModel: SavedViewModel
    @EnvironmentObject private var router: AppRouter
    @State private var isLabelPickerPresented = false

    /// 現在地の実座標は RoutePlanViewModel が取得のたびに解決する。
    /// ここでは「現在地である」という印だけを持った仮のノードを渡す。
    private var currentLocationPlace: Place {
        Place(name: RouteEndpoint.currentLocation.displayName, coordinate: place.coordinate)
    }

    public init(place: Place,
                dependencies: AppDependencies,
                onClose: @escaping () -> Void = {}) {
        self.place = place
        self.dependencies = dependencies
        self.onClose = onClose
        _viewModel = StateObject(wrappedValue: SavedViewModel(dependencies: dependencies))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            actions
            addressRow
            mapPreview
            Spacer(minLength: 0)
        }
        .padding(20)
        .onAppear { viewModel.refresh() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(place.displayName)
                    .font(.title2.bold())
                    .accessibilityIdentifier(A11y.placeTitle)
                if let address = place.address {
                    Text(address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .padding(10)
                    .background(Color.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("placeDetail.close"))
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                router.showRoute(
                    RoutePlan.simple(origin: RouteNode(place: currentLocationPlace,
                                                       kind: .origin,
                                                       isCurrentLocation: true),
                                     destination: RouteNode(place: place, kind: .destination),
                                     mode: .transit),
                    dependencies: dependencies)
            } label: {
                Label(L10n.string("placeDetail.route"), systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(A11y.routeButton)

            Button {
                // 未保存ならラベルを選んで保存、保存済みならその場で解除する。
                if viewModel.isSaved(place) {
                    viewModel.toggleSave(place)
                } else {
                    isLabelPickerPresented = true
                }
            } label: {
                Label(saveButtonTitle, systemImage: saveButtonSymbol)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(A11y.saveButton)
            .confirmationDialog(L10n.string("placeDetail.saveTitle"),
                                isPresented: $isLabelPickerPresented,
                                titleVisibility: .visible) {
                ForEach(SavedPlace.Label.allCases, id: \.self) { label in
                    Button(label == .other
                           ? L10n.string("placeDetail.saveOnly")
                           : L10n.string("placeDetail.saveAsLabel", label.displayName)) {
                        viewModel.save(place, label: label)
                    }
                    .accessibilityIdentifier(A11y.saveLabelOption(label.rawValue))
                }
                Button(L10n.string("search.cancel"), role: .cancel) {}
            }
        }
    }

    private var saveButtonTitle: String {
        guard let label = viewModel.label(for: place) else { return L10n.string("placeDetail.save") }
        return label == .other ? L10n.string("placeDetail.saved") : label.displayName
    }

    private var saveButtonSymbol: String {
        guard let label = viewModel.label(for: place) else { return "bookmark" }
        return label == .other ? "bookmark.fill" : label.symbolName
    }

    private var addressRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .foregroundStyle(.tint)
            Text(place.address ?? "\(place.coordinate.latitudeString), \(place.coordinate.longitudeString)")
                .font(.subheadline)
            Spacer()
        }
    }

    private var mapPreview: some View {
        Map(initialPosition: .region(place.coordinate.region(spanMeters: 800))) {
            Marker(place.displayName, coordinate: place.coordinate.mapCoordinate)
                .tint(.red)
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
