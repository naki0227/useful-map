import Domain
import MapKit
import SwiftUI

/// S04 経路比較。
public struct RouteCompareView: View {
    private let dependencies: AppDependencies
    @StateObject private var viewModel: RouteCompareViewModel
    @EnvironmentObject private var router: AppRouter
    @State private var isEditorPresented = false

    public init(query: RouteQuery, dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: RouteCompareViewModel(query: query, dependencies: dependencies))
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            modePicker
            Divider()
            map
            results
        }
        .task { await viewModel.load().value }
        .sheet(isPresented: $isEditorPresented) {
            RouteEditorView(viewModel: viewModel, dependencies: dependencies)
        }
    }

    // MARK: - ヘッダ

    private var header: some View {
        Button {
            isEditorPresented = true
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                endpointRow(symbol: "smallcircle.filled.circle", text: viewModel.query.origin.displayName)
                ForEach(viewModel.query.waypoints) { waypoint in
                    endpointRow(symbol: "circle.dotted", text: waypoint.displayName)
                }
                endpointRow(symbol: "mappin.circle.fill", text: viewModel.query.destination.displayName)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(A11y.editRouteButton)
        .accessibilityLabel("経路の条件を編集")
        .accessibilityValue(viewModel.title)
    }

    private func endpointRow(symbol: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
            Text(text)
                .font(.body)
                .lineLimit(1)
            Spacer()
        }
        .accessibilityIdentifier(A11y.routeCompareTitle)
    }

    private var modePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RouteCompareViewModel.ModeFilter.allCases) { filter in
                    let isSelected = filter == viewModel.modeFilter
                    Button {
                        viewModel.modeFilter = filter
                    } label: {
                        Label(filter.displayName, systemImage: filter.symbolName)
                            .font(.subheadline)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.10),
                                        in: Capsule())
                            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(A11y.modeFilter(filter.id))
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - 地図

    private var map: some View {
        Map {
            ForEach(viewModel.options.filter { !$0.geometry.isEmpty }) { option in
                MapPolyline(coordinates: option.geometry.map(\.mapCoordinate))
                    .stroke(option.id == viewModel.recommendedID ? Color.accentColor : Color.secondary,
                            lineWidth: option.id == viewModel.recommendedID ? 6 : 3)
            }
            Marker(viewModel.query.destination.displayName,
                   coordinate: viewModel.query.destination.coordinate.mapCoordinate)
                .tint(.red)
        }
        .frame(height: 180)
        .accessibilityHidden(true)
    }

    // MARK: - 候補一覧

    @ViewBuilder
    private var results: some View {
        if viewModel.isLoading && viewModel.options.isEmpty {
            ProgressView("経路を取得中")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = viewModel.errorMessage, viewModel.options.isEmpty {
            ContentUnavailableView("経路を取得できません",
                                   systemImage: "exclamationmark.triangle",
                                   description: Text(message))
                .accessibilityIdentifier(A11y.routeError)
        } else if viewModel.showsEmptyState {
            ContentUnavailableView("利用可能な経路なし",
                                   systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                   description: Text("条件を変えて再検索してください。"))
                .accessibilityIdentifier(A11y.routeEmpty)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(viewModel.options.enumerated()), id: \.element.id) { index, option in
                        RouteOptionCard(option: option,
                                        index: index,
                                        isRecommended: option.id == viewModel.recommendedID) {
                            Task { await viewModel.openDetail(for: option) }
                        }
                    }
                    openStatus
                    footnote
                }
                .padding(16)
            }
        }
    }

    @ViewBuilder
    private var openStatus: some View {
        if let outcome = viewModel.lastOpenOutcome {
            HStack(spacing: 8) {
                Image(systemName: outcome == .failed ? "exclamationmark.triangle" : "arrow.up.forward.app")
                Text(statusText(for: outcome))
                    .font(.footnote)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.top, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(A11y.lastOpenedURL)
            .accessibilityLabel(statusText(for: outcome))
            // E2E から生成 URL を検証するために値として持たせる。
            .accessibilityValue(viewModel.lastOpenedURL ?? "")
        }
    }

    private func statusText(for outcome: DetailOpenOutcome) -> String {
        switch outcome {
        case .openedPrimary: return "Google Maps を時刻付きリンクで開きました"
        case .openedFallback: return "Google Maps を公式リンクで開きました（時刻条件は保証されません）"
        case .failed: return "Google Maps を開けませんでした"
        }
    }

    private var footnote: some View {
        Text("所要時間は交通状況により前後する場合があります。運賃・乗換の詳細は Google Maps で確認してください。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

/// 比較カード。共通必須表示は所要時間、公共交通のみ出発 / 到着時刻と「詳細」を出す。
struct RouteOptionCard: View {
    let option: RouteOption
    let index: Int
    let isRecommended: Bool
    let onDetail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                let parts = Formatters.durationParts(option.expectedTravelTime)
                Text(parts.value)
                    .font(.system(size: 34, weight: .semibold))
                Text(parts.unit)
                    .font(.headline)
                Label(option.mode.displayName, systemImage: option.mode.symbolName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if isRecommended {
                    Text("おすすめ")
                        .font(.caption.bold())
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }

            HStack(spacing: 12) {
                if let range = Formatters.timeRange(departure: option.departureDate, arrival: option.arrivalDate) {
                    Text(range)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let distance = option.distance {
                    Text(Formatters.distance(distance))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if option.supportsExternalDetail {
                    Button(action: onDetail) {
                        Label("詳細", systemImage: "arrow.up.forward.square")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(A11y.detailButton(index))
                    .accessibilityHint("Google Maps で運賃や乗換を確認します")
                }
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isRecommended ? Color.accentColor : Color.secondary.opacity(0.25),
                        lineWidth: isRecommended ? 2 : 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11y.routeCard(index))
        .accessibilityLabel("\(option.mode.displayName) \(Formatters.duration(option.expectedTravelTime))")
    }
}
