import Domain
import Foundation

/// S02 検索。入力変更時は古い Task を cancel し、遅れて返った結果で UI を上書きしない（非機能要件 14）。
@MainActor
public final class SearchViewModel: ObservableObject {
    @Published public var queryText: String = ""
    @Published public private(set) var results: [Place] = []
    @Published public private(set) var isSearching = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var hasCompletedSearch = false

    private let searchService: PlaceSearching
    private let store: LocalStoring
    private let now: () -> Date
    private let debounce: Duration
    private let centerProvider: () -> Coordinate?

    private var searchTask: Task<Void, Never>?
    /// 遅延応答の取り違えを防ぐ世代番号。
    private var generation = 0

    public init(dependencies: AppDependencies, centerProvider: @escaping () -> Coordinate? = { nil }) {
        self.searchService = dependencies.searchService
        self.store = dependencies.store
        self.now = dependencies.now
        self.debounce = dependencies.searchDebounce
        self.centerProvider = centerProvider
    }

    deinit {
        searchTask?.cancel()
    }

    /// 検索結果 0 件を明示表示する条件（仕様書 13）。
    public var showsEmptyState: Bool {
        hasCompletedSearch && !isSearching && results.isEmpty && errorMessage == nil && !trimmedQuery.isEmpty
    }

    public var trimmedQuery: String {
        queryText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 入力変更。返り値の Task を await するとテストから完了を待てる。
    @discardableResult
    public func updateQuery(_ text: String) -> Task<Void, Never> {
        queryText = text
        searchTask?.cancel()
        generation += 1
        let currentGeneration = generation

        guard !trimmedQuery.isEmpty else {
            isSearching = false
            results = []
            errorMessage = nil
            hasCompletedSearch = false
            let task = Task { }
            searchTask = task
            return task
        }

        isSearching = true
        errorMessage = nil
        let task = Task { [weak self] in
            guard let self else { return }
            if self.debounce > .zero {
                try? await Task.sleep(for: self.debounce)
            }
            guard !Task.isCancelled else { return }
            await self.performSearch(generation: currentGeneration)
        }
        searchTask = task
        return task
    }

    /// デバウンスを挟まず即時に検索する（Enter 押下時）。
    @discardableResult
    public func searchNow() -> Task<Void, Never> {
        searchTask?.cancel()
        generation += 1
        let currentGeneration = generation
        guard !trimmedQuery.isEmpty else {
            let task = Task { }
            searchTask = task
            return task
        }
        isSearching = true
        errorMessage = nil
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performSearch(generation: currentGeneration)
        }
        searchTask = task
        return task
    }

    public func clear() {
        searchTask?.cancel()
        generation += 1
        queryText = ""
        results = []
        errorMessage = nil
        isSearching = false
        hasCompletedSearch = false
    }

    /// 候補選択時に最近の検索へ記録する。
    public func select(_ place: Place) {
        store.recordSearch(place, at: now())
    }

    private func performSearch(generation currentGeneration: Int) async {
        do {
            let found = try await searchService.search(query: trimmedQuery, around: centerProvider())
            guard currentGeneration == generation, !Task.isCancelled else { return }
            results = found
            errorMessage = nil
            hasCompletedSearch = true
            isSearching = false
        } catch let error as PlaceSearchError {
            guard currentGeneration == generation, !Task.isCancelled else { return }
            switch error {
            case .cancelled:
                // 新しい入力に置き換わっただけなので UI は触らない。
                return
            case let .failed(message):
                results = []
                errorMessage = message
                hasCompletedSearch = true
                isSearching = false
            }
        } catch {
            guard currentGeneration == generation, !Task.isCancelled else { return }
            results = []
            errorMessage = error.localizedDescription
            hasCompletedSearch = true
            isSearching = false
        }
    }
}
