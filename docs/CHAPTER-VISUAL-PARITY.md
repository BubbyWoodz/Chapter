# Whole-app cross-client visual and functional acceptance

The user's requirement is **the same notebooks, covers, themes, colors, content and features**, responsively adapted to real native iOS controls — not a stripped-down list or web wrapper. Source correspondence alone is not visual verification. A simulator screenshot is not a real iPhone/device acceptance test.

| Original web source / experience | Native state | Visual/functional gate still required |
| --- | --- | --- |
| `screens/Journals.tsx`, `ui/primitives.tsx` mobile `Cover` | Notebook list/create/rename/subtitle/color/pattern editing; five real native patterned cover thumbnails added | Compare actual mobile web vs native screenshots for translucent covers/spine/border/all patterns; search/archive/delete/reorder/cascade semantics remain incomplete |
| `hooks/useTheme.ts`, `styles/tokens.css`, `ui/Preferences.tsx` | Original color catalog + native light/dark/system, six styles, six accents; optional encrypted shared preference added to updated web/native | Actual Apple and live bidirectional/restart/offline gates pending feature CI; row surfaces/typography and all screens need visual comparison; browser equal-clock/race acceptance remains open |
| `screens/JournalEntries.tsx`, `ui/Search.tsx`, `EntryThumbs.tsx`, `LabelField.tsx`, `EntryDateTime.tsx` | Native lists, local text/labels search and basic metadata exist | Web card content/thumbnail/date/label semantics, full filters/sorting/search and responsive layouts |
| `screens/Editor.tsx`, `editor/**` | Native lossless JSON viewer, formatted-run edits and tasks; opaque nodes retained | Complete structural editing and exact tables/math/custom nodes/layout; no lossy flattening or silent unsupported-node removal |
| `ui/Attachments.tsx`, `Lightbox.tsx` | Encrypted file/photo import, durable outbox, bounded upload/download/private previews | Actual selected-file/photos UI and interruption/physical-device checks; complete preview/playback/capture/large-file parity |
| `ui/AudioCapture.tsx`, `VideoCapture.tsx`, `FilmRender.tsx`, `VideoInterview.tsx` | Not complete | Real capture/edit/render/cancel/playback, compatible encrypted outputs and privacy cleanup |
| `screens/Calendar.tsx`, badge/reminder interfaces | Basic native calendar/day counts | Original calendar density, statistics, badges and reminders with native permissions/semantics |
| `ui/Templates.tsx`, `InterviewTypes.tsx`, `GuidedInterview.tsx`, `NewEntryWizard.tsx` | Data preserved, complete native managers/flows missing | All create/edit/apply/delete paths and rich document preservation |
| `ui/AiSettings.tsx`, `AiActionDialog.tsx`, `AskJournal.tsx`, transcription and provider badges | Opaque encrypted settings preserved; no automatic mobile AI requests | Explicit-consent native functionality matching server policy; no added telemetry or unrequested provider traffic |
| `ui/ImportDayOne.tsx`, `ExportJournal.tsx` | Not implemented natively | Import/export plus media, validation, progress/cancel and protected temporary files |
| `ui/LocationPicker.tsx`, maps | Not implemented natively | Same location semantics, explicit external content consent and permission behavior |
| `screens/Onboarding.tsx`, `PendingApproval.tsx`, `DeviceUnlock.tsx`, `RotatePhrase.tsx`, `DeleteVault.tsx`, `DeleteJournal.tsx` | Enter original recovery phrase/server + genuine original auth and protected local storage; native creation/rotation/destructive lifecycle incomplete | Exact original approval/recovery/rotation/deletion semantics, migration/recovery tests and user-confirmed destructive actions |
| i18n, preferences and original assets | Not full native localization or font/asset parity | Original locales/RTL, Dynamic Type, VoiceOver, keyboard, reduced-motion/contrast and original font licensing before embedding |

## Required comparison procedure

1. Render **actual** original web components with identical public synthetic fixtures; never infer an appearance from code or manufacture a reference image. Existing repository screenshots cover only their actual captured screens, not an unseen notebook shelf.
2. Capture native app rendering the same data and preferences. Compare phone-size original web alongside native, plus desktop web for content/feature availability. Native navigation/control adaptation is expected; disappearing covers, metadata, nodes or controls is not.
3. Cover all five notebook patterns and original colors; all skins and modes with independent accent override; long/multilingual titles; empty/full/error/loading/offline/conflict states; RTL and accessibility sizes. Catalog assertions prove token values, **not** rendered pixel fidelity or sufficient contrast.
4. Keep strict accessibility audits required. No filtering findings, accepting issues or weakening tests. Current prior production audit failures remain an explicit release blocker until actual replacement-run results pass.
5. Require per-feature native UI + compatible real-server tests, actual screenshots and reviewer sign-off. Signed real-iPhone testing, LAN/Tailscale/trusted HTTPS and signing/distribution remain later acceptance gates, not implied by source or Simulator builds.

## Local review preview (not committed or deployed)

The executor prepared a localhost-only Vite preview rendering the **actual** original `JournalsScreen` and original public sample `JOURNALS` under its real providers/fonts/tokens. Desktop: `http://127.0.0.1:4179/chapter-preview.html`; mobile adaptation: `http://127.0.0.1:4179/chapter-preview.html?mobile=1`. Notebook controls are intentionally disabled; light/dark toggle works. It is unauthenticated synthetic visual reference, **not** live server integration. The parent should visually inspect and capture this; the executor has not operated a browser or claimed to have seen it. Source preview files are ignored local helpers, not shipped in the product.

## Native card/navigation correction — source grounded, fresh images pending

Genuine `docs/screenshots/mobile-journal.png` was visually inspected again; it
shows original warm surfaces, notebook-colored leading card edges, serif titles
and notebook covers. Actual `screens/JournalEntries.tsx:84` and
`screens/Calendar.tsx:548` use14px radius,1px `--line`,3px notebook leading edge
and `--surface`. Native `ChapterEntryCard` now shares these original tokens,
heading/UI/mono roles across Journal and Calendar instead of generic white rows.
Layout/native chevrons/date placement adapt to iPhone; this is NOT full pixel parity.
A new required genuine screenshot RGB test checks Paper surface#fbf7ef and public
notebook#4e8b85 edge. It must pass before rendered colors are certified.

Source also revealed pushed notebook Journal created a SECOND NavigationStack;
only the root Journal tab now creates one. A real new shelf→filtered notebook→
entry→notebook→shelf UI test checks the native back path, and capture43 covers
this previously missing page. No data/network/crypto behavior changed.

Strict production onboarding audits remain required and failing in completed be
and94 runs; unknown-element unsupported Dynamic Type and intermittent XXXL server
reachability were inspected in real logs/screenshots. Native Form/SecureField
comparisons pass, not proof of a framework-wide false positive. A NEW isolated
full-width prominent bottom-CTA comparison tests one layout hypothesis, required
independently; it does not alter the production screen or ignore findings.
Required normal/XXXL audits now export their real evidence BEFORE independent
functional tests. Unreachable-control failures retain actual screenshot/hierarchy.

Outstanding professional gates: actual new-card/arrangement/back-stack screenshots,
dark interactive contrast, complete card/custom-node/math/table/interview fidelity,
all palettes/locales/VoiceOver/landscape, coherent recovery/settings copy, genuine
live original-web rendering comparison and physical-device usability. Passing
unit/pixel tests alone does not satisfy these gates or make this a final design.
