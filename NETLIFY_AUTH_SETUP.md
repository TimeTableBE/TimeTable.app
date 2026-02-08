# Netlify Auth Setup (registratie, verificatie, reset, uitnodiging)

## 1) Netlify Identity activeren
- Open je Netlify site.
- Ga naar `Identity` en activeer Netlify Identity.
- Zet `Registration` op `Open`.
- Zet `Email confirmations` uit (account mag direct bruikbaar zijn).

## 2) Service-role token
- In Netlify Identity: kopieer de admin/service token.
- In Netlify Site Settings -> Environment variables voeg toe:
  - `NETLIFY_SITE_URL` = `https://jouw-site.netlify.app`
  - `NETLIFY_IDENTITY_ADMIN_TOKEN` = jouw service token

## 3) Flutter app configureren
Start met dart-defines:

```bash
flutter run \
  --dart-define=NETLIFY_SITE_URL=https://jouw-site.netlify.app \
  --dart-define=NETLIFY_INVITE_FUNCTION_PATH=/.netlify/functions/send-invite
```

## 4) Wat er nu automatisch werkt
- Registratie: bevestigingsmail wordt verstuurd, account is direct bruikbaar.
- Login: alleen na correcte credentials.
- Wachtwoord vergeten: resetmail via Netlify Identity.
- Uitnodigen (rollenbeheer): Netlify Function `send-invite` stuurt uitnodiging.

## 5) GitHub + Netlify
- Connect je GitHub repo in Netlify.
- Build command (Flutter web):

```bash
cd timetable_app && flutter build web
```

- Publish directory:

```text
timetable_app/build/web
```

## 6) Belangrijke noot
In deze app blijft domeindata (rollen/projecten) lokaal in app-opslag. Voor productie multi-device sync heb je nog een centrale database nodig (bv. Supabase/Postgres API).
