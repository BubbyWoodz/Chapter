// SPDX-License-Identifier: AGPL-3.0-or-later
// Every web locale's built-in template seeds, through the app's own i18n: Vite SSR
// expands import.meta.glob exactly like the bundle, then the real setLocale and
// seedBuiltinTemplates run. No server listens and nothing leaves the machine.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createServer } from 'vite';

export async function verifyLocalizedBuiltins(write: boolean): Promise<void> {
  const vite = await createServer({ configFile: false, root: new URL('..', import.meta.url).pathname, logLevel: 'error', server: { middlewareMode: true, hmr: false, ws: false }, appType: 'custom', optimizeDeps: { noDiscovery: true, include: [] } });
  try {
    const i18n = (await vite.ssrLoadModule('/src/i18n/index.tsx')) as typeof import('../src/i18n');
    const tpl = (await vite.ssrLoadModule('/src/data/templates.ts')) as typeof import('../src/data/templates');
    const seeds: Record<string, unknown> = {};
    for (const info of i18n.LOCALES) {
      await i18n.setLocale(info.id);
      assert.equal(i18n.currentLocale().id, info.id, 'Locale did not load: ' + info.id);
      seeds[info.id] = tpl.seedBuiltinTemplates(0).map((t) => ({ slug: t.builtin, name: t.name, bodyJson: t.bodyJson, bodyText: t.bodyText }));
    }
    await i18n.setLocale('en');
    const english = JSON.parse(readFileSync(new URL('../../ios/ChapterCore/Sources/ChapterCore/Resources/builtin-templates.json', import.meta.url), 'utf8'));
    assert.deepEqual(seeds.en, english, 'English seeds must equal the bundled English catalog');
    const data = { locales: i18n.LOCALES, seeds };
    const url = new URL('../../ios/ChapterCore/Sources/ChapterCore/Resources/builtin-templates-locales.json', import.meta.url);
    if (write) writeFileSync(url, JSON.stringify(data, null, 2) + '\n');
    else assert.deepEqual(JSON.parse(readFileSync(url, 'utf8')), data, 'Native localized built-ins must equal the original web catalogs');
    console.log('Native built-in templates equal the original web seeds in all ' + i18n.LOCALES.length + ' locales.');
  } finally {
    await vite.close();
  }
}
