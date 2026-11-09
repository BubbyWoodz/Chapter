#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Lossless WOFF2 → TrueType conversion of the lockfile-pinned original web fonts.
Reproduce: pip install fonttools==4.65.0 Brotli==1.1.0; pnpm install --frozen-lockfile;
python3 apps/ios/scripts/bundle-original-fonts.py
No font is downloaded by the iOS app or Xcode build. Latin subsets use native
fallback for missing glyphs; this is not full non-Latin visual certification.
"""
import hashlib, json
from pathlib import Path
from fontTools.ttLib import TTFont
ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'apps/client/node_modules/@fontsource-variable'
OUTPUT = ROOT / 'apps/ios/Chapter/Fonts'
OUTPUT.mkdir(parents=True, exist_ok=True)
assets = [('hanken-grotesk','hanken-grotesk-latin-wght-normal'),('hanken-grotesk','hanken-grotesk-latin-wght-italic'),('newsreader','newsreader-latin-standard-normal'),('newsreader','newsreader-latin-standard-italic'),('spline-sans-mono','spline-sans-mono-latin-wght-normal'),('spline-sans-mono','spline-sans-mono-latin-wght-italic')]
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
manifest = []
for family, name in assets:
    package = SOURCE / family
    source = package / 'files' / (name+'.woff2')
    font = TTFont(source, recalcTimestamp=False)
    postscript = font['name'].getDebugName(6)
    target = OUTPUT / (postscript+'.ttf')
    font.flavor = None
    font.save(target, reorderTables=False)
    restored = TTFont(target, recalcTimestamp=False)
    assert restored.getBestCmap() == font.getBestCmap()
    assert restored.getGlyphOrder() == font.getGlyphOrder()
    assert restored['name'].getDebugName(6) == postscript
    original_head = bytearray(font.getTableData('head'))
    restored_head = bytearray(restored.getTableData('head'))
    original_head[8:12] = restored_head[8:12] = bytes(4)  # checkSumAdjustment only
    assert original_head == restored_head, (family,'head except checksum')
    for table in font.keys():
        if table in ('GlyphOrder','head'): continue
        assert restored.getTableData(table) == font.getTableData(table), (family,table)
    license = OUTPUT / (family+'-OFL.txt')
    license.write_bytes((package/'LICENSE').read_bytes())
    manifest.append(dict(package=family,version=json.loads((package/'package.json').read_text())['version'],source=name+'.woff2',sourceSHA256=sha(source),file=target.name,postscript=postscript,sha256=sha(target),license=license.name,licenseSHA256=sha(license)))
(OUTPUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('PASS: six original web fonts converted; glyph maps/orders and every non-checksum font table preserved; exact licenses copied.')
