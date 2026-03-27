import { sleep } from 'k6';
import { authHeaders } from './helpers/auth.js';
import { userSession } from './helpers/flows.js';
export { handleSummary } from './helpers/summary.js';

export const options = {
  stages: [
    { duration: '30s', target: 10 },
    { duration: '1m', target: 10 },
    { duration: '10s', target: 150 },
    { duration: '2m', target: 150 },
    { duration: '10s', target: 10 },
    { duration: '1m', target: 10 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<2000'],
    http_req_failed: ['rate<0.05'],
    checks: ['rate>0.95'],
  },
};

export default function () {
  const auth = authHeaders();
  if (!auth) return;

  userSession(auth);
  sleep(Math.random() + 0.5);
}
