import crypto from 'node:crypto';
import { nowIso, shortCode, raw } from '../util.js';
import { validateApplication, validateStatusQuery, normalizeLicense } from '../validate.js';
import { homePage, applyPage, submittedPage, statusPage, rulesPage, errorPage } from '../views/site.js';
import { publicRecent, statsFor } from '../services.js';

export const publicRoutes = [
  { method: 'GET', path: '/', handler: async (ctx) => {
    const { store } = ctx.s;
    const apps = store.list('applications');
    return ctx.html(homePage(ctx.config, {
      stats: statsFor(store),
      recent: publicRecent(apps),
      user: ctx.user,
      flash: ctx.takeFlash(),
    }));
  } },

  { method: 'GET', path: '/prijava', handler: async (ctx) => ctx.html(applyPage(ctx.config, {
    form: { csrf: ctx.csrfToken() }, flash: ctx.takeFlash(), values: {}, errors: {},
  })) },

  {
    method: 'POST',
    path: '/prijava',
    handler: async (ctx) => {
      const cfg = ctx.config;
      const { store, logger } = ctx.s;
      const form = { csrf: ctx.csrfToken() };

      if (!cfg.applications.open) {
        logger.warn('app.closed', `nekdo je poskusil oddati prijavo, ko so bile prijave zaprte`, { ip: ctx.ip });
        return ctx.html(applyPage(cfg, { form, flash: { kind: 'warn', text: 'Prijave so trenutno zaprte. Poskusi kasneje.' }, errors: {} }), 409);
      }

      const { ok, errors, values, honeypotHit } = validateApplication(ctx.body, cfg);

      if (honeypotHit) {
        // bot je izpolnil skrito polje - delamo, kot da je bilo vse v redu, a ne shranimo ničesar
        logger.warn('app.submit', 'spam preprečen z honeypot poljem', { ip: ctx.ip, meta: { ua: ctx.ua?.slice(0, 120) } });
        return ctx.html(submittedPage(cfg, { app: { code: 'CDX-' + crypto.randomBytes(3).toString('hex').toUpperCase().slice(0, 6), submittedAt: nowIso() } }));
      }

      if (!ok) {
        return ctx.html(applyPage(cfg, { form, errors, values, flash: { kind: 'bad', text: 'Preveri označena polja.' } }), 422);
      }

      // omejitev na IP (dnevno)
      const today = Date.now() - 86400000;
      const mine = store.filter('applications', (a) => a.ip === ctx.ip && Date.parse(a.submittedAt || a.createdAt) > today);
      if (mine.length >= Number(cfg.applications.maxPerIpPerDay)) {
        logger.warn('app.submit', `zavrnjeno: prekoračena dnevna omejitev prijav z IP ${ctx.ip}`, { ip: ctx.ip, meta: { count: mine.length } });
        return ctx.html(applyPage(cfg, {
          form,
          values,
          errors: {},
          flash: { kind: 'bad', text: `S tega naslova je bilo že oddanih ${mine.length} prijav. Počakaj 24 ur ali stopi v stik z ekipo na Discordu.` },
        }), 429);
      }

      const record = await store.insert('applications', {
        code: shortCode('CDX'),
        name: values.name,
        ingame: values.ingame,
        discord: values.discord.toLowerCase(),
        steam: values.steam,
        license: values.licenseNorm || normalizeLicense(values.license),
        age: Number(values.age),
        message: values.message,
        status: 'pending',
        ip: ctx.ip,
        submittedAt: nowIso(),
        submittedUa: String(ctx.ua || '').slice(0, 200),
        reviewNote: '',
        reviewedAt: null,
        reviewedBy: null,
      });

      logger.info('app.submit', `nova prijava ${record.code} (${record.ingame})`, {
        ip: ctx.ip,
        meta: { discord: record.discord, steam: record.steam, license: record.license, age: record.age },
      });

      return ctx.html(submittedPage(cfg, { app: record }));
    },
  },

  { method: 'GET', path: '/status', handler: async (ctx) => ctx.html(statusPage(ctx.config, {
    values: { csrf: ctx.csrfToken() },
  })) },

  {
    method: 'POST',
    path: '/status',
    handler: async (ctx) => {
      const { store } = ctx.s;
      const { ok, errors, values } = validateStatusQuery(ctx.body, ctx.config);
      if (!ok) return ctx.html(statusPage(ctx.config, { values: { ...values, csrf: ctx.csrfToken() }, errors }), 422);
      const app = store.list('applications').find(
        (a) => String(a.code).toUpperCase() === values.code && String(a.discord).toLowerCase() === values.discord);
      if (!app) {
        return ctx.html(statusPage(ctx.config, { values: { ...values, csrf: ctx.csrfToken() }, result: 'notfound' }));
      }
      // prikažemo samo tisto, kar je smiselno javno: status, čas, opomba
      return ctx.html(statusPage(ctx.config, {
        values: { ...values, csrf: ctx.csrfToken() },
        result: 'found',
        app: {
          code: app.code,
          ingame: app.ingame,
          status: app.status,
          submittedAt: app.submittedAt || app.createdAt,
          reviewedAt: app.reviewedAt,
          reviewNote: app.status === 'pending' ? '' : app.reviewNote,
        },
      }));
    },
  },

  { method: 'GET', path: '/pravila', handler: async (ctx) => ctx.html(rulesPage(ctx.config)) },

  {
    method: 'GET',
    path: '/.well-known/security.txt',
    handler: (ctx) => ctx.text(`Contact: ${ctx.config.discordInvite}\nAcknowledgments: ne\nPolicy: ${ctx.config.publicUrl}/pravila\n`, {
      'Cache-Control': 'public, max-age=3600',
    }),
  },

  {
    method: 'GET',
    path: '/sitemap.xml',
    handler: (ctx) => {
      const origin = ctx.origin();
      const urls = ['/', '/prijava', '/status', '/pravila'];
      return ctx.text(raw(`<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls.map((u) => `  <url><loc>${origin}${u}</loc><changefreq>weekly</changefreq></url>`).join('\n')}
</urlset>
`), { 'Content-Type': 'application/xml; charset=utf-8' });
    },
  },

  {
    method: 'GET',
    path: '/robots.txt',
    handler: (ctx) => ctx.text(`User-agent: *\nDisallow: /admin\nDisallow: /api\nAllow: /\nSitemap: ${ctx.config.publicUrl || ''}/sitemap.xml\n`),
  },
];

export function renderErrorPage(ctx, { code = 500, title, text }) {
  return ctx.html(errorPage(ctx.config, { code, title, text, user: ctx.user }), code);
}
