/**
 * format.json から Swift の形式定義を生成する。
 *
 *   node src/generate-swift.mjs          … 生成して書き込む
 *   node src/generate-swift.mjs --check  … 生成結果と現物が一致するか確認する（CI 用）
 *
 * 自動修復はこの生成器を通して Swift まで更新するため、PR には
 * format.json と Swift の両方の差分が載る。人間はその PR をレビューしてマージする。
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadFormat } from './urlBuilder.mjs';

const here = dirname(fileURLToPath(import.meta.url));
export const generatedSwiftPath = join(
  here, '..', '..',
  'Packages/UsefulMapKit/Sources/Data/GoogleMapsURLFormat+Generated.swift'
);

const PLACEHOLDERS = new Set([
  'longitude', 'latitude', 'timeMode', 'timestamp', 'modeCode', 'innerCount', 'outerCount'
]);

/** `{longitude}` のようなプレースホルダなら中身を返す。定数なら null。 */
function placeholderName(value) {
  const match = /^\{(\w+)\}$/.exec(String(value));
  if (!match) return null;
  if (!PLACEHOLDERS.has(match[1])) {
    throw new Error(`未知のプレースホルダ: ${match[1]}`);
  }
  return match[1];
}

function swiftToken(token, indent) {
  const name = placeholderName(token.value);
  const value = name ? `.placeholder(.${name})` : `.constant("${token.value}")`;
  return `${indent}FormatToken(group: ${token.group}, kind: "${token.kind}", value: ${value})`;
}

function swiftTokenArray(tokens, indent) {
  return tokens.map((token) => swiftToken(token, indent)).join(',\n');
}

function swiftDictionary(map, indent) {
  return Object.entries(map)
    .map(([key, value]) => `${indent}"${key}": "${value}"`)
    .join(',\n');
}

export function generate(format = loadFormat()) {
  return `// このファイルは自動生成されています。直接編集しないでください。
//
// 生成元 : contract-watch/format.json
// 生成器 : contract-watch/src/generate-swift.mjs
// 再生成 : make generate-format
//
// Google Maps の非公開 data= 形式が変わった場合、契約監視 CI が最小差分を
// format.json へ当ててから、この生成器で Swift まで更新して PR を作る。

import Foundation

enum GoogleMapsURLFormat {
    static let host = "${format.host}"
    static let pathPrefix = "${format.pathPrefix}"
    static let dataPrefix = "${format.dataPrefix}"
    static let coordinatePrecision = ${format.coordinatePrecision}

    /// 全体を包むブロック。
    static let wrapper: [FormatToken] = [
${swiftTokenArray([format.wrapper.outer, format.wrapper.inner], '        ')}
    ]

    /// 地点 1 つぶんのブロック。
    static let placeBlock: [FormatToken] = [
${swiftTokenArray(format.placeBlock, '        ')}
    ]

    /// 時刻条件のブロック。
    static let timeBlock: [FormatToken] = [
${swiftTokenArray(format.timeBlock, '        ')}
    ]

    /// 移動手段のトークン。
    static let modeToken: FormatToken =
${swiftToken(format.modeToken, '        ')}

    /// 出発指定 / 到着指定の値。
    static let timeMode: [String: String] = [
${swiftDictionary(format.timeMode, '        ')}
    ]

    /// 移動手段コード（キーは TransportMode の rawValue）。
    static let modeCode: [String: String] = [
${swiftDictionary(format.modeCode, '        ')}
    ]
}
`;
}

function main() {
  const generated = generate();
  const check = process.argv.includes('--check');

  if (check) {
    let current = '';
    try {
      current = readFileSync(generatedSwiftPath, 'utf8');
    } catch {
      console.error('生成済みファイルが見つからない。`make generate-format` を実行すること。');
      process.exitCode = 1;
      return;
    }
    if (current !== generated) {
      console.error('format.json と Swift の生成結果がずれている。`make generate-format` を実行すること。');
      process.exitCode = 1;
      return;
    }
    console.log('生成済みファイルは最新。');
    return;
  }

  writeFileSync(generatedSwiftPath, generated, 'utf8');
  console.log(`generated: ${generatedSwiftPath}`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
