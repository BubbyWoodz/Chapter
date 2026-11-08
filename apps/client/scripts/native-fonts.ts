// SPDX-License-Identifier: AGPL-3.0-or-later
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
const root = new URL('../../ios/Chapter/Fonts/',import.meta.url);
const manifest = JSON.parse(readFileSync(new URL('manifest.json',root),'utf8')) as {package:string;version:string;source:string;sourceSHA256:string;file:string;sha256:string;license:string;licenseSHA256:string;postscript:string}[];
const hash = (bytes:Buffer) => createHash('sha256').update(bytes).digest('hex');
assert.equal(manifest.length,6);
const plist = readFileSync(new URL('../../ios/Chapter/Info.plist',import.meta.url),'utf8');
for (const asset of manifest) {
 const pkg = new URL('../node_modules/@fontsource-variable/'+asset.package+'/',import.meta.url);
 assert.equal(JSON.parse(readFileSync(new URL('package.json',pkg),'utf8')).version,asset.version);
 assert.equal(hash(readFileSync(new URL('files/'+asset.source,pkg))),asset.sourceSHA256,'Original web glyph source changed; regenerate deliberately');
 const font = readFileSync(new URL(asset.file,root)); assert.equal(hash(font),asset.sha256);assert.equal(font.readUInt32BE(),0x00010000,'iOS fonts must be actual TrueType, not renamed WOFF2');
 const license = readFileSync(new URL(asset.license,root));assert.equal(hash(license),asset.licenseSHA256);assert.deepEqual(license,readFileSync(new URL('LICENSE',pkg)));
 assert.ok(license.toString().includes('SIL OPEN FONT LICENSE Version 1.1'));assert.ok(plist.includes('<string>Fonts/'+asset.file+'</string>'));
}
const project = readFileSync(new URL('../../ios/Chapter.xcodeproj/project.pbxproj',import.meta.url),'utf8');
assert.ok(project.includes('lastKnownFileType = folder; path = Fonts;'));assert.ok(project.includes('files = (D00000000000000000000002, A00000000000000000000025)'));
const css = readFileSync(new URL('../src/styles/tokens.css',import.meta.url),'utf8');
assert.ok(css.includes("--ui: 'Hanken Grotesk Variable'"));assert.ok(css.includes("--serif: 'Newsreader Variable'"));assert.ok(css.includes("--mono: 'Spline Sans Mono Variable'"));
console.log('PASS original font provenance: six exact web-source/output SHA256s, real TrueType headers, pinned package versions, full original OFL notices and actual Xcode font resources/plist. UIKit loading/scaling is a separate required iOS test.');
