/**
 * Google Maps の経路画面が fixture の条件を保っているかを検証する（仕様書 8.4）。
 *
 * Google の DOM は非公開かつ変わりやすいため、
 * class 名ではなく「見えているテキスト」と入力値を根拠に判定する。
 * ここが落ちること自体が「契約が壊れた」シグナルなので、
 * 過度に緩い判定にはしない。
 */

const CONSENT_PATTERNS = [/同意する/, /すべて受け入れる/, /Accept all/i, /Reject all/i];

/** EU 等で出る同意ダイアログを閉じる（出ない場合は何もしない）。 */
export async function dismissConsentIfPresent(page) {
  for (const pattern of CONSENT_PATTERNS) {
    const button = page.getByRole('button', { name: pattern });
    if (await button.first().isVisible().catch(() => false)) {
      await button.first().click().catch(() => {});
      await page.waitForLoadState('domcontentloaded').catch(() => {});
      return true;
    }
  }
  return false;
}

/** 期待する時刻表記のバリエーション（"10:32" / "10時32分"）。 */
export function timePatterns(wallClock) {
  const [, hour, minute] = /T(\d{2}):(\d{2})$/.exec(wallClock) ?? [];
  if (!hour) return [];
  const h = String(Number(hour));
  return [
    new RegExp(`${h}:${minute}`),
    new RegExp(`${h}時${Number(minute)}分`),
    new RegExp(`${hour}:${minute}`)
  ];
}

/** 期待する日付表記（"9月1日" / "2026/09/01" / "9/1"）。 */
export function datePatterns(wallClock) {
  const [, year, month, day] = /^(\d{4})-(\d{2})-(\d{2})/.exec(wallClock) ?? [];
  if (!year) return [];
  const m = String(Number(month));
  const d = String(Number(day));
  return [
    new RegExp(`${m}月${d}日`),
    new RegExp(`${year}/${month}/${day}`),
    new RegExp(`${m}/${d}`),
    new RegExp(`${month}/${day}`)
  ];
}

async function pageContainsAny(page, patterns) {
  if (patterns.length === 0) return false;
  const text = await page.locator('body').innerText().catch(() => '');
  const inputs = await page.locator('input').evaluateAll((nodes) =>
    nodes.map((node) => node.value ?? '').join('\n')
  ).catch(() => '');
  const haystack = `${text}\n${inputs}`;
  return patterns.some((pattern) => pattern.test(haystack));
}

/**
 * fixture の条件が画面に反映されているかを検証し、失敗理由の配列を返す。
 * 空配列なら PASS。
 */
export async function verifyFixture(page, fixture) {
  const failures = [];

  // 1. 経路画面になっている（URL が /maps/dir/ を保っている）。
  const currentURL = page.url();
  if (!currentURL.includes('/maps/dir/')) {
    failures.push(`経路画面ではない: ${currentURL}`);
  }

  // 2. 出発地・目的地が保たれている。
  //    名前を渡した場合は画面にその名前が出る。
  //    名前なし（座標のみ）の場合、Google は住所へ逆引きして表示するため画面文字列では確認できない。
  //    その場合は URL に座標が残っているかで判定する。
  for (const [role, place] of [['出発地', fixture.origin], ['目的地', fixture.destination]]) {
    const name = (place.name ?? '').trim();
    if (name) {
      if (!(await pageContainsAny(page, [new RegExp(escapeRegExp(name))]))) {
        failures.push(`${role}が反映されていない: ${name}`);
      }
      continue;
    }
    const latitude = String(place.latitude).slice(0, 7);
    const longitude = String(place.longitude).slice(0, 8);
    if (!currentURL.includes(latitude) || !currentURL.includes(longitude)) {
      failures.push(`${role}の座標が URL から失われた: ${place.latitude},${place.longitude}`);
    }
  }

  // 3. 公共交通モードになっている。
  if (fixture.mode === 'transit') {
    const transitSelected = await page
      .locator('[data-travel_mode="3"][aria-pressed="true"], [aria-label*="公共交通"], [aria-label*="Transit"]')
      .first()
      .isVisible()
      .catch(() => false);
    const urlKeepsTransitMode = currentURL.includes('!3e3');
    if (!transitSelected && !urlKeepsTransitMode) {
      failures.push('公共交通モードになっていない');
    }
  }

  // 4. 出発 / 到着の指定が意図どおり。
  const expectsArrival = fixture.timePreference === 'arriveBy';
  const arrivalSelected = await pageContainsAny(page, [/到着時刻/, /Arrive by/i]);
  const departureSelected = await pageContainsAny(page, [/出発時刻/, /Depart at/i]);
  if (expectsArrival && !arrivalSelected && !currentURL.includes('!6e1')) {
    failures.push('到着時刻指定になっていない');
  }
  if (!expectsArrival && !departureSelected && !currentURL.includes('!6e0')) {
    failures.push('出発時刻指定になっていない');
  }

  // 5. 指定した日付・時刻が UI に反映されている。
  if (!(await pageContainsAny(page, timePatterns(fixture.wallClock)))) {
    failures.push(`時刻が反映されていない: ${fixture.wallClock}`);
  }
  if (!(await pageContainsAny(page, datePatterns(fixture.wallClock)))) {
    failures.push(`日付が反映されていない: ${fixture.wallClock}`);
  }

  return failures;
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
