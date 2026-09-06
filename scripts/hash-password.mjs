#!/usr/bin/env node
/**
 * Izpiši scrypt has za geslo, da ga lahko vpišeš v config.json
 * (namesto da bi geslo pisal v navadnem besedilu).
 *   node scripts/hash-password.mjs "Moje#trdnoGeslo12"
 */
import { hashPassword } from '../src/auth.js';

const pw = process.argv[2];
if (!pw) {
  console.error('Uporaba: node scripts/hash-password.mjs "<geslo>"');
  process.exit(1);
}
if (pw.length < 12) {
  console.error('Geslo mora imeti vsaj 12 znakov.');
  process.exit(1);
}
console.log(JSON.stringify({ admin: { username: 'admin', password: pw } }, null, 2));
console.log('\nPriporočilo: geslo pusti v config.json (ki NI na GitHubu) ali v okoljski spremenljivki ADMIN_PASSWORD.');
console.log('Ob prvem zagonu ga aplikacija zhašira sama. Ročni has za zapis v data/users.json:');
console.log(hashPassword(pw));
