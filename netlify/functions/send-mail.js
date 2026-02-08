const json = (statusCode, body) => ({
  statusCode,
  headers: {
    'content-type': 'application/json; charset=utf-8',
  },
  body: JSON.stringify(body),
});

const resendApiKey = process.env.RESEND_API_KEY || '';
const fromEmail = process.env.RESEND_FROM_EMAIL || '';

const sendResendEmail = async ({ to, subject, html }) => {
  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${resendApiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: fromEmail,
      to: [to],
      subject,
      html,
    }),
  });
  const body = await response.text();
  if (!response.ok) {
    let message = 'Mail verzenden mislukt.';
    try {
      const parsed = JSON.parse(body || '{}');
      message = parsed.message || parsed.error || message;
    } catch (_) {
      if (body && body.trim().length > 0) message = body;
    }
    throw new Error(message);
  }
};

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return json(405, { error: 'Method not allowed' });
  }

  if (!resendApiKey || !fromEmail) {
    return json(200, {
      ok: true,
      skipped: true,
      message: 'RESEND_API_KEY/RESEND_FROM_EMAIL ontbreken; mail overgeslagen.',
    });
  }

  let input;
  try {
    input = JSON.parse(event.body || '{}');
  } catch (_) {
    return json(400, { error: 'Invalid JSON body' });
  }

  const type = String(input.type || '').trim();
  const to = String(input.email || '').trim().toLowerCase();
  const name = String(input.name || '').trim();

  if (!to || !to.includes('@')) {
    return json(400, { error: 'Geldig e-mailadres is verplicht.' });
  }

  try {
    if (type === 'welcome') {
      const company = String(input.company || '').trim();
      await sendResendEmail({
        to,
        subject: 'Je TimeTable account is aangemaakt',
        html: `
          <p>Hallo ${name || 'gebruiker'},</p>
          <p>Je account voor <strong>${company || 'TimeTable'}</strong> is succesvol aangemaakt.</p>
          <p>Je kan nu inloggen in de app.</p>
          <p>Groeten,<br/>TimeTable</p>
        `,
      });
      return json(200, { ok: true, message: 'Welkomstmail verzonden.' });
    }

    if (type === 'invite_notice') {
      const role = String(input.role || '').trim();
      const invitedBy = String(input.invitedBy || '').trim();
      const company = String(input.company || '').trim();
      await sendResendEmail({
        to,
        subject: 'Je bent uitgenodigd voor TimeTable',
        html: `
          <p>Hallo ${name || 'gebruiker'},</p>
          <p>Je bent uitgenodigd voor <strong>${company || 'TimeTable'}</strong>.</p>
          <p>Rol: <strong>${role || 'Werknemer'}</strong></p>
          <p>Uitgenodigd door: <strong>${invitedBy || 'beheerder'}</strong></p>
          <p>Gebruik je e-mailadres om in te loggen of je account te activeren.</p>
          <p>Groeten,<br/>TimeTable</p>
        `,
      });
      return json(200, { ok: true, message: 'Uitnodigingsmail verzonden.' });
    }

    if (type === 'verified') {
      const company = String(input.company || '').trim();
      await sendResendEmail({
        to,
        subject: 'Verificatie geslaagd - Welkom bij TimeTable',
        html: `
          <p>Hallo ${name || 'gebruiker'},</p>
          <p>Je account voor <strong>${company || 'TimeTable'}</strong> is succesvol geverifieerd.</p>
          <p>Welkom bij <strong>TimeTable</strong>.</p>
          <p>Met TimeTable beheer je projecten, planning, rollen, documenten en werfopvolging op een overzichtelijke manier voor je volledige team.</p>
          <p>Je kan nu inloggen in de app en meteen starten.</p>
          <p>Groeten,<br/>TimeTable</p>
        `,
      });
      return json(200, { ok: true, message: 'Verificatiemail verzonden.' });
    }

    return json(400, { error: 'Ongeldig type. Gebruik welcome, invite_notice of verified.' });
  } catch (error) {
    return json(500, { error: error.message || 'Mail versturen mislukt.' });
  }
};
