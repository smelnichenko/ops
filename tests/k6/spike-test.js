import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const errorRate = new Rate('errors');

// Spike test - sudden traffic surge
export const options = {
  stages: [
    { duration: '10s', target: 10 },   // Warm up
    { duration: '1m', target: 10 },    // Normal load
    { duration: '10s', target: 200 },  // Spike!
    { duration: '3m', target: 200 },   // Stay at spike
    { duration: '10s', target: 10 },   // Scale down
    { duration: '1m', target: 10 },    // Recovery
    { duration: '10s', target: 0 },    // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<2000'], // 95% under 2s during spike
    errors: ['rate<0.3'],              // Allow higher error rate during spike
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

export default function () {
  const res = http.get(`${BASE_URL}/api/monitor/results`);
  check(res, {
    'status 200': (r) => r.status === 200,
  });
  errorRate.add(res.status !== 200);
  sleep(0.3);
}
