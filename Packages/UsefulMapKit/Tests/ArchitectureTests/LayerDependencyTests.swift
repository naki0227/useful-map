import Foundation
import Testing

/// アーキテクチャテスト。
///
/// 依存方向の第一の防壁は SwiftPM のモジュール境界（許可されていない import はビルドが通らない）。
/// このテストは第二の防壁で、
///   - Package.swift 側の依存宣言がうっかり追加されていないか
///   - 各層が使ってよいシステムフレームワークの範囲を超えていないか
/// をソースの import 文から静的に検査する。
///
/// （Harmonize などの構造解析ツールを入れる場合もこの位置づけの層に置く。
///  ここでは外部依存を増やさず、SwiftSyntax 無しで成立する範囲に留めている）
@Suite("アーキテクチャ")
struct LayerDependencyTests {
    // MARK: - ルール

    /// 自作モジュールの許可された依存先。
    static let allowedModuleDependencies: [String: Set<String>] = [
        "Domain": [],
        "Data": ["Domain"],
        "Infrastructure": ["Domain", "Data"],
        "Presentation": ["Domain"]
    ]

    /// 各層が触れてよいシステムフレームワーク。
    static let allowedSystemFrameworks: [String: Set<String>] = [
        // Domain は純粋なモデルとポリシー。UI も地図 SDK も知らない。
        "Domain": ["Foundation"],
        // Data は永続化と外部 URL 契約。UI にも地図 SDK にも依存しない。
        "Data": ["Foundation", "Combine"],
        // Infrastructure はプラットフォーム SDK との境界。ここだけが MapKit / CoreLocation / UIKit を知る。
        "Infrastructure": ["Foundation", "MapKit", "CoreLocation", "UIKit", "Contacts"],
        // Presentation は SwiftUI と地図表示。永続化や位置情報 SDK は直接触らない。
        "Presentation": ["Foundation", "SwiftUI", "MapKit", "Combine"]
    ]

    static let allModules = Set(allowedModuleDependencies.keys)

    // MARK: - テスト

    @Test("各モジュールは許可された自作モジュールしか import しない",
          arguments: ["Domain", "Data", "Infrastructure", "Presentation"])
    func moduleDependencies(module: String) throws {
        let allowed = try #require(Self.allowedModuleDependencies[module])
        for file in try SourceScanner.files(in: module) {
            let violations = file.imports
                .filter { Self.allModules.contains($0) && $0 != module }
                .filter { !allowed.contains($0) }
            #expect(violations.isEmpty,
                    "\(module)/\(file.name) が許可されていないモジュールを import している: \(violations.sorted())")
        }
    }

    @Test("各モジュールは許可されたシステムフレームワークしか import しない",
          arguments: ["Domain", "Data", "Infrastructure", "Presentation"])
    func systemFrameworks(module: String) throws {
        let allowed = try #require(Self.allowedSystemFrameworks[module])
        for file in try SourceScanner.files(in: module) {
            let violations = file.imports
                .filter { !Self.allModules.contains($0) }
                .filter { !allowed.contains($0) }
            #expect(violations.isEmpty,
                    "\(module)/\(file.name) が想定外のフレームワークを import している: \(violations.sorted())")
        }
    }

    @Test("Domain は UI・地図・位置情報 SDK を一切知らない")
    func domainIsPure() throws {
        let forbidden: Set<String> = ["SwiftUI", "UIKit", "MapKit", "CoreLocation", "Combine"]
        for file in try SourceScanner.files(in: "Domain") {
            #expect(file.imports.isDisjoint(with: forbidden),
                    "Domain/\(file.name) が \(file.imports.intersection(forbidden).sorted()) に依存している")
        }
    }

    @Test("Presentation は Data / Infrastructure の実装を直接参照しない")
    func presentationDependsOnPortsOnly() throws {
        for file in try SourceScanner.files(in: "Presentation") {
            #expect(!file.imports.contains("Data"), "Presentation/\(file.name) が Data を import している")
            #expect(!file.imports.contains("Infrastructure"),
                    "Presentation/\(file.name) が Infrastructure を import している")
        }
    }

    @Test("Google 内部 URL 形式の知識は Data 層の限られたファイルに閉じている")
    func googleURLKnowledgeIsIsolated() throws {
        // 非公開仕様は GoogleMapsURLBuilder と Contract Watcher の外へ漏らさない（非機能要件 14）。
        let markers = ["!8j", "!7e2", "!3e", "/maps/dir/"]
        for module in Self.allModules {
            for file in try SourceScanner.files(in: module) {
                let leaks = markers.filter { file.contents.contains($0) }
                let isAllowedFile = module == "Data"
                    && ["GoogleMapsURLBuilder.swift",
                        "GoogleMapsDataParam.swift",
                        "GoogleTimestamp.swift",
                        "GoogleMapsURLFormat.swift",
                        // format.json から生成される形式定義。
                        "GoogleMapsURLFormat+Generated.swift"].contains(file.name)
                if !isAllowedFile {
                    #expect(leaks.isEmpty,
                            "\(module)/\(file.name) に Google 内部 URL 形式の知識が漏れている: \(leaks)")
                }
            }
        }
    }

    @Test("ViewModel は MainActor 上で動く")
    func viewModelsAreMainActor() throws {
        let viewModels = try SourceScanner.files(in: "Presentation")
            .filter { $0.name.hasSuffix("ViewModel.swift") }
        #expect(!viewModels.isEmpty)
        for file in viewModels {
            #expect(file.contents.contains("@MainActor"), "\(file.name) に @MainActor が無い")
        }
    }

    @Test("import 文は各ファイルの先頭にまとまっている（スキャナの前提を保証する）")
    func importsAreAtTop() throws {
        for module in Self.allModules {
            for file in try SourceScanner.files(in: module) {
                let lines = file.contents.components(separatedBy: .newlines)
                guard let lastImport = lines.lastIndex(where: { $0.hasPrefix("import ") || $0.contains(" import ") }),
                      let firstDeclaration = lines.firstIndex(where: {
                          $0.hasPrefix("public ") || $0.hasPrefix("struct ")
                              || $0.hasPrefix("final ") || $0.hasPrefix("enum ") || $0.hasPrefix("extension ")
                      }) else { continue }
                #expect(lastImport < firstDeclaration, "\(module)/\(file.name) の import 位置が想定と違う")
            }
        }
    }
}

/// Sources 配下の Swift ファイルを読み、import 文を抽出する。
enum SourceScanner {
    struct SourceFile {
        let name: String
        let contents: String
        let imports: Set<String>
    }

    struct ScanError: Error, CustomStringConvertible {
        let description: String
    }

    /// テストバイナリの位置からリポジトリ内の Sources を辿る。
    static func sourcesRoot() throws -> URL {
        // #filePath は Tests/ArchitectureTests/LayerDependencyTests.swift を指す。
        let thisFile = URL(fileURLWithPath: #filePath)
        let packageRoot = thisFile
            .deletingLastPathComponent()  // ArchitectureTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // UsefulMapKit
        let sources = packageRoot.appendingPathComponent("Sources")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw ScanError(description: "Sources ディレクトリが見つからない: \(sources.path)")
        }
        return sources
    }

    static func files(in module: String) throws -> [SourceFile] {
        let root = try sourcesRoot().appendingPathComponent(module)
        guard let enumerator = FileManager.default.enumerator(at: root,
                                                              includingPropertiesForKeys: nil) else {
            throw ScanError(description: "\(module) を走査できない")
        }
        var result: [SourceFile] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let contents = try String(contentsOf: url, encoding: .utf8)
            result.append(SourceFile(name: url.lastPathComponent,
                                     contents: contents,
                                     imports: parseImports(contents)))
        }
        guard !result.isEmpty else {
            throw ScanError(description: "\(module) に Swift ファイルが無い")
        }
        return result
    }

    /// `import X` / `@preconcurrency import X` / `import struct X.Y` に対応する。
    static func parseImports(_ contents: String) -> Set<String> {
        var modules: Set<String> = []
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let range = line.range(of: "import ") else { continue }
            // コメント行や文字列中の "import" は無視する。
            let prefix = line[line.startIndex..<range.lowerBound]
            guard !prefix.contains("//"), prefix.isEmpty || prefix.hasPrefix("@") else { continue }
            let rest = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            // `import struct Foundation.Data` のような形式は最後の要素の先頭がモジュール名。
            let tokens = rest.split(separator: " ")
            guard let last = tokens.last else { continue }
            let moduleName = last.split(separator: ".").first.map(String.init) ?? String(last)
            modules.insert(moduleName)
        }
        return modules
    }
}
