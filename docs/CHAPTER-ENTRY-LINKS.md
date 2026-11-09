# Native local entry links and backlinks

Source-grounded contracts: original `editor/wikilink.ts` (`entryId`,`label`,live
resolved title), `editor/doc.ts:docEntryLinks` (document order/duplicates),
`screens/Editor.tsx` backlinks (exclude self/deleted,descending updatedAt).
Original body JSON is never rewritten to navigate or resolve a title.

Implemented native inline attributed links, supplemental accessible links,
native NavigationStack destinations and reverse links from downloaded entries.
Unavailable/deleted links explain the actual state, retain original content and
never silently restore writing. Only an explicit available sync button contacts
YOUR configured authenticated relay; no Chapter account, external resolver,
telemetry, web wrapper or new third-party SDK/content request exists.

Entry IDs are URLComponents QUERY DATA under fixed internal `chapter-entry://open`.
No ID can become a host or an outbound network URL. Strict parser rejects external
schemes/hosts,credentials,paths,extra query items/fragments and control/oversized
IDs; Unicode spelling and URL-special characters roundtrip exactly. External
http/https/mailto links keep the preexisting explicit outside-app confirmation.

Four real Foundation tests PASS for original fixture, exact URI/Unicode/host
safety, duplicate/opaque descendant collection, malformed data, backlink ordering
and no mutation. Actual original web docEntryLinks comparison is mandatory in
native reverse interop; new UI tests cover genuine target/backlink/back navigation
and honest missing offline state. Planned real captures44–46. Apple tests/build/
UI/captures still pending latest CI; this is NOT certified full link/editor parity.
Link authoring/search picker, full inline selected-text editing and every original
custom renderer remain separate incomplete feature groups.

## Native link authoring — November 9, 2026

Entry → More → **Link to another entry** opens a picker that mirrors the original
web `[[` suggester (`wikilink.ts buildEntryLinkItems`): other live downloaded
entries only (never the current, deleted or non-entry records), title search with
ECMAScript `trim`/`toLowerCase`/UTF-16 `includes` semantics (an NFC query does not
match an NFD title, as on the web), most recently updated first, at most eight,
empty title shown as "Untitled".

Choosing an entry appends a paragraph holding exactly the web `insertEntryLink`
content: `{type:"entryLink",attrs:{entryId,label}}` followed by a `" "` text node.
It is a compare-and-set on the exact original document bytes (a concurrent or
canonically-equivalent change refuses without mutation). All existing blocks,
root attrs, opaque nodes/marks and future record fields are retained; bodyText is
the original web docToText. Apple CI writes the native result and the actual web
schema, `docEntryLinks` and `docToText` must accept it unchanged.

Not yet: inserting at a cursor position inside an existing paragraph (native
editing has no selection model yet), or linking entries that are not downloaded.
