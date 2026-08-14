import Domain
import SwiftUI

/// 経路の条件を、画面遷移なしでその場で編集する上部の連鎖表示。
///
///   ◉ 現在地
///   │ 🚶 12分            ← アイコンを押すと 公共交通 → 徒歩 → 車 と切り替わる
///   ▼
///   🚉 梅田駅
///   │ 🚋 21分 10:24-10:45 ← 時刻を押すと便を選び直せる
///   ▼
///   📍 目的地
struct RoutePlanChainView: View {
    @ObservedObject var viewModel: RoutePlanViewModel
    let dependencies: AppDependencies
    let center: Coordinate?
    let onPickOnMap: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(viewModel.nodes.enumerated()), id: \.element.id) { index, node in
                nodeRow(node, at: index)
                if index < viewModel.segments.count {
                    segmentRow(viewModel.segments[index], at: index)
                }
            }
            controls
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 2)
    }

    // MARK: - 地点

    @ViewBuilder
    private func nodeRow(_ node: RouteNode, at index: Int) -> some View {
        if viewModel.editingNodeIndex == index {
            InlinePlaceField(index: index,
                             title: nodeTitle(for: node, at: index),
                             placeholder: nodeTitle(for: node, at: index),
                             allowsCurrentLocation: index == 0,
                             dependencies: dependencies,
                             center: center,
                             onSelect: { viewModel.updatePlace($0, at: index) },
                             onUseCurrentLocation: { viewModel.useCurrentLocation(at: index) },
                             onPickOnMap: { onPickOnMap(index) },
                             onCancel: { viewModel.editingNodeIndex = nil })
        } else {
            Button {
                viewModel.editingNodeIndex = index
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: symbol(for: node, at: index))
                        .foregroundStyle(.tint)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(node.displayName)
                            .font(.body)
                            .lineLimit(1)
                        if node.isInferred {
                            Text(l10n: "route.node.inferred")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if canRemove(at: index) {
                        Button {
                            viewModel.removeNode(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.string("route.removeNode"))
                    }
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(A11y.node(index))
        }
    }

    private func canRemove(at index: Int) -> Bool {
        index > 0 && index < viewModel.nodes.count - 1
    }

    private func symbol(for node: RouteNode, at index: Int) -> String {
        if index == 0 { return "smallcircle.filled.circle" }
        if index == viewModel.nodes.count - 1 { return "mappin.circle.fill" }
        return TransitStopClassifier.kind(of: node.place).symbolName
    }

    private func nodeTitle(for node: RouteNode, at index: Int) -> String {
        if index == 0 { return L10n.string("editor.origin") }
        if index == viewModel.nodes.count - 1 { return L10n.string("editor.destination") }
        return L10n.string("editor.waypoint")
    }

    // MARK: - 区間

    private func segmentRow(_ segment: RouteSegment, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                // 縦線とモードアイコン。アイコンを押すと手段が切り替わる。
                ZStack {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 2)
                    Button {
                        viewModel.toggleMode(at: index)
                    } label: {
                        Image(systemName: segment.mode.symbolName)
                            .font(.footnote)
                            .frame(width: 28, height: 28)
                            .background(.background, in: Circle())
                            .overlay(Circle().stroke(Color.accentColor, lineWidth: viewModel.isLocked(at: index) ? 2 : 1))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(A11y.segmentMode(index))
                    .accessibilityLabel(segment.mode.displayName)
                    .accessibilityHint(L10n.string("route.segment.toggleHint"))
                }
                .frame(width: 20, height: 40)

                segmentSummary(segment, at: index)
                Spacer()
                detailButton(at: index)
            }

            if let update = viewModel.pendingUpdate(at: index) {
                pendingUpdateRow(update, at: index)
            }
        }
    }

    @ViewBuilder
    private func segmentSummary(_ segment: RouteSegment, at index: Int) -> some View {
        if let leg = segment.leg {
            Button {
                viewModel.beginPickingDeparture(at: index)
            } label: {
                HStack(spacing: 8) {
                    Text(Formatters.duration(leg.expectedTravelTime))
                        .font(.subheadline.weight(.medium))
                    if let range = viewModel.timeRange(at: index) {
                        Text(range)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if segment.mode == .transit {
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(segment.mode != .transit)
            .accessibilityIdentifier(A11y.segmentTime(index))
        } else if viewModel.isLoading {
            ProgressView().controlSize(.small)
        } else {
            Text(l10n: "route.segment.unavailable")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// 区間ごとの「詳細へ」。
    ///
    /// 区間は 2 地点なので、Google が経由地つき公共交通を扱えない制約に当たらない。
    /// 「この電車の詳細」「この徒歩の道順」をそれぞれ開ける。
    private func detailButton(at index: Int) -> some View {
        Button {
            Task { await viewModel.openDetail(at: index) }
        } label: {
            Image(systemName: "arrow.up.forward.square")
                .font(.footnote)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(A11y.detailButton(index))
        .accessibilityLabel(L10n.string("route.openDetail"))
        .accessibilityHint(L10n.string("route.detail.hint"))
    }

    /// 「ここが違いますが更新しますか？」の提示。勝手に置き換えない。
    private func pendingUpdateRow(_ update: PendingSegmentUpdate, at index: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string("route.update.title"))
                    .font(.caption.weight(.medium))
                Text(L10n.string("route.update.detail",
                                 Formatters.duration(update.current.expectedTravelTime),
                                 Formatters.duration(update.proposed.expectedTravelTime)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L10n.string("route.update.keep")) { viewModel.dismissUpdate(at: index) }
                .font(.caption)
                .buttonStyle(.bordered)
                .accessibilityIdentifier(A11y.updateKeep(index))
            Button(L10n.string("route.update.apply")) { viewModel.acceptUpdate(at: index) }
                .font(.caption)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(A11y.updateApply(index))
        }
        .padding(8)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .padding(.leading, 30)
    }

    // MARK: - ワンボタン操作

    private var controls: some View {
        HStack(spacing: 10) {
            controlButton(symbol: "arrow.up.arrow.down",
                          label: L10n.string("editor.swap"),
                          identifier: A11y.swapButtonInline) {
                viewModel.swapEndpoints()
            }
            controlButton(symbol: "location.fill",
                          label: L10n.string("editor.useCurrentLocation"),
                          identifier: A11y.currentLocationButton) {
                viewModel.useCurrentLocation()
            }
            controlButton(symbol: "plus",
                          label: L10n.string("editor.addWaypoint"),
                          identifier: A11y.addWaypointInline) {
                viewModel.beginAddingWaypoint()
            }
            Spacer()
            // 徒歩の速さをボタン 1 つで 普通 → 速い → 遅い と切り替える。
            Button {
                viewModel.cycleWalkingPace()
            } label: {
                Label(viewModel.walkingPace.displayName, systemImage: viewModel.walkingPace.symbolName)
                    .font(.caption)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(A11y.walkingPaceButton)
            .accessibilityLabel(L10n.string("route.walkingPace.label", viewModel.walkingPace.displayName))
        }
        .padding(.top, 6)
    }

    private func controlButton(symbol: String,
                               label: String,
                               identifier: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote)
                .frame(width: 36, height: 36)
                .background(Color.secondary.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
    }
}
