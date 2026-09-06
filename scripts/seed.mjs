#!/usr/bin/env node
/**
 * Naloži vzorčne podatke (za test na napravo / lokalni ogled).
 *   node scripts/seed.mjs            -> uporabi ./data
 *   node scripts/seed.mjs --dir=tmp  -> uporabi ./tmp-data
 *
 * NE uporabi na produkciji, razen če res želiš vzorčne igralce.
 */
import fs from 'node:fs';
import path from 'node:path';
import { Store } from '../src/store.js';
import { Logger } from '../src/logs.js';
import { WhitelistService } from '../src/whitelist.js';
import { nowIso, shortCode } from '../src/util.js';

const argDir = process.argv.indexOf('--dir');
const dataDir = path.resolve(process.cwd(), argDir > -1 ? `${process.argv[argDir + 1]}-data` : 'data');
fs.mkdirSync(dataDir, { recursive: true });

const logger = new Logger(path.join(dataDir, 'logs'));
await logger.init();
const store = new Store(dataDir, { logger });
await store.init();
const config = {
  siteName: 'CodeX Community',
  dataDirAbs: dataDir,
  exportFileAbs: path.join(dataDir, 'fivem-whitelist.json'),
  whitelist: { copyTo: [] },
  csrfSecret: 'seed',
  api: { token: '' },
  logs: {},
};
const wl = new WhitelistService({ store, logger, config });

const lic = (s) => `license:${s}`;
const players = [
  ['Luka_Kova', 'Luka Kovačič', 'luka.codex', 'STEAM_0:1:48231055', lic('a1b2c3d4e5f60718293a4b5c6d7e8f9012345678'), 'active', 'Mehanik', 'Zelo aktiven, igra 3x tedensko.'],
  ['Ana_Novak', 'Ana Novak', 'ana_n', 'STEAM_0:0:22114877', lic('0f1e2d3c4b5a69788796a5b4c3d2e1f0a9b8c7d6'), 'active', 'Zdravarka', 'Izkušnje iz drugih RP strežnikov.'],
  ['Marko_Zupan', 'Marko Zupan', 'markoz', 'STEAM_0:1:99887766', lic('5a4b3c2d1e0ff1e2d3c4b5a697887960a1b2c3d4'), 'trial', 'Taksi', 'Nov - preizkusna doba do konca tedna.'],
  ['Jaka_Potok', 'Jaka Potok', 'jaka.p', 'STEAM_0:0:10293847', lic('99887766554433221100ffeeddccbbaa99887766'), 'inactive', '-', 'Ni se javljal 3 tedne.'],
  ['Nina_Kralj', 'Nina Kralj', 'nina.kralj', 'STEAM_0:1:65432198', lic('12121212343434345656565678787878abcdefab'), 'active', 'Policija', 'Igra samo ob vikendih.'],
  ['Rok_Maver', 'Rok Maver', 'rokm', 'STEAM_0:1:11223344', lic('feedfacecafebeefdeadbeefcafebabe12345678'), 'banned', '-', 'RDM in varypanje - trajni ban.'],
];

const applications = [
  ['Matej_Hrib', 'Matej Hribar', 'matej.hrib', 'STEAM_0:1:77665544', lic('aabbccddeeff00112233445566778899aabbccdd'), 21, 'Zdravnik, ki je začel sodelovati v epizodi "Pomladna utrip" in ima 3 leta izkušenj na RP strežnikih. Rad imam resno in spoštljivo vzdušje.', 'approved'],
  ['Tine_Vrh', 'Tine Vrhovnik', 'tine.vrh', 'STEAM_0:0:66554433', lic('1029384756abcdef0123456789abcdef01234567'), 19, 'Mehanik ali morda kakšno serijsko vozilo. Igram približno 15 ur tedensko, nimam izkušenj z FiveM, sem imel pa 4 leta SA:MP.', 'pending'],
  ['Zala_Kot', 'Zala Kotnik', 'zala.kot', 'STEAM_0:1:33445566', lic('9876543210fedcba9876543210fedcba98765432'), 24, 'Iščem resen RP na daljši rok. Prejšnji strežnik je propadel, ker ni bilo osebja. Rad bi igral odvetnika ali tiskarno.', 'approved'],
  ['Bostjan_Ravan', 'Boštjan Ravan', 'boto.r', 'STEAM_0:0:44556677', lic('abcd0123ef5678901234567890abcdef12345678'), 17, 'Mafija, vozila. Nimam mikrofon, ampak pišem hitro. Rad bi imel resne RP situacije, kjer se ne strelja takoj na vsakogar.', 'denied'],
  ['Jure_Klanec', 'Jure Klanec', 'jure.k', 'STEAM_0:1:88990011', lic('ffeeddccbbaa99887766554433221100ffeeddcc'), 20, 'Zanima me policija, sem 2 leti gasilec v realnem življenju, zato mi je ta struktura blizu.', 'more_info'],
];

for (const [ingame, name, discord, steam, license, status, job, notes] of players) {
  await store.insert('players', { ingame, name, discord, steam, license, status, job, notes, wlExpires: null });
  logger.info('player.create', `vzorčni igralec ${ingame} dodan`, { actor: 'seed', ip: '127.0.0.1' });
}

for (const [ingame, name, discord, steam, license, age, message, status] of applications) {
  const code = shortCode('CDX');
  const app = await store.insert('applications', {
    code, name, ingame, discord, steam, license, age, message, status,
    ip: '127.0.0.1', submittedAt: nowIso(), reviewNote: '', reviewedAt: null, reviewedBy: null,
  });
  logger.info('app.submit', `vzorcna prijava ${code} (${ingame})`, { ip: '127.0.0.1' });
  if (status === 'approved') {
    await wl.add({ identifier: license, ingame, discord, note: `prijava ${code}`, addedBy: 'admin', source: 'application', applicationId: app.id });
    await store.update('applications', app.id, { status: 'approved', reviewedAt: nowIso(), reviewedBy: 'admin', reviewNote: 'Vse v redu - dobrodošel.' });
    logger.info('app.approve', `prijava ${code} odobrena (vzorec)`, { actor: 'admin', ip: '127.0.0.1' });
  }
  if (status === 'denied') {
    await store.update('applications', app.id, { status: 'denied', reviewedAt: nowIso(), reviewedBy: 'admin', reviewNote: 'Starost in odsotenost mikrofona. Poskusi čez 30 dni.' });
    logger.info('app.deny', `prijava ${code} zavrnjena (vzorec)`, { actor: 'admin', ip: '127.0.0.1' });
  }
}

const info = await wl.export({ actor: 'seed', quiet: true });
await store.snapshot('seed');
console.log(`shranjeno: ${store.count('players')} igralcev, ${store.count('applications')}`
  + ` prijav, ${info.count} na whitelisti (izvoz: ${info.file})`);
console.log(`Vzorčno geslo za prijavo v admin: uporabnik "admin" (ustvari se ob prvem zagonu aplikacije).`);
await logger.close();
