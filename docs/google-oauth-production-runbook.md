# Google OAuth Production Setup Runbook

King Mongkut Social requires Google Sign-In with university email addresses (@kmutt.ac.th, @kmitl.ac.th, @kmutnb.ac.th).

## 1. Google Cloud Console Configuration

1. Navigate to [Google Cloud Console](https://console.cloud.google.com/) -> **APIs & Services** -> **Credentials**.
2. Create or select your OAuth 2.0 Web Application client:
   - **Application type**: Web application
   - **Name**: `King Mongkut Social Production`

### Authorized JavaScript origins:
- `https://denmannsolutions.com`
- `https://www.denmannsolutions.com`

### Authorized redirect URIs:
- `https://api.denmannsolutions.com/api/v1/auth/google/callback`

> [!IMPORTANT]
> The backend validation strictly checks:
> - Protocol must be `https:` in production
> - Callback pathname must be `/api/v1/auth/google/callback`
> - `COOKIE_SECURE=true` and `COOKIE_SAME_SITE=none` must be enabled for cross-origin cookie authorization between `denmannsolutions.com` and `api.denmannsolutions.com`.

## 2. University Account Restrictions

The backend validates that the signed-in user's email belongs to one of the three King Mongkut universities:
- King Mongkut's University of Technology Thonburi (`KMUTT`)
- King Mongkut's Institute of Technology Ladkrabang (`KMITL`)
- King Mongkut's University of Technology North Bangkok (`KMUTNB`)

Users signing in with regular `@gmail.com` accounts will receive a descriptive error instructing them to use their university Google account.

## 3. Post-Authentication Flow

1. User clicks **เข้าสู่ระบบด้วย Google** on `https://denmannsolutions.com/login`.
2. Browser navigates to `https://api.denmannsolutions.com/api/v1/auth/google`.
3. User authorizes Google account.
4. Google redirects to `https://api.denmannsolutions.com/api/v1/auth/google/callback`.
5. API issues HttpOnly Secure `refresh_token` cookie and redirects back to `https://denmannsolutions.com/auth/callback` with short-lived token handoff.
6. Frontend initializes session and redirects to onboarding profile completion or main feed.
