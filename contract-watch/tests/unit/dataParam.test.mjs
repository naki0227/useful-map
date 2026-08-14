import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  encodeData,
  extractData,
  isStructurallyConsistent,
  parseData
} from '../../src/dataParam.mjs';

test('data= をトークンへ分解する', () => {
  const tokens = parseData('!4m8!4m7!1m1!1s0x0:0x0!2m3!6e0!7e2!8j1786703520');
  assert.equal(tokens.length, 8);
  assert.deepEqual(tokens[0], { group: 4, kind: 'm', value: '8' });
  assert.deepEqual(tokens[7], { group: 8, kind: 'j', value: '1786703520' });
});

test('encode は parse の逆写像', () => {
  const raw = '!4m14!1m5!1m1!1s0x0:0x0!2m2!1d139.7671248!2d35.6812362!2m3!6e1!7e2!8j1786704840!3e3';
  assert.equal(encodeData(parseData(raw)), raw);
});

test('形式不正は null', () => {
  for (const raw of ['', '4m8', '!', '!!4m8', '!m8', '!4', '!4m8!']) {
    assert.equal(parseData(raw), null, `${raw} を受理してはいけない`);
  }
});

test('ブロック長の整合を検証する', () => {
  assert.equal(isStructurallyConsistent(parseData('!1m5!1m1!1s0x0:0x0!2m2!1d139.0!2d35.0')), true);
  assert.equal(isStructurallyConsistent(parseData('!1m9!1m1!1s0x0:0x0!2m2!1d139.0!2d35.0')), false);
  assert.equal(isStructurallyConsistent(parseData('!1m3!1m1!1s0x0:0x0!2m2!1d139.0!2d35.0')), false);
});

test('URL から data= を取り出す（クエリは落とす）', () => {
  assert.equal(extractData('https://www.google.com/maps/dir/A/B/data=!4m2!3e3?hl=ja'), '!4m2!3e3');
  assert.equal(extractData('https://www.google.com/maps/dir/?api=1'), null);
});
