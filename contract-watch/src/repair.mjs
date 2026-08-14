/**
 * 自動差分解析・修復（仕様書 9 / 10）。
 *
 *   1. 全 fixture を実行し、FAIL したものを集める
 *   2. Google Maps UI を操作して同条件の「正解 URL」を新規生成する
 *   3. 現行 URL と正解 URL を構造ブロック単位で diff する
 *   4. delta debugging で最小の変更集合へ縮小する
 *   5. format.json へ適用して全 fixture を再実行する
 *   6. 全件 PASS したときだけ修正候補として書き出す（それ以外は Issue 用の報告のみ）
 *
 * 実行: node src/repair.mjs [--write]
 */
import { chromium } from '@playwright/test';
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildPrimaryURL, buildOfficialURL, formatPath, loadFixtures, loadFormat } from './urlBuilder.mjs';
import { extractData, parseData } from './dataParam.mjs';
import { applyChanges, minimizeChangeSet, structuralDiff } from './diff.mjs';
import { dismissConsentIfPresent, verifyFixture } from './verify.mjs';
import { generate, generatedSwiftPath } from './generate-swift.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const artifactsDir = join(here, '..', 'artifacts');

/** fixture を 1 件検証する。 */
async function runFixture(browser, fixture, format) {
  const context = await browser.newContext({ locale: 'ja-JP', timezoneId: fixture.timeZone });
  const page = await context.newPage();
  const url = buildPrimaryURL(fixture, format);
  try {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60_000 });
    await dismissConsentIfPresent(page);
    await page.waitForTimeout(4000);
    const failures = await verifyFixture(page, fixture);
    const finalURL = page.url();
    const screenshot = failures.length > 0 ? await page.screenshot() : null;
    return { fixture: fixture.name, url, finalURL, failures, screenshot };
  } catch (error) {
    return { fixture: fixture.name, url, finalURL: null, failures: [String(error)], screenshot: null };
  } finally {
    await context.close();
  }
}

async function runAll(browser, fixtures, format) {
  const results = [];
  for (const fixture of fixtures) {
    results.push(await runFixture(browser, fixture, format));
  }
  return results;
}

/**
 * Google Maps の UI を操作して、同じ条件の「正解 URL」を得る。
 * 公式 Directions URL から入り、公共交通と時刻条件を UI で設定して、
 * Google 自身が書き換えた location.href（= 正解の内部形式）を読み取る。
 *
 * Google の UI 変更で失敗しうるため、取得できなければ null を返し、
 * 呼び出し側は「修復不能 → Issue」へ倒す。
 */
export async function captureGroundTruthURL(browser, fixture) {
  const context = await browser.newContext({ locale: 'ja-JP', timezoneId: fixture.timeZone });
  const page = await context.newPage();
  try {
    await page.goto(buildOfficialURL(fixture), { waitUntil: 'domcontentloaded', timeout: 60_000 });
    await dismissConsentIfPresent(page);
    await page.waitForTimeout(3000);

    // 公共交通タブ。
    const transitTab = page.locator('[data-travel_mode="3"], [aria-label*="公共交通"], [aria-label*="Transit"]').first();
    if (await transitTab.isVisible().catch(() => false)) {
      await transitTab.click().catch(() => {});
      await page.waitForTimeout(2000);
    }

    // 時刻条件のセレクタを開く。
    const timeSelector = page
      .locator('button:has-text("出発時刻"), button:has-text("到着時刻"), button:has-text("すぐに出発")')
      .first();
    if (await timeSelector.isVisible().catch(() => false)) {
      await timeSelector.click().catch(() => {});
      await page.waitForTimeout(1000);
      const wanted = fixture.timePreference === 'arriveBy' ? '到着時刻' : '出発時刻';
      const option = page.getByRole('option', { name: new RegExp(wanted) }).first();
      if (await option.isVisible().catch(() => false)) {
        await option.click().catch(() => {});
        await page.waitForTimeout(1000);
      }
    }

    const [, date, time] = /^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2})$/.exec(fixture.wallClock) ?? [];
    const dateInput = page.locator('input[type="date"], input[aria-label*="日付"]').first();
    if (date && (await dateInput.isVisible().catch(() => false))) {
      await dateInput.fill(date).catch(() => {});
      await dateInput.press('Enter').catch(() => {});
      await page.waitForTimeout(1500);
    }
    const timeInput = page.locator('input[type="time"], input[aria-label*="時刻"]').first();
    if (time && (await timeInput.isVisible().catch(() => false))) {
      await timeInput.fill(time).catch(() => {});
      await timeInput.press('Enter').catch(() => {});
      await page.waitForTimeout(2500);
    }

    // Google が内部形式へ書き換えるのを待つ。
    await page.waitForFunction(() => window.location.href.includes('/data='), null, { timeout: 20_000 })
      .catch(() => {});
    const href = page.url();
    return href.includes('/data=') ? href : null;
  } catch {
    return null;
  } finally {
    await context.close();
  }
}

async function main() {
  const shouldWrite = process.argv.includes('--write');
  mkdirSync(artifactsDir, { recursive: true });

  const fixtures = loadFixtures();
  const format = loadFormat();
  const browser = await chromium.launch();
  const report = {
    startedAt: new Date().toISOString(),
    initial: [],
    repaired: false,
    minimalChanges: [],
    finalFormat: null,
    reason: null
  };

  try {
    report.initial = (await runAll(browser, fixtures, format)).map(stripScreenshot);
    const failing = report.initial.filter((result) => result.failures.length > 0);

    if (failing.length === 0) {
      report.reason = 'すべての fixture が PASS。修復不要。';
      finish(report, 0);
      return;
    }

    // 正解 URL を 1 件でも取得できなければ機械的な修復はできない。
    const target = fixtures.find((fixture) => fixture.name === failing[0].fixture);
    const groundTruth = await captureGroundTruthURL(browser, target);
    if (!groundTruth) {
      report.reason = '正解 URL を UI から取得できなかった。自動修復不能（Issue を作成する）。';
      finish(report, 2);
      return;
    }
    report.groundTruthURL = groundTruth;

    const currentTokens = parseData(extractData(buildPrimaryURL(target, format)));
    const truthTokens = parseData(extractData(groundTruth));
    if (!currentTokens || !truthTokens) {
      report.reason = 'data= を解析できなかった。自動修復不能。';
      finish(report, 2);
      return;
    }

    // 座標・timestamp は fixture 依存の可変値なので diff から除外する。
    const changes = structuralDiff(currentTokens, truthTokens, { ignoreValues: ['1d', '2d', '8j'] });
    report.allChanges = changes;
    if (changes.length === 0) {
      report.reason = '構造差分が無い（UI 側の一時的な失敗の可能性）。自動修復は行わない。';
      finish(report, 2);
      return;
    }

    const minimal = await minimizeChangeSet(changes, async (subset) => {
      const candidate = applyChanges(format, subset);
      const results = await runAll(browser, fixtures, candidate);
      return results.every((result) => result.failures.length === 0);
    });

    if (!minimal) {
      report.reason = '変更集合を当てても全 fixture が PASS しなかった。自動修復不能（Issue を作成する）。';
      finish(report, 2);
      return;
    }

    const repairedFormat = applyChanges(format, minimal);
    const finalResults = await runAll(browser, fixtures, repairedFormat);
    if (!finalResults.every((result) => result.failures.length === 0)) {
      report.reason = '最終確認で PASS しなかった。PR は作らない。';
      finish(report, 2);
      return;
    }

    report.repaired = true;
    report.minimalChanges = minimal;
    report.finalFormat = repairedFormat;
    report.finalResults = finalResults.map(stripScreenshot);
    report.reason = '最小変更で全 fixture が PASS。修正 PR の候補。';

    if (shouldWrite) {
      // format.json と、そこから生成する Swift の形式定義を同時に更新する。
      // PR には両方の差分が載り、人間がレビューしてマージする。
      writeFileSync(formatPath, `${JSON.stringify(repairedFormat, null, 2)}\n`, 'utf8');
      writeFileSync(generatedSwiftPath, generate(repairedFormat), 'utf8');
      report.updatedFiles = ['contract-watch/format.json',
                            'Packages/UsefulMapKit/Sources/Data/GoogleMapsURLFormat+Generated.swift'];
    }
    finish(report, 0);
  } finally {
    await browser.close();
  }
}

function stripScreenshot(result) {
  const { screenshot, ...rest } = result;
  return rest;
}

function finish(report, exitCode) {
  report.finishedAt = new Date().toISOString();
  writeFileSync(join(artifactsDir, 'repair-report.json'), `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  console.log(report.reason);
  process.exitCode = exitCode;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  await main();
}
