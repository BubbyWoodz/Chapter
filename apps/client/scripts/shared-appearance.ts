import assert from 'node:assert/strict';
import { withAppearance,withAiSettingsPreservingAppearance,readAppearance,appearanceModes,appearancePalettes,appearanceSkins } from '../src/appearance/shared';
import { defaultAiSettings } from '../src/ai/types';
const choice={v:1 as const,mode:'dark' as const,palette:'plum',skin:'lavender'};
const original={...defaultAiSettings(),anthropic:{apiKey:'PUBLIC-TEST',model:'future-model'},opaqueFuture:{preserve:true},chapterAppearance:{v:1,mode:'light',palette:'sea',skin:'forest',futureDensity:'keep'}};
const before=JSON.stringify(original),edited=withAppearance(original,choice);
assert.equal(JSON.stringify(original),before);assert.equal(edited.anthropic.apiKey,'PUBLIC-TEST');
assert.deepEqual((edited as unknown as Record<string,unknown>).opaqueFuture,{preserve:true});
assert.deepEqual(edited.chapterAppearance,{...choice,futureDensity:'keep'});
assert.equal(withAppearance(null,choice).enabled,false);
for(const mode of appearanceModes)for(const palette of appearancePalettes)for(const skin of appearanceSkins)assert(readAppearance({v:1,mode,palette,skin}));
for(const invalid of [{...choice,v:2},{...choice,mode:'automatic'},{...choice,palette:'external-url'},{...choice,skin:'unsupported'}]) {
 assert.equal(readAppearance(invalid),null);assert.throws(()=>withAppearance({...original,chapterAppearance:invalid},choice));
}
assert.throws(()=>withAppearance(original,{...choice,palette:'unsupported'}));
console.log('PASS: 108 appearance combinations, preserved API/opaque/future fields, disabled bootstrap and fail-closed unknown versions/values.');

const cleared=withAiSettingsPreservingAppearance(original,null);
assert(cleared);assert.equal(cleared.enabled,false);assert.equal(cleared.anthropic.apiKey,'');
assert.deepEqual(cleared.chapterAppearance,original.chapterAppearance);
for(const invalid of [false,0,''])assert.throws(()=>withAppearance({...original,chapterAppearance:invalid},choice));
