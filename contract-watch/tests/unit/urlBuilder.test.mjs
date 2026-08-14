import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildOfficialURL, buildPrimaryURL, googleTimestamp, loadFixtures } from '../../src/urlBuilder.mjs';
import { extractData, isStructurallyConsistent, parseData } from '../../src/dataParam.mjs';

const fixture = {
  name: 'unit',
  origin: { name: '御茶ノ水駅', latitude: 35.6993, longitude: 139.7649 },
  destination: { name: '東京駅', latitude: 35.6812362, longitude: 139.7671248 },
  waypoints: [],
  mode: 'transit',
  timePreference: 'departAt',
  timeZone: 'Asia/Tokyo',
  wallClock: '2026-08-14T10:32'
};

test('!8j は壁時計時刻を UTC として epoch 化した値（Swift 実装と同じ）', () => {
  assert.equal(googleTimestamp('2026-08-14T10:32'), 1786703520);
  assert.equal(googleTimestamp('2026-08-14T10:54'), 1786704840);
});

test('壁時計の形式が不正なら例外', () => {
  assert.throws(() => googleTimestamp('2026/08/14 10:32'));
});

test('Primary URL が Swift 実装と同じ文字列になる', () => {
  assert.equal(
    buildPrimaryURL(fixture),
    'https://www.google.com/maps/dir/' +
      '%E5%BE%A1%E8%8C%B6%E3%83%8E%E6%B0%B4%E9%A7%85/%E6%9D%B1%E4%BA%AC%E9%A7%85/data=' +
      '!4m14!4m13' +
      '!1m3!2m2!1d139.7649000!2d35.6993000' +
      '!1m3!2m2!1d139.7671248!2d35.6812362' +
      '!2m3!6e0!7e2!8j1786703520' +
      '!3e3'
  );
});

test('到着指定は !6e1 になる', () => {
  const url = buildPrimaryURL({ ...fixture, timePreference: 'arriveBy' });
  assert.ok(url.includes('!2m3!6e1!7e2!8j1786703520'));
});

test('名前が空の地点は座標をパスに使う', () => {
  const url = buildPrimaryURL({
    ...fixture,
    origin: { name: '', latitude: 35.6993, longitude: 139.7649 }
  });
  assert.ok(url.includes('/maps/dir/35.6993000,139.7649000/'));
});

test('全 fixture の構造が自己整合している', () => {
  for (const item of loadFixtures()) {
    const tokens = parseData(extractData(buildPrimaryURL(item)));
    assert.ok(tokens, `${item.name}: data= を解析できない`);
    assert.ok(isStructurallyConsistent(tokens), `${item.name}: ブロック長が不整合`);
  }
});

test('公式 fallback URL は公開 API の形式', () => {
  const url = buildOfficialURL(fixture);
  assert.ok(url.startsWith('https://www.google.com/maps/dir/?'));
  assert.ok(url.includes('api=1'));
  assert.ok(url.includes('travelmode=transit'));
  assert.ok(url.includes('destination=35.6812362%2C139.7671248'));
});
