import Domain
import SwiftUI

/// 下部シートに出す経路の要約。合計時間と、Google マップへの委譲だけを持つ。
///
/// 区間の内訳は上部の連鎖表示が担うので、ここでは重複させない。
struct RoutePlanSummaryView: View {
    @ObservedObject var viewModel: RoutePlanViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            presetPicker

            if let message = viewModel.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(A11y.routeError)
            }

            if let outcome = viewModel.lastOpenOutcome {
                openStatus(outcome)
            }

            Text(l10n: "route.footnote")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let total = viewModel.totalTravelTime {
                let parts = Formatters.durationParts(total)
                Text(parts.value)
                    .font(.system(size: 34, weight: .semibold))
                Text(parts.unit)
                    .font(.headline)
            } else if viewModel.isLoading {
                ProgressView()
            } else {
                Text(l10n: "route.segment.unavailable")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if let range = viewModel.overallTimeRange {
                Text(range)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(A11y.planTotal)
        .accessibilityValue(viewModel.totalTravelTime.map { Formatters.duration($0) } ?? "")
    }

    /// 全区間を一括で組み直すプリセット。ユーザーが決めた区間は変わらない。
    private var presetPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RoutePlanViewModel.Preset.allCases) { preset in
                    let isSelected = viewModel.activePreset == preset
                    Button {
                        viewModel.applyPreset(preset)
                    } label: {
                        Label(preset.displayName, systemImage: preset.symbolName)
                            .font(.subheadline)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(isSelected ? Color.accentColor.opacity(0.15)
                                                   : Color.secondary.opacity(0.10),
                                        in: Capsule())
                            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(A11y.preset(preset.id))
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
        }
    }

    private func openStatus(_ outcome: DetailOpenOutcome) -> some View {
        let text: String
        switch outcome {
        case .openedPrimary: text = L10n.string("route.open.primary")
        case .openedFallback: text = L10n.string("route.open.fallback")
        case .failed: text = L10n.string("route.open.failed")
        }
        return HStack(spacing: 8) {
            Image(systemName: outcome == .failed ? "exclamationmark.triangle" : "arrow.up.forward.app")
            Text(text)
                .font(.footnote)
            Spacer()
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(A11y.lastOpenedURL)
        .accessibilityLabel(text)
        // E2E から生成 URL を検証するために値として持たせる。
        .accessibilityValue(viewModel.lastOpenedURL ?? "")
    }
}
