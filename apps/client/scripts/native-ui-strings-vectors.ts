// SPDX-License-Identifier: AGPL-3.0-or-later
// Translated interface text: the native app ships the web's own message catalogs
// and ports t()/tp()/fmtNumber. Vite SSR loads the real modules (no server, no
// network); vectors come from the web functions in every locale.
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createServer } from 'vite';

const counts = [0, 1, 2, 3, 4, 5, 7, 11, 12, 21, 100, 101, 102, 111, 1000000, 1.5, 0.5];
const numbers: [number, Record<string, number> | undefined][] = [[0, undefined], [7, undefined], [1234, undefined], [1234567.891, undefined], [3.14159, undefined], [0.5, { minimumFractionDigits: 1, maximumFractionDigits: 1 }], [5.55, { minimumFractionDigits: 1, maximumFractionDigits: 1 }], [9.95, { minimumFractionDigits: 1, maximumFractionDigits: 1 }], [2.25, { minimumFractionDigits: 1, maximumFractionDigits: 1 }]];
const distances = [0.0004, 0.0125, 0.25, 0.9994, 0.9996, 1, 2.25, 5.55, 9.94, 9.96, 10, 10.5, 123.4, 20015.08];
const points: [[number, number], [number, number]][] = [[[48.8566, 2.3522], [51.5074, -0.1278]], [[0, 0], [0, 180]], [[-33.8688, 151.2093], [40.7128, -74.006]], [[37.7749, -122.4194], [37.7749, -122.4194]], [[10, 10], [10.001, 10.001]]];

export async function verifyUIStrings(write: boolean): Promise<void> {
  const vite = await createServer({ configFile: false, root: new URL('..', import.meta.url).pathname, logLevel: 'error', server: { middlewareMode: true, hmr: false, ws: false }, appType: 'custom', optimizeDeps: { noDiscovery: true, include: [] } });
  try {
    const i18n = (await vite.ssrLoadModule('/src/i18n/index.tsx')) as typeof import('../src/i18n');
    const { en } = (await vite.ssrLoadModule('/src/i18n/en.ts')) as typeof import('../src/i18n/en');
    const location = (await vite.ssrLoadModule('/src/editor/location.tsx')) as typeof import('../src/editor/location');
    const mercator = (await vite.ssrLoadModule('/src/location/mercator.ts')) as typeof import('../src/location/mercator');
    const catalogs: Record<string, Record<string, string>> = { en: { ...en } };
    for (const info of i18n.LOCALES.slice(1)) catalogs[info.id] = { ...((await vite.ssrLoadModule(`/src/i18n/locales/${info.id}.ts`)) as { default: Record<string, string> }).default };
    const keys = Object.keys(en).sort();
    const sample = [...keys.filter((_, i) => i % 37 === 0), ...keys.filter(k => k.startsWith('editorx.location.')), 'missing.key.example'];
    const bases = [...new Set(keys.filter(k => k.endsWith('#other')).map(k => k.slice(0, -'#other'.length)))].sort();
    const vectors: Record<string, unknown> = {};
    for (const info of i18n.LOCALES) {
      await i18n.setLocale(info.id);
      assert.equal(i18n.currentLocale().id, info.id);
      const plural = new Intl.PluralRules(info.id);
      vectors[info.id] = {
        t: sample.map(key => ({ key, out: i18n.t(key as never, { n: 7, count: 3, name: 'Ada' }) })),
        bare: sample.slice(0, 12).map(key => ({ key, out: i18n.t(key as never) })),
        plural: counts.map(n => ({ n, category: plural.select(n) })),
        tp: bases.flatMap(base => counts.map(n => ({ base, n, out: i18n.tp(base as never, n, { name: 'Ada' }) }))),
        numbers: numbers.map(([n, opts]) => ({ n, opts: opts ?? null, out: i18n.fmtNumber(n, opts) })),
        distances: distances.map(km => ({ km, out: location.fmtDistance(km) })),
      };
    }
    await i18n.setLocale('en');
    const haversine = points.map(([a, b]) => ({ a, b, km: mercator.haversineKm({ lat: a[0], lng: a[1], label: '' }, { lat: b[0], lng: b[1], label: '' }) }));
    const catalogURL = new URL('../../ios/ChapterCore/Sources/ChapterCore/Resources/ui-messages.json', import.meta.url);
    const vectorURL = new URL('../../ios/ChapterCore/Tests/ChapterCoreTests/Fixtures/ui-strings.json', import.meta.url);
    const catalog = { locales: i18n.LOCALES.map(l => l.id), catalogs };
    const fixture = { vectors, haversine };
    if (write) { writeFileSync(catalogURL, JSON.stringify(catalog) + '\n'); writeFileSync(vectorURL, JSON.stringify(fixture, null, 1) + '\n'); }
    else {
      assert.deepEqual(JSON.parse(readFileSync(catalogURL, 'utf8')), catalog, 'Native interface catalogs must equal the web message catalogs');
      assert.deepEqual(JSON.parse(readFileSync(vectorURL, 'utf8')), JSON.parse(JSON.stringify(fixture)), 'Native string vectors must equal the web t/tp/fmtNumber');
    }
    // Every key the native app asks for must be a real web key (no invented strings).
    const appDir = new URL('../../ios/Chapter/', import.meta.url);
    const used = new Set<string>();
    for (const file of readdirSync(appDir).filter(f => f.endsWith('.swift'))) {
      const text = readFileSync(new URL(file, appDir), 'utf8');
      for (const m of text.matchAll(/\bt\("([^"\\]+)"(?:\s*\+\s*\$0)?/g)) {
        if (m[0].includes('+')) for (const id of m[1] === 'prefs.mode.' ? ['light', 'dark', 'system'] : m[1] === 'prefs.skin.' ? ['paper', 'modern', 'terminal', 'forest', 'blossom', 'lavender'] : m[1] === 'prefs.palette.' ? ['terracotta', 'moss', 'sea', 'twilight', 'plum', 'rose'] : [null]) { assert.ok(id, 'Unknown dynamic key prefix ' + m[1]); used.add(m[1] + id); }
        else used.add(m[1]);
      }
    }
    for (const key of used) assert.ok(key in en, 'Native app uses a key the web catalog lacks: ' + key);
    assert.ok(used.size >= 30, 'Expected the native screens to use the web catalog');
    console.log(`Native interface text: ${keys.length} web keys in ${i18n.LOCALES.length} locales; t/tp/number/distance vectors equal the web; ${used.size} keys used by native screens all exist.`);
  } finally { await vite.close(); }
}
