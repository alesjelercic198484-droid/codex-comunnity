import { sendJson } from '../http.js';
import { normalizeIdentifier } from '../util.js';

/**
 * JSON API za FiveM skripto (in za nadzorno ploščo).
 * Vključen je samo, če je config.api.enabled in je nastavljen token.
 */
function tokenOk(ctx) {
  const expected = ctx.config.api.token;
  if (!expected) return false;
  const given = ctx.query.get('token') || ctx.req.headers['x-api-key'] || '';
  return normalizeIdentifier(given) === normalizeIdentifier(expected);
}

function guard(ctx) {
  if (!ctx.config.api.enabled) return { code: 503, error: 'API je onemogočen (config.api.enabled = false).' };
  if (!ctx.config.api.token) return { code: 503, error: 'API token ni nastavljen. Ustvari ga v Admin → Nastavitve.' };
  if (!tokenOk(ctx)) return { code: 401, error: 'Neveljaven ali manjkajoč API token.' };
  return null;
}

export const apiRoutes = [
  {
    method: 'GET',
    path: '/api/health',
    public: true,
    handler: async (ctx) => {
      const { store, logger } = ctx.s;
      const st = logger.stats(24);
      sendJson(ctx.res, {
        ok: true,
        app: ctx.config.siteName,
        time: new Date().toISOString(),
        uptimeSeconds: Math.round((Date.now() - ctx.startedAt) / 1000),
        applications: { open: ctx.config.applications.open, pending: store.filter('applications', (a) => a.status === 'pending').length },
        whitelist: store.count('whitelist'),
        players: store.count('players'),
        errors24h: st.errors,
      });
    },
  },
  {
    method: 'GET',
    path: '/api/whitelist/check',
    public: true,
    handler: async (ctx) => {
      const err = guard(ctx);
      if (err) return sendJson(ctx.res, err, err.code);
      const license = ctx.query.get('license') || ctx.query.get('identifier') || '';
      if (!license) return sendJson(ctx.res, { error: 'Manjka parameter license ali identifier.' }, 400);
      const result = ctx.s.wl.check(license);
      if (!result.allowed) ctx.s.logger.debug('wl.check', `zavrnjeno: ${license} (${result.reason})`, { ip: ctx.ip });
      return sendJson(ctx.res, {
        allowed: result.allowed,
        reason: result.allowed ? null : result.reason,
        identifier: normalizeIdentifier(license),
        name: result.row?.ingame || null,
        expires: result.row?.expires || null,
        checkedAt: new Date().toISOString(),
      });
    },
  },
  {
    method: 'GET',
    path: '/api/whitelist',
    public: true,
    handler: async (ctx) => {
      const err = guard(ctx);
      if (err) return sendJson(ctx.res, err, err.code);
      const rows = ctx.s.wl.active.map((w) => ({ identifier: w.identifier, name: w.ingame || '', discord: w.discord || '', expires: w.expires || null }));
      return sendJson(ctx.res, { generatedAt: new Date().toISOString(), count: rows.length, whitelist: rows });
    },
  },
  {
    method: 'POST',
    path: '/api/whitelist/touch',
    public: true,
    csrfSkip: true,
    handler: async (ctx) => {
      // FiveM skripta lahko prijavo igralca zabeleži v dnevnik (kdaj je bil na strežniku)
      const err = guard(ctx);
      if (err) return sendJson(ctx.res, err, err.code);
      const license = normalizeIdentifier(ctx.body?.license || ctx.body?.identifier || '');
      if (!license) return sendJson(ctx.res, { error: 'Manjka license.' }, 400);
      const result = ctx.s.wl.check(license);
      ctx.s.logger.info('wl.hit', `igralec na strežniku: ${license}${result.row?.ingame ? ` (${result.row.ingame})` : ''}`, {
        meta: { allowed: result.allowed, serverId: ctx.body.serverId || null },
      });
      return sendJson(ctx.res, { ok: true, allowed: result.allowed });
    },
  },
];
