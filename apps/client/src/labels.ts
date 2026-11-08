// Original LabelField normalization, shared with native compatibility fixtures.
export function normalizeEntryLabel(raw: string): string {
  return raw.trim().toLowerCase().replace(/\s+/g, ' ');
}
