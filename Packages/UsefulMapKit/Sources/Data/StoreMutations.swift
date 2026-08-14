import Foundation

/// 保存系の共通ルール。
/// 「同一 ID を除いて先頭へ挿す（＝新しい順・重複なし）」「上限で打ち切る」という
/// 振る舞いを 1 箇所に置き、各ストア実装で重複させない。
enum StoreMutations {
    static func upsert<Element: Identifiable>(_ entry: Element,
                                              into list: inout [Element],
                                              limit: Int? = nil) {
        list.removeAll { $0.id == entry.id }
        list.insert(entry, at: 0)
        if let limit, list.count > limit {
            list = Array(list.prefix(limit))
        }
    }

    static func remove<Element: Identifiable>(id: Element.ID, from list: inout [Element]) {
        list.removeAll { $0.id == id }
    }
}
