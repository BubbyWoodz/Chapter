# Actual native screen capture inventory

This inventories implemented SwiftUI user-facing screens, NOT all original Mneme
features. Unimplemented features have no fabricated screen. Required Simulator
UI tours export unchanged screenshots in `Chapter-actual-page-screenshots` before
separate strict production accessibility/functional runs. Observe the actual
Xcode attachment manifest and test results; source calls are intended coverage,
not proof that navigation/capture succeeded. Only screenshot tours disable
animations for settled static frames; the actual system-media/picker tour and production audits retain normal animations.

| Implemented screen | Intended genuine capture states |
|---|---|
| ConnectView | 00 URL/recovery unlock; no real secrets |
| EntryList | 01 Journal, 02 local search; 43 notebook-filtered list with original cover/subtitle/cards (fresh capture pending) |
| CalendarView | 04 real graphical calendar and local counts |
| NotebookList | 05 shelf, 08 actual create dialog |
| NotebookEditor | 06 metadata/color form, 07 actual cover-pattern choices |
| NotebookDeletionView | 33 reviewed downloaded-set deletion; complete apply/restore independently tested |
| EntryDetail | 09 reader, 10 actions, 31 plain-edit choices, 27 real deletion confirmation |
| EntryMetadataEditor | 16 title/date/individual labels |
| MoveEntryView | 11 form, 12 actual notebook choices |
| EntryEditor | 03 new, 32 existing plain, 36 failed-writing recovery controls, 41 resumed writer |
| RichEntryEditor | 13 actual original rich-node/run list |
| RichStructureEditor | 42 actual whole-block arrangement; fresh capture pending |
| RichDraftEditor | 14 text run, 15 expanded formats, 29 new block, 30 all block styles, 35 resumed draft |
| SettingsView | 17 upper, 22 lower, 26 durable media outbox, 28 original recovery, 34 rich drafts, 37 writing recovery |
| AppearanceSettings | 18 style choices, 19 palette choices, 20 mode choices, 21 actual dark Forest |
| ChapterFontLicenses | 23 local licensed font text; engineering diagnostic is not a user page |
| Actual media UI/system surfaces | 24 controls/pending queue, 25 genuine protected offline decrypted Quick Look, 38 actual Files picker, 39 actual Photos picker, 40 honest unsupported-file error |

## Coverage boundaries

Even if all intended captures exist this is not all-feature parity, final design,
accessibility certification, real server authentication proof or iPhone delivery.
Device-specific permission/biometrics/passcode prompts, landscape/iPad,
VoiceOver/RTL/locales, all six skins×six palettes×three modes, full scrolling,
privacy/background shield, interruption/provider/download/network-error states,
real imported photo/video/audio playback and every control sub-state are NOT
certified by this gallery. Notebook-filtered Journal and all alternate plain-edit
paths/metadata pickers need explicit capture as needed. Native source remains
unfinished; math/media/custom nodes are simplified. Web live visual comparison
has not succeeded. Professional coherent fidelity is required, not claimed.

Public data only. Default rich fixture uses a real encrypted local store and no
identity/relay. Optional media fixture adds a PUBLIC identity plus real protected
media staging/queue/original encryption, never a fake server or auth/upload success.
Original ciphertext/keys/record/auth protocol remain unchanged. A documented
server correction now reports retryable500/503 instead of falsely acknowledging
failed media cleanup; it does not change the native visual fixtures.

## Observed94bbbc8 gallery (November8,2026)

Actual42-state dedicated tour42525937610 PASSED. Visual review delivered40 usable
unchanged states:25 showed only blank loading Quick Look chrome and39 showed a
Photos loading spinner, so neither was falsely presented as a fully rendered
media/picker screen. New tests require actual decrypted text and completed system
preview dismissal. The additional arrangement screen42 is a new planned capture,
not yet observed. Current galleries and actual source inventories are versioned;
never blend builds/themes without labels.
