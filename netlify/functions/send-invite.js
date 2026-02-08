const json = (statusCode, body) => ({
  statusCode,
  headers: {
    'content-type': 'application/json; charset=utf-8',
  },
  body: JSON.stringify(body),
});

const normalizeSiteUrl = (value) => {
  if (!value) return '';
  return value.endsWith('/') ? value.slice(0, -1) : value;
};

const postInvite = async ({ siteUrl, token, payload, path }) => {
  const response = await fetch(`${siteUrl}${path}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });
  return response;
};

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return json(405, { error: 'Method not allowed' });
  }

  const siteUrl = normalizeSiteUrl(process.env.NETLIFY_SITE_URL);
  const adminToken = process.env.NETLIFY_IDENTITY_ADMIN_TOKEN;

  if (!siteUrl || !adminToken) {
    return json(500, {
      error:
        'Server configuration ontbreekt. Zet NETLIFY_SITE_URL en NETLIFY_IDENTITY_ADMIN_TOKEN.',
    });
  }

  let input;
  try {
    input = JSON.parse(event.body || '{}');
  } catch (_) {
    return json(400, { error: 'Invalid JSON body' });
  }

  const email = String(input.email || '').trim().toLowerCase();
  const name = String(input.name || '').trim();
  const role = String(input.role || '').trim();

  if (!email || !email.includes('@')) {
    return json(400, { error: 'Geldig e-mailadres is verplicht.' });
  }
  if (!name) {
    return json(400, { error: 'Naam is verplicht.' });
  }
  if (!role) {
    return json(400, { error: 'Rol is verplicht.' });
  }

  const payload = {
    email,
    data: {
      name,
      role,
      company: String(input.company || '').trim(),
      contractor: String(input.contractor || '').trim(),
      team: String(input.team || '').trim(),
      invitedBy: String(input.invitedBy || '').trim(),
    },
  };

  const endpoints = [
    '/.netlify/identity/admin/invite',
    '/.netlify/identity/admin/invitations',
  ];

  let lastBody = '';
  let lastStatus = 500;
  for (const endpoint of endpoints) {
    const response = await postInvite({
      siteUrl,
      token: adminToken,
      payload,
      path: endpoint,
    });
    const text = await response.text();
    if (response.ok) {
      return json(200, { ok: true, message: 'Uitnodiging verzonden.' });
    }
    lastStatus = response.status;
    lastBody = text;
    if (response.status !== 404) {
      break;
    }
  }

  let message = 'Uitnodiging versturen mislukt.';
  try {
    const parsed = JSON.parse(lastBody || '{}');
    message =
      parsed.error_description || parsed.error || parsed.message || message;
  } catch (_) {
    if (lastBody && lastBody.trim().length > 0) {
      message = lastBody;
    }
  }

  return json(lastStatus || 500, { error: message });
};
