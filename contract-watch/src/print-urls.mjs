/**
 * 手動検証用に、fixture から Primary / Official URL を出力する。
 *
 *   node src/print-urls.mjs                 … fixtures.json の全件
 *   node src/print-urls.mjs 2026-08-18T10:32 … 日時を差し替えて出力
 *
 * `xcrun simctl openurl booted "<URL>"` に渡せば、シミュレータの Safari で開ける。
 */
import { buildOfficialURL, buildPrimaryURL, loadFixtures } from './urlBuilder.mjs';

const override = process.argv[2];
const fixtures = loadFixtures();

for (const fixture of fixtures) {
  const target = override ? { ...fixture, wallClock: override } : fixture;
  const condition = target.timePreference === 'arriveBy' ? '到着' : '出発';
  console.log(`# ${target.name} (${condition} ${target.wallClock})`);
  console.log(`  ${target.description}`);
  console.log(`  primary : ${buildPrimaryURL(target)}`);
  console.log(`  official: ${buildOfficialURL(target)}`);
  console.log('');
}

console.log('シミュレータで開く:');
console.log(`  xcrun simctl openurl booted "${buildPrimaryURL(override ? { ...fixtures[0], wallClock: override } : fixtures[0])}"`);
