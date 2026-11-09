// SPDX-License-Identifier: AGPL-3.0-or-later
// Imported first by native-vectors.ts: fflate writes ZIP entry times in LOCAL time, so the
// committed ZIP/Day One vectors are only reproducible in one fixed zone (CI runs in UTC).
process.env.TZ = 'America/Los_Angeles';
