import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const errorRate = new Rate('errors');

// Stress test - find breaking point
export const options = {
  stages: [
    { duration: '2m', target: 100 },  // Ramp to 100 users
    { duration: '5m', target: 100 },  // Stay at 100
    { duration: '2m', target: 200 },  // Ramp to 200
    { duration: '5m', target: 200 },  // Stay at 200
    { duration: '2m', target: 300 },  // Ramp to 300
    { duration: '5m', target: 300 },  // Stay at 300
    { duration: '2m', target: 0 },    // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(99)<1500'], // 99% under 1.5s
    errors: ['rate<0.2'],              // Error rate under 20%
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

export default function () {
  const responses = http.batch([
    ['GET', `${BASE_URL}/api/monitor/pages`],
    ['GET', `${BASE_URL}/api/monitor/results`],
    ['GET', `${BASE_URL}/api/actuator/health`],
  ]);

  responses.forEach((res) => {
    check(res, { 'status 200': (r) => r.status === 200 });
    errorRate.add(res.status !== 200);
  });

  sleep(0.5);
}
