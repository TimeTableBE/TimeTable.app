const { getStore } = require('@netlify/blobs');

const json = (statusCode, body) => ({
  statusCode,
  headers: {
    'content-type': 'application/json; charset=utf-8',
  },
  body: JSON.stringify(body),
});

const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

const normalizeEmail = (value) => String(value || '').trim().toLowerCase();

const makeCode = (length = 8) => {
  let result = '';
  for (let i = 0; i < length; i++) {
    const idx = Math.floor(Math.random() * CODE_CHARS.length);
    result += CODE_CHARS[idx];
  }
  return result;
};

const makeKey = (email, code) => `invite:${email}:${code}`;

const getInvitesStore = () => {
  const siteID =
    process.env.NETLIFY_SITE_ID || process.env.SITE_ID || '';
  const token =
    process.env.NETLIFY_BLOBS_TOKEN ||
    process.env.NETLIFY_AUTH_TOKEN ||
    process.env.NETLIFY_ACCESS_TOKEN ||
    '';

  // Preferred path when Blobs context is auto-injected by Netlify.
  if (!siteID || !token) {
    return getStore('invites');
  }

  // Fallback path for environments where Blobs context is not auto-configured.
  return getStore({
    name: 'invites',
    siteID,
    token,
  });
};

const sanitizeRecord = (record) => ({
  code: String(record.code || ''),
  email: normalizeEmail(record.email),
  name: String(record.name || ''),
  role: String(record.role || ''),
  company: String(record.company || ''),
  invitedBy: String(record.invitedBy || ''),
  contractor: String(record.contractor || ''),
  team: String(record.team || ''),
  createdAt: String(record.createdAt || ''),
  expiresAt: String(record.expiresAt || ''),
  used: record.used === true,
});

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return json(405, { error: 'Method not allowed' });
  }

  let payload;
  try {
    payload = JSON.parse(event.body || '{}');
  } catch (_) {
    return json(400, { error: 'Invalid JSON body' });
  }

  const action = String(payload.action || '').trim();
  const email = normalizeEmail(payload.email);
  const code = String(payload.code || '').trim().toUpperCase();

  if (!action) {
    return json(400, { error: 'Action is verplicht.' });
  }

  if (!email || !email.includes('@')) {
    return json(400, { error: 'Geldig e-mailadres is verplicht.' });
  }

  let store;
  try {
    store = getInvitesStore();
  } catch (error) {
    return json(500, {
      error:
        error && error.message
          ? error.message
          : 'Blobs store niet beschikbaar.',
    });
  }

  if (action === 'create') {
    const name = String(payload.name || '').trim();
    const role = String(payload.role || '').trim();
    const company = String(payload.company || '').trim();
    const invitedBy = String(payload.invitedBy || '').trim();
    const contractor = String(payload.contractor || '').trim();
    const team = String(payload.team || '').trim();
    const ttlHoursRaw = Number(payload.ttlHours || 24);
    const ttlHours = Number.isFinite(ttlHoursRaw)
      ? Math.max(1, Math.min(168, Math.floor(ttlHoursRaw)))
      : 24;
    if (!name || !role || !company) {
      return json(400, { error: 'Naam, rol en bedrijf zijn verplicht.' });
    }
    let newCode = '';
    let key = '';
    for (let i = 0; i < 8; i++) {
      newCode = makeCode();
      key = makeKey(email, newCode);
      // eslint-disable-next-line no-await-in-loop
      const exists = await store.get(key, { type: 'json' });
      if (!exists) break;
    }
    if (!newCode || !key) {
      return json(500, { error: 'Code genereren mislukt.' });
    }
    const now = new Date();
    const expiresAt = new Date(now.getTime() + ttlHours * 60 * 60 * 1000);
    const record = sanitizeRecord({
      code: newCode,
      email,
      name,
      role,
      company,
      invitedBy,
      contractor,
      team,
      createdAt: now.toISOString(),
      expiresAt: expiresAt.toISOString(),
      used: false,
    });
    await store.setJSON(key, record);
    return json(200, { ok: true, invite: record });
  }

  if (!code) {
    return json(400, { error: 'Code is verplicht.' });
  }

  const key = makeKey(email, code);
  const existing = await store.get(key, { type: 'json' });
  if (!existing) {
    return json(404, { error: 'Code niet gevonden.' });
  }
  const record = sanitizeRecord(existing);
  if (record.used) {
    return json(409, { error: 'Code is al gebruikt.' });
  }
  const now = Date.now();
  const expiresAtMs = Date.parse(record.expiresAt);
  if (!Number.isFinite(expiresAtMs) || now > expiresAtMs) {
    return json(410, { error: 'Code is verlopen.' });
  }

  if (action === 'validate') {
    return json(200, { ok: true, invite: record });
  }

  if (action === 'consume') {
    record.used = true;
    await store.setJSON(key, record);
    return json(200, { ok: true, invite: record });
  }

  return json(400, { error: 'Ongeldige action. Gebruik create, validate of consume.' });
};
