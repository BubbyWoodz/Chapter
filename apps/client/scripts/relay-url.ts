import assert from 'node:assert/strict';
import { normalizeRelayUrl } from '../src/sync/relay';
for (const value of ['https://user:secret@host/mneme', 'https://host/mneme?token=secret', 'https://host/#secret', 'javascript:alert(1)', '/mneme', 'server.local', 'ftp://server/file', '']) {
  assert.equal(normalizeRelayUrl(value), null, value);
}
for (const [input, expected] of [
  [' https://chapter.tailnet.ts.net/mneme/ ', 'https://chapter.tailnet.ts.net/mneme'],
  ['http://192.168.1.4:8080/', 'http://192.168.1.4:8080'],
  ['https://[fd7a:115c:a1e0::1]:8443/chapter/', 'https://[fd7a:115c:a1e0::1]:8443/chapter'],
]) assert.equal(normalizeRelayUrl(input), expected);
console.log('Relay URL privacy/compatibility regressions passed.');
