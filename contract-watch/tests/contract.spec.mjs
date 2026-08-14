import { test, expect } from '@playwright/test';
import { buildPrimaryURL, loadFixtures, loadFormat } from '../src/urlBuilder.mjs';
import { extractData, isStructurallyConsistent, parseData } from '../src/dataParam.mjs';
import { dismissConsentIfPresent, verifyFixture } from '../src/verify.mjs';

const fixtures = loadFixtures();
const format = loadFormat();

test.describe('Google Maps 時刻付き URL の契約', () => {
  // 生成側の自己検査。ネットワークに出る前に壊れた URL を弾く。
  for (const fixture of fixtures) {
    test(`[構造] ${fixture.name}`, () => {
      const url = buildPrimaryURL(fixture, format);
      const data = extractData(url);
      expect(data, 'data= が生成されていない').not.toBeNull();
      const tokens = parseData(data);
      expect(tokens, 'data= を解析できない').not.toBeNull();
      expect(isStructurallyConsistent(tokens), 'ブロック長が整合していない').toBe(true);
    });
  }

  // 実際に Google Maps を開いて条件が保たれるかを見る（仕様書 8.4）。
  for (const fixture of fixtures) {
    test(`[実遷移] ${fixture.name}`, async ({ page }, testInfo) => {
      const url = buildPrimaryURL(fixture, format);
      testInfo.annotations.push({ type: 'primary-url', description: url });

      await page.goto(url, { waitUntil: 'domcontentloaded' });
      await dismissConsentIfPresent(page);
      // 経路パネルの描画待ち。
      await page.waitForTimeout(4000);

      const failures = await verifyFixture(page, fixture);

      if (failures.length > 0) {
        // FAIL 時の診断材料を Artifact として残す（仕様書 8.5）。
        await testInfo.attach('fixture.json', {
          body: JSON.stringify({ fixture, requestedURL: url, finalURL: page.url(), failures }, null, 2),
          contentType: 'application/json'
        });
        await testInfo.attach('screenshot.png', {
          body: await page.screenshot({ fullPage: false }),
          contentType: 'image/png'
        });
      }

      expect(failures, `期待条件を満たさない:\n${failures.join('\n')}`).toEqual([]);
    });
  }
});
