import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  testMatch: '**/*.spec.mjs',
  // 契約監視なので落ちたら落ちたまま記録する（リトライで隠さない）。
  retries: 0,
  workers: 1,
  timeout: 90_000,
  reporter: [
    ['list'],
    ['html', { open: 'never', outputFolder: 'artifacts/html-report' }],
    ['json', { outputFile: 'artifacts/results.json' }]
  ],
  outputDir: 'artifacts/test-results',
  use: {
    ...devices['Desktop Chrome'],
    locale: 'ja-JP',
    timezoneId: 'Asia/Tokyo',
    geolocation: { latitude: 35.6812362, longitude: 139.7671248 },
    permissions: [],
    screenshot: 'only-on-failure',
    video: 'off',
    trace: 'retain-on-failure'
  }
});
