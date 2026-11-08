import { useCallback, useEffect, useState, useRef } from 'preact/hooks';
import { readAppearance, type SharedAppearance } from '../appearance/shared';
import { darken, hexA } from '../ui/color';

const MODE_KEY = 'mneme.theme.mode';
const PALETTE_KEY = 'mneme.theme.palette';
const SKIN_KEY = 'mneme.theme.skin';
const LEGACY_DARK_KEY = 'mneme.theme.dark'; // pre-preferences boolean toggle

export type ThemeMode = 'light' | 'dark' | 'system';

export interface ThemePalette {
  id: string;
  accent: string;
}

/** Accent tints, orthogonal to the skin: any accent works on any skin.
 * Muted, ink-compatible tones; the default terracotta first. */
export const PALETTES: ThemePalette[] = [
  { id: 'terracotta', accent: '#B0563A' },
  { id: 'moss', accent: '#6F7D4D' },
  { id: 'sea', accent: '#3F7B82' },
  { id: 'twilight', accent: '#5C6291' },
  { id: 'plum', accent: '#91527D' },
  { id: 'rose', accent: '#C25573' },
];

// Display names/hints live in the i18n catalog (`prefs.skin.*` /
// `prefs.palette.*`), not here — a second English copy on the data would
// silently drift from what the picker actually renders.
export interface ThemeSkin {
  id: string;
  /** Palette id adopted when the skin is picked (re-tintable afterwards). */
  accent: string;
  /** Swatch colors for the picker card (the skin's signature variant). */
  preview: { bg: string; ink: string; accent: string };
}

/** Full themes: each redefines the surface/ink ramp (and for some, the type)
 * via [data-skin] blocks in styles/tokens.css. Paper is the brand default. */
export const SKINS: ThemeSkin[] = [
  { id: 'paper', accent: 'terracotta', preview: { bg: '#f4eee2', ink: '#2a2521', accent: '#B0563A' } },
  { id: 'modern', accent: 'twilight', preview: { bg: '#fafafa', ink: '#1f1f1f', accent: '#5C6291' } },
  { id: 'terminal', accent: 'sea', preview: { bg: '#0d1117', ink: '#d7dee8', accent: '#3F7B82' } },
  { id: 'forest', accent: 'moss', preview: { bg: '#eef0e2', ink: '#232a1e', accent: '#6F7D4D' } },
  { id: 'blossom', accent: 'rose', preview: { bg: '#f9eef0', ink: '#322327', accent: '#C25573' } },
  { id: 'lavender', accent: 'twilight', preview: { bg: '#f0edf6', ink: '#2a2533', accent: '#5C6291' } },
];

function initialMode(): ThemeMode {
  const stored = localStorage.getItem(MODE_KEY);
  if (stored === 'light' || stored === 'dark' || stored === 'system') return stored;
  const legacy = localStorage.getItem(LEGACY_DARK_KEY);
  if (legacy !== null) return legacy === '1' ? 'dark' : 'light';
  return 'system';
}

function initialPalette(): string {
  const stored = localStorage.getItem(PALETTE_KEY);
  return stored && PALETTES.some((p) => p.id === stored) ? stored : PALETTES[0].id;
}

function initialSkin(): string {
  const stored = localStorage.getItem(SKIN_KEY);
  return stored && SKINS.some((s) => s.id === stored) ? stored : SKINS[0].id;
}

export interface ThemeControls {
  syncMessage: string;
  mode: ThemeMode;
  setMode: (m: ThemeMode) => void;
  /** Resolved dark flag (mode + system preference). */
  dark: boolean;
  /** Quick toggle (sidebar moon): pins an explicit light/dark over 'system'. */
  toggleDark: () => void;
  palette: string;
  setPalette: (id: string) => void;
  skin: string;
  /** Picking a skin also adopts its default accent (re-tintable afterwards). */
  setSkin: (id: string) => void;
}

/**
 * Theme layer: light/dark/system mode + accent palette, persisted per device
 * in localStorage before unlock; explicit changes also persist in existing encrypted vault settings. Mirrors the
 * design handoff's "tweaks" but keeps only the product-relevant bits; the
 * accent ramp is recomputed for dark (softer fills) like the prototype.
 */
export function useTheme(shared?: {value:unknown;ready:boolean;save:(p:SharedAppearance)=>Promise<void>}): ThemeControls {
  const [mode, setModeState] = useState<ThemeMode>(initialMode);
  const [palette, setPaletteState] = useState<string>(initialPalette);
  const [skin, setSkinState] = useState<string>(initialSkin);
  const [syncMessage,setSyncMessage]=useState('Appearance is local until you change it while a vault is unlocked.');
  const latest=useRef<SharedAppearance>({v:1,mode,palette,skin});
  const generation=useRef(0);
  useEffect(()=>{
    generation.current++;
    if(!shared?.ready) return;
    const remote=readAppearance(shared.value);
    if(remote) { latest.current=remote; setModeState(remote.mode);setPaletteState(remote.palette);setSkinState(remote.skin);
      localStorage.setItem(MODE_KEY,remote.mode);localStorage.setItem(PALETTE_KEY,remote.palette);localStorage.setItem(SKIN_KEY,remote.skin);
      setSyncMessage('Appearance loaded from encrypted vault settings.');
    } else if(shared.value) setSyncMessage('Unsupported shared appearance preserved; upgrade before editing.');
  },[shared?.value,shared?.ready]);
  const apply=useCallback((patch:Partial<SharedAppearance>)=>{
    const next={...latest.current,...patch}; latest.current=next;
    setModeState(next.mode);setPaletteState(next.palette);setSkinState(next.skin);
    localStorage.setItem(MODE_KEY,next.mode);localStorage.setItem(PALETTE_KEY,next.palette);localStorage.setItem(SKIN_KEY,next.skin);
    if(shared?.ready) { const attempt=generation.current; setSyncMessage('Saving encrypted appearance…');
      void shared.save(next).then(()=>{if(attempt===generation.current)setSyncMessage('Saved encrypted on this device; vault sync sends it to your other clients.');},()=>{if(attempt===generation.current)setSyncMessage('Appearance could not be saved to the vault. Local preview only; retry your choice.');});
    } else setSyncMessage('Local preview only. Unlock the vault to save a shared appearance.');
  },[shared?.ready,shared?.save]);
  const [systemDark, setSystemDark] = useState(
    () => window.matchMedia('(prefers-color-scheme: dark)').matches,
  );

  // 'system' follows the OS live, not just at startup.
  useEffect(() => {
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    const onChange = (e: MediaQueryListEvent): void => setSystemDark(e.matches);
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, []);

  const dark = mode === 'dark' || (mode === 'system' && systemDark);
  const accent = (PALETTES.find((p) => p.id === palette) ?? PALETTES[0]).accent;

  useEffect(() => {
    const root = document.documentElement;
    root.dataset.theme = dark ? 'dark' : 'light';
    root.dataset.skin = skin;
    root.style.setProperty('--accent', accent);
    root.style.setProperty('--accent-ink', darken(accent, dark ? 0 : 0.16));
    root.style.setProperty('--accent-soft', hexA(accent, dark ? 0.2 : 0.12));
    root.style.setProperty('--accent-line', hexA(accent, 0.28));
    // Keep the mobile browser chrome (Android status bar / iOS Safari) matching
    // the page background of the active skin+mode, so it no longer shows the
    // static light cream over a dark app. --paper is the base page background.
    const paper = getComputedStyle(root).getPropertyValue('--paper').trim();
    if (paper) {
      let meta = document.querySelector<HTMLMetaElement>('meta[name="theme-color"]');
      if (!meta) {
        meta = document.createElement('meta');
        meta.name = 'theme-color';
        document.head.appendChild(meta);
      }
      meta.content = paper;
    }
  }, [dark, accent, skin]);

  const setMode = useCallback((m:ThemeMode)=>apply({mode:m}),[apply]);
  const setPalette = useCallback((id:string)=>{if(PALETTES.some(p=>p.id===id))apply({palette:id});},[apply]);
  const setSkin = useCallback((id:string)=>{const value=SKINS.find(s=>s.id===id);if(value)apply({skin:id,palette:value.accent});},[apply]);

  const toggleDark = useCallback(() => setMode(dark ? 'light' : 'dark'), [dark, setMode]);

  return { syncMessage, mode, setMode, dark, toggleDark, palette, setPalette, skin, setSkin };
}
