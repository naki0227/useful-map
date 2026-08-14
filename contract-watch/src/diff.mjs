/**
 * data= の構造 diff と delta debugging（仕様書 9）。
 *
 * 単純な文字列 diff ではなく、トークン / ブロック単位で比較する。
 * 「壊れた」と分かっただけでは PR を作らず、最小の変更集合を探索して
 * 全 fixture が PASS した場合にのみ修正候補とする。
 */
import { parseData, tokenKey, tokenString } from './dataParam.mjs';

/**
 * 旧 URL と新（正解）URL の data= を突き合わせ、変更集合を求める。
 * 位置ではなく「同じ group+kind のトークン列」を対応付けるため、
 * 座標や timestamp のような可変値の違いは無視できる。
 */
export function structuralDiff(oldTokens, newTokens, { ignoreValues = [] } = {}) {
  const changes = [];
  const oldByKey = groupByKey(oldTokens);
  const newByKey = groupByKey(newTokens);
  const keys = new Set([...Object.keys(oldByKey), ...Object.keys(newByKey)]);

  for (const key of [...keys].sort()) {
    const before = oldByKey[key] ?? [];
    const after = newByKey[key] ?? [];

    if (before.length === 0) {
      changes.push({ type: 'added', key, before: null, after: after.map(tokenString) });
      continue;
    }
    if (after.length === 0) {
      changes.push({ type: 'removed', key, before: before.map(tokenString), after: null });
      continue;
    }
    const beforeValues = before.map((token) => token.value);
    const afterValues = after.map((token) => token.value);
    if (ignoreValues.includes(key)) continue;
    if (JSON.stringify(beforeValues) !== JSON.stringify(afterValues)) {
      changes.push({
        type: 'changed',
        key,
        before: before.map(tokenString),
        after: after.map(tokenString)
      });
    }
  }
  return changes;
}

function groupByKey(tokens) {
  const result = {};
  for (const token of tokens) {
    const key = tokenKey(token);
    (result[key] ??= []).push(token);
  }
  return result;
}

export function diffURLs(oldURL, newURL, options) {
  const oldTokens = parseData(extract(oldURL));
  const newTokens = parseData(extract(newURL));
  if (!oldTokens || !newTokens) return null;
  return structuralDiff(oldTokens, newTokens, options);
}

function extract(url) {
  const index = url.indexOf('/data=');
  return index < 0 ? '' : url.slice(index + '/data='.length).split('?')[0];
}

/**
 * delta debugging（ddmin の簡易版）。
 * 変更集合のうち「これだけ当てれば直る」最小の部分集合を、
 * 分割 → 検証 → 縮小 の繰り返しで探す。
 *
 * @param {Array} changes 候補となる変更集合
 * @param {(subset: Array) => Promise<boolean>} test subset を適用したとき PASS するか
 * @returns {Promise<Array|null>} 最小の変更集合（見つからなければ null）
 */
export async function minimizeChangeSet(changes, test) {
  if (changes.length === 0) return null;
  if (!(await test(changes))) return null; // 全部当てても直らないなら修復不能

  let current = [...changes];
  let granularity = 2;

  while (current.length >= 2) {
    const chunks = split(current, Math.min(granularity, current.length));
    let reduced = false;

    // まず「部分集合だけで直るか」を試す。
    for (const chunk of chunks) {
      if (await test(chunk)) {
        current = chunk;
        granularity = 2;
        reduced = true;
        break;
      }
    }
    if (reduced) continue;

    // 次に「補集合（1 チャンクを取り除いたもの）で直るか」を試す。
    for (const chunk of chunks) {
      const complement = current.filter((change) => !chunk.includes(change));
      if (complement.length > 0 && (await test(complement))) {
        current = complement;
        granularity = Math.max(granularity - 1, 2);
        reduced = true;
        break;
      }
    }
    if (reduced) continue;

    if (granularity >= current.length) break;
    granularity = Math.min(granularity * 2, current.length);
  }

  return current;
}

function split(items, count) {
  const size = Math.ceil(items.length / count);
  const chunks = [];
  for (let index = 0; index < items.length; index += size) {
    chunks.push(items.slice(index, index + size));
  }
  return chunks;
}

/**
 * 変更集合を format.json へ適用する。
 *
 * トークンの group+kind をキーに、定数値のトークンだけを差し替える
 * （座標や timestamp のようなプレースホルダは書き換えない）。
 *
 * 同じ group+kind が複数の場所に存在する場合（例: `!2m` は地点ブロックにも
 * 時刻ブロックにもある）、どちらを直すべきか決められない。
 * 当てずっぽうで両方書き換えると形式全体を壊すので、その差分は適用しない。
 * 適用できなかった差分があると `minimizeChangeSet` の検証が通らず、
 * 「自動修復不能」として Issue に回る。
 */
export function applyChanges(format, changes) {
  const next = structuredClone(format);

  for (const change of changes) {
    if (change.type !== 'changed' || !change.after || change.after.length === 0) continue;
    const parsed = parseData(change.after[0]);
    if (!parsed || parsed.length !== 1) continue;
    const token = parsed[0];

    const targets = constantTargets(next, token);
    // 一意に決まるときだけ書き換える。
    if (targets.length === 1) {
      targets[0].value = token.value;
    }
  }
  return next;
}

/** 差し替え候補となる定数トークンを、形式定義の中から集める。 */
function constantTargets(format, token) {
  const isConstant = (entry) => !String(entry.value).includes('{');
  const matches = (entry) => entry.group === token.group && entry.kind === token.kind && isConstant(entry);

  const targets = [];
  for (const section of ['placeBlock', 'timeBlock']) {
    for (const entry of format[section]) {
      if (matches(entry)) targets.push(entry);
    }
  }
  if (matches(format.modeToken)) targets.push(format.modeToken);
  for (const key of ['outer', 'inner']) {
    if (matches(format.wrapper[key])) targets.push(format.wrapper[key]);
  }
  return targets;
}
