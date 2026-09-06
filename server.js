#!/usr/bin/env node
/**
 * CodeX Community — vstopna točka.
 * Zagon:  node server.js          (ali: npm start)
 * Na Windows Server 2022 to zagone scripts/install-windows.ps1 kot samodejno storitev.
 */
import { createApp } from './src/app.js';
import { loadConfig } from './src/config.js';

const config = loadConfig();
const app = createApp(config);

const ac = await app.listen();

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
// Windows nima pravih signalov; ustavitev skozi Ctrl+C ali "Stop-Process".
process.on('unhandledRejection', (err) => app.logger.error('unhandledRejection', err));
process.on('uncaughtException', (err) => {
  app.logger.error('uncaughtException', err);
  // Ne umri takoj — sicer bi bil VPS nedosegljiv; zabeleži in nadaljuj.
});

async function shutdown(signal) {
  console.log(`\n[${config.siteName}] prejem signala ${signal} - varno zaključujem zapise ...`);
  try {
    await app.close();
  } catch (err) {
    console.error('zapiranje ni uspelo:', err);
  }
  process.exit(0);
}

const shown = config.publicUrl || `http://${ac.address === '0.0.0.0' ? 'localhost' : ac.address}:${ac.port}`;
console.log(`
  ${'='.repeat(58)}
   ${config.siteName} · ${config.siteTagline}
   strani:   ${shown}
   admin:    ${shown}/admin
   podatki:  ${config.dataDirAbs}
   posluša:  ${ac.address}:${ac.port}  (uporabnik: ${process.env.USERNAME || process.env.USER || 'unknown'})
  ${'='.repeat(58)}
`);
