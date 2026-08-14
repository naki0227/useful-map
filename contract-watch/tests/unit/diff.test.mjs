import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyChanges, minimizeChangeSet, structuralDiff } from '../../src/diff.mjs';
import { parseData } from '../../src/dataParam.mjs';
import { loadFormat } from '../../src/urlBuilder.mjs';

test('値の変更をブロック単位で検出する', () => {
  const before = parseData('!2m3!6e0!7e2!8j1786703520');
  const after = parseData('!2m3!6e0!7e4!8j1786703520');
  const changes = structuralDiff(before, after, { ignoreValues: ['8j'] });
  assert.equal(changes.length, 1);
  assert.equal(changes[0].type, 'changed');
  assert.equal(changes[0].key, '7e');
  assert.deepEqual(changes[0].after, ['!7e4']);
});

test('追加・削除も検出する', () => {
  const before = parseData('!2m3!6e0!7e2');
  const after = parseData('!2m3!6e0!9k1');
  const changes = structuralDiff(before, after);
  const types = changes.map((change) => change.type).sort();
  assert.deepEqual(types, ['added', 'removed']);
});

test('無視指定した可変値（座標・timestamp）は差分にしない', () => {
  const before = parseData('!1d139.7!2d35.6!8j1000');
  const after = parseData('!1d135.5!2d34.7!8j2000');
  assert.deepEqual(structuralDiff(before, after, { ignoreValues: ['1d', '2d', '8j'] }), []);
});

test('delta debugging が最小の変更集合へ縮小する', async () => {
  const changes = ['a', 'b', 'c', 'd', 'e'];
  // 'c' さえ含まれていれば PASS するという状況を作る。
  const minimal = await minimizeChangeSet(changes, async (subset) => subset.includes('c'));
  assert.deepEqual(minimal, ['c']);
});

test('全部当てても直らなければ null（= 自動修復不能）', async () => {
  const minimal = await minimizeChangeSet(['a', 'b'], async () => false);
  assert.equal(minimal, null);
});

test('必要な変更が複数なら両方残す', async () => {
  const changes = ['a', 'b', 'c', 'd'];
  const minimal = await minimizeChangeSet(changes, async (subset) =>
    subset.includes('a') && subset.includes('d')
  );
  assert.ok(minimal.includes('a'));
  assert.ok(minimal.includes('d'));
});

test('変更集合を format.json へ適用できる（定数トークンのみ）', () => {
  const format = loadFormat();
  const updated = applyChanges(format, [
    { type: 'changed', key: '7e', before: ['!7e2'], after: ['!7e4'] }
  ]);
  const token = updated.timeBlock.find((entry) => entry.group === 7 && entry.kind === 'e');
  assert.equal(token.value, '4');
  // プレースホルダを持つトークンは書き換えない。
  const timestamp = updated.timeBlock.find((entry) => entry.group === 8 && entry.kind === 'j');
  assert.equal(timestamp.value, '{timestamp}');
});
