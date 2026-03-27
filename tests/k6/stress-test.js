import { sleep } from 'k6';
import { authHeaders } from './helpers/auth.js';
import { userSession } from './helpers/flows.js';
export { handleSummary } from './helpers/summary.js';

export const options = {
  stages: [
    { duration: '1m', target: 50 },
    { duration: '3m', target: 50 },
    { duration: '1m', target: 100 },
    { duration: '3m', target: 100 },
    { duration: '1m', target: 200 },
    { duration: '3m', target: 200 },
    { duration: '1m', target: 300 },
    { duration: '3m', target: 300 },
    { duration: '2m', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<1000', 'p(99)<3000'],
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
