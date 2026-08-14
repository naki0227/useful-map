import Domain
import SwiftUI

/// S05 経路編集。出発地・目的地・経由地・移動手段・時刻条件を変更する。
public struct RouteEditorView: View {
    @ObservedObject private var viewModel: RouteCompareViewModel
    private let dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss

    @State private var searchTarget: SearchTarget?
    @State private var pendingDate: Date

    private enum SearchTarget: String, Identifiable {
        case origin
        case destination
        case waypoint

        var id: String { rawValue }

        var title: String {
            switch self {
            case .origin: return "出発地"
            case .destination: return "目的地"
            case .waypoint: return "経由地"
            }
        }
    }

    public init(viewModel: RouteCompareViewModel, dependencies: AppDependencies) {
        self.viewModel = viewModel
        self.dependencies = dependencies
        _pendingDate = State(initialValue: viewModel.query.requestedDate ?? dependencies.now())
    }

    public var body: some View {
        NavigationStack {
            Form {
                endpointsSection
                waypointsSection
                modeSection
                timeSection
            }
            .navigationTitle("経路を編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .accessibilityIdentifier(A11y.closeEditorButton)
                }
            }
            .sheet(item: $searchTarget) { target in
                SearchView(dependencies: dependencies, center: nil) { place in
                    apply(place, to: target)
                }
            }
        }
    }

    private var endpointsSection: some View {
        Section("出発地・目的地") {
            Button {
                searchTarget = .origin
            } label: {
                LabeledContent("出発地", value: viewModel.query.origin.displayName)
            }
            .accessibilityIdentifier("routeEditor.origin")

            Button {
                searchTarget = .destination
            } label: {
                LabeledContent("目的地", value: viewModel.query.destination.displayName)
            }
            .accessibilityIdentifier("routeEditor.destination")

            Button {
                viewModel.setOrigin(.currentLocation)
            } label: {
                Label("出発地を現在地にする", systemImage: "location.circle")
            }
            .accessibilityIdentifier("routeEditor.useCurrentLocation")

            Button {
                viewModel.swapEndpoints()
            } label: {
                Label("出発地と目的地を入れ替える", systemImage: "arrow.up.arrow.down")
            }
            .accessibilityIdentifier(A11y.swapButton)
        }
    }

    private var waypointsSection: some View {
        Section("経由地") {
            if viewModel.query.waypoints.isEmpty {
                Text("経由地なし")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.query.waypoints) { waypoint in
                    Text(waypoint.displayName)
                }
                .onDelete { offsets in
                    for index in offsets {
                        viewModel.removeWaypoint(id: viewModel.query.waypoints[index].id)
                    }
                }
                .onMove { source, destination in
                    viewModel.moveWaypoints(fromOffsets: source, toOffset: destination)
                }
            }
            Button {
                searchTarget = .waypoint
            } label: {
                Label("経由地を追加", systemImage: "plus")
            }
            .accessibilityIdentifier(A11y.addWaypointButton)
        }
    }

    private var modeSection: some View {
        Section("移動手段") {
            Picker("移動手段", selection: Binding(
                get: { viewModel.modeFilter },
                set: { viewModel.modeFilter = $0 }
            )) {
                ForEach(RouteCompareViewModel.ModeFilter.allCases) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("routeEditor.mode")
        }
    }

    private var timeSection: some View {
        Section("時刻条件") {
            Picker("条件", selection: Binding(
                get: { viewModel.query.timePreference },
                set: { viewModel.setTimePreference($0, date: pendingDate) }
            )) {
                ForEach(TimePreference.allCases) { preference in
                    Text(preference.displayName).tag(preference)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("routeEditor.timePreference")

            if viewModel.query.timePreference.requiresDate {
                DatePicker("日時", selection: Binding(
                    get: { viewModel.query.requestedDate ?? pendingDate },
                    set: { newValue in
                        pendingDate = newValue
                        viewModel.setTimePreference(viewModel.query.timePreference, date: newValue)
                    }
                ))
                .accessibilityIdentifier("routeEditor.date")
            }
        }
    }

    private func apply(_ place: Place, to target: SearchTarget) {
        switch target {
        case .origin:
            viewModel.setOrigin(.place(place))
        case .destination:
            viewModel.setDestination(place)
        case .waypoint:
            viewModel.addWaypoint(place)
        }
        searchTarget = nil
    }
}
