import { sleep } from 'k6';
import { authHeaders } from './helpers/auth.js';
import { userSession } from './helpers/flows.js';
export { handleSummary } from './helpers/summary.js';

export const options = {
  stages: [
    { duration: '1m', target: 30 },
    { duration: '28m', target: 30 },
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<300', 'p(99)<1000'],
    http_req_failed: ['rate<0.001'],
    checks: ['rate>0.99'],
  },
};

export default function () {
  const auth = authHeaders();
  if (!auth) return;

  userSession(auth);
  sleep(Math.random() * 3 + 2);
}
