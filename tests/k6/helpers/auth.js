import http from 'k6/http';

const KEYCLOAK_URL = __ENV.KEYCLOAK_URL || 'http://localhost:8180';
const CLIENT_ID = __ENV.K6_CLIENT_ID || 'k6-smoke';
const CLIENT_SECRET = __ENV.K6_CLIENT_SECRET || '';

let cachedToken = null;
let tokenExpiry = 0;

export function getToken() {
  const now = Date.now();
  if (cachedToken && now < tokenExpiry) return cachedToken;

  if (!CLIENT_SECRET) {
    console.error('K6_CLIENT_SECRET not set');
    return null;
  }

  const res = http.post(
    `${KEYCLOAK_URL}/realms/schnappy/protocol/openid-connect/token`,
    { client_id: CLIENT_ID, client_secret: CLIENT_SECRET, grant_type: 'client_credentials' },
    { tags: { name: 'token' } },
  );

  if (res.status !== 200) {
    console.error(`Token request failed: ${res.status} ${res.body}`);
    return null;
  }

  cachedToken = res.json('access_token');
  tokenExpiry = now + (res.json('expires_in') - 30) * 1000;
  return cachedToken;
}

export function authHeaders() {
  const token = getToken();
  return token ? { headers: { Authorization: `Bearer ${token}` } } : null;
}
