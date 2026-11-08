// Appearance is an optional, versioned extension of the EXISTING encrypted
// aiSettings.settings object. Older codecs retain it; no new record kind/cipher.
import { defaultAiSettings, type AiSettings } from '../ai/types';
export interface SharedAppearance { v: 1; mode: 'light'|'dark'|'system'; palette: string; skin: string }
export const appearanceModes = ['light','dark','system'] as const;
export const appearancePalettes = ['terracotta','moss','sea','twilight','plum','rose'];
export const appearanceSkins = ['paper','modern','terminal','forest','blossom','lavender'];
export function readAppearance(value: unknown): SharedAppearance|null {
 if(!value || typeof value!=='object') return null;
 const p=value as SharedAppearance;
 return p.v===1 && appearanceModes.includes(p.mode) && appearancePalettes.includes(p.palette) && appearanceSkins.includes(p.skin) ? p : null;
}
export function withAppearance(current:AiSettings|null, preference:SharedAppearance):AiSettings {
 if(!readAppearance(preference)) throw new Error('Unsupported appearance');
 const raw=current?.chapterAppearance;
 if(raw!==undefined && raw!==null && !readAppearance(raw)) throw new Error('A newer/unsupported appearance is preserved. Upgrade before editing it.');
 const base=current ?? defaultAiSettings();
 return {...base,chapterAppearance:{...(raw as Record<string,unknown>|undefined),...preference}};
}

/** An AI form may predate a theme update. Clear credentials without clearing theme. */
export function withAiSettingsPreservingAppearance(current:AiSettings|null,next:AiSettings|null):AiSettings|null {
 if(current?.chapterAppearance!==undefined) return {...(next??defaultAiSettings()),chapterAppearance:current.chapterAppearance};
 return next;
}
