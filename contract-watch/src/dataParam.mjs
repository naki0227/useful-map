/**
 * Google Maps `data=` パラメータのトークン操作。
 * Swift 側 GoogleMapsDataParam と同じ意味論を JS でも持つ（構造単位で比較するため）。
 */

/** `!4m18!1m5...` を [{group, kind, value}] へ分解する。形式不正なら null。 */
export function parseData(raw) {
  if (!raw || !raw.startsWith('!')) return null;
  const tokens = [];
  for (const chunk of raw.slice(1).split('!')) {
    if (chunk.length === 0) return null;
    const match = /^(\d+)([a-z])(.*)$/.exec(chunk);
    if (!match) return null;
    tokens.push({ group: Number(match[1]), kind: match[2], value: match[3] });
  }
  return tokens;
}

export function encodeData(tokens) {
  return tokens.map((token) => `!${token.group}${token.kind}${token.value}`).join('');
}

export function tokenKey(token) {
  return `${token.group}${token.kind}`;
}

export function tokenString(token) {
  return `!${token.group}${token.kind}${token.value}`;
}

/** ブロックヘッダ（!4m18 のように後続 n トークンを束ねるもの）か。 */
export function isBlockHeader(token) {
  return token.kind === 'm';
}

/** ブロック長が後続トークン数と整合しているか。 */
export function isStructurallyConsistent(tokens) {
  const walk = (start, count) => {
    let index = start;
    const end = start + count;
    if (end > tokens.length) return false;
    while (index < end) {
      const token = tokens[index];
      index += 1;
      if (!isBlockHeader(token)) continue;
      const length = Number(token.value);
      if (!Number.isInteger(length) || index + length > end) return false;
      if (!walk(index, length)) return false;
      index += length;
    }
    return index === end;
  };
  return walk(0, tokens.length);
}

/** URL から data= 部分を取り出す。 */
export function extractData(url) {
  const marker = '/data=';
  const index = url.indexOf(marker);
  if (index < 0) return null;
  const tail = url.slice(index + marker.length);
  // ?hl=ja のようなクエリが付く場合があるので落とす。
  return tail.split('?')[0].split('#')[0];
}
