/**
 * format.json に従って、アプリと同じ Primary URL を生成する。
 * ここが Swift 実装とずれていないことは Swift 側の URLFormatContractTests が保証する。
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { encodeData } from './dataParam.mjs';

const here = dirname(fileURLToPath(import.meta.url));
export const formatPath = join(here, '..', 'format.json');
export const fixturesPath = join(here, '..', 'fixtures', 'fixtures.json');

export function loadFormat(path = formatPath) {
  return JSON.parse(readFileSync(path, 'utf8'));
}

export function loadFixtures(path = fixturesPath) {
  return JSON.parse(readFileSync(path, 'utf8'));
}

/**
 * 壁時計時刻（"2026-09-01T10:32"）を Google の !8j 値へ変換する。
 * 仕様書 7.3: ローカル表示したい年月日時分を UTC の壁時計としてそのまま epoch 化する。
 */
export function googleTimestamp(wallClock) {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(wallClock);
  if (!match) throw new Error(`wallClock の形式が不正: ${wallClock}`);
  const [, year, month, day, hour, minute] = match.map(Number);
  return Math.floor(Date.UTC(year, month - 1, day, hour, minute, 0) / 1000);
}

function formatCoordinate(value, precision) {
  return Number(value).toFixed(precision);
}

function pathSegment(place, precision) {
  const name = (place.name ?? '').trim();
  if (name.length === 0) {
    return `${formatCoordinate(place.latitude, precision)},${formatCoordinate(place.longitude, precision)}`;
  }
  return encodeURIComponent(name.replace(/ /g, '+')).replace(/%2B/g, '+');
}

function fill(template, values) {
  return String(template).replace(/\{(\w+)\}/g, (match, key) =>
    Object.prototype.hasOwnProperty.call(values, key) ? String(values[key]) : match
  );
}

/** fixture から Primary URL を組み立てる。 */
export function buildPrimaryURL(fixture, format = loadFormat()) {
  const precision = format.coordinatePrecision;
  const places = [fixture.origin, ...(fixture.waypoints ?? []), fixture.destination];

  const body = [];
  for (const place of places) {
    for (const token of format.placeBlock) {
      body.push({
        group: token.group,
        kind: token.kind,
        value: fill(token.value, {
          longitude: formatCoordinate(place.longitude, precision),
          latitude: formatCoordinate(place.latitude, precision)
        })
      });
    }
  }

  const timeMode = format.timeMode[fixture.timePreference];
  if (timeMode === undefined) throw new Error(`未知の timePreference: ${fixture.timePreference}`);
  const timestamp = googleTimestamp(fixture.wallClock);
  for (const token of format.timeBlock) {
    body.push({
      group: token.group,
      kind: token.kind,
      value: fill(token.value, { timeMode, timestamp })
    });
  }

  const modeCode = format.modeCode[fixture.mode];
  if (modeCode === undefined) throw new Error(`未知の mode: ${fixture.mode}`);
  body.push({
    group: format.modeToken.group,
    kind: format.modeToken.kind,
    value: fill(format.modeToken.value, { modeCode })
  });

  const inner = { ...format.wrapper.inner, value: fill(format.wrapper.inner.value, { innerCount: body.length }) };
  const outer = {
    ...format.wrapper.outer,
    value: fill(format.wrapper.outer.value, { outerCount: body.length + 1 })
  };
  const tokens = [outer, inner, ...body];

  const path = places.map((place) => pathSegment(place, precision)).join('/');
  return `${format.host}${format.pathPrefix}${path}${format.dataPrefix}${encodeData(tokens)}`;
}

/** 公式 Maps URLs（fallback）。契約が壊れてもこちらは公開 API なので安定している。 */
export function buildOfficialURL(fixture, format = loadFormat()) {
  const precision = format.coordinatePrecision;
  const coordinate = (place) =>
    `${formatCoordinate(place.latitude, precision)},${formatCoordinate(place.longitude, precision)}`;
  const params = new URLSearchParams({
    api: '1',
    origin: coordinate(fixture.origin),
    destination: coordinate(fixture.destination),
    travelmode: fixture.mode
  });
  return `${format.host}${format.pathPrefix}?${params.toString()}`;
}
