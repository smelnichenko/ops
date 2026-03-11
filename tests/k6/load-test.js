import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const apiDuration = new Trend('api_duration');

// Test configuration
export const options = {
  stages: [
    { duration: '30s', target: 10 },  // Ramp up to 10 users
    { duration: '1m', target: 10 },   // Stay at 10 users
    { duration: '30s', target: 50 },  // Ramp up to 50 users
    { duration: '1m', target: 50 },   // Stay at 50 users
    { duration: '30s', target: 0 },   // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],  // 95% of requests under 500ms
    errors: ['rate<0.1'],               // Error rate under 10%
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

export default function () {
  group('API Health', () => {
    const res = http.get(`${BASE_URL}/api/actuator/health`);
    check(res, {
      'health status 200': (r) => r.status === 200,
      'health status UP': (r) => r.json('status') === 'UP',
    });
    errorRate.add(res.status !== 200);
    apiDuration.add(res.timings.duration);
  });

  group('List Pages', () => {
    const res = http.get(`${BASE_URL}/api/monitor/pages`);
    check(res, {
      'pages status 200': (r) => r.status === 200,
      'pages is array': (r) => Array.isArray(r.json()),
    });
    errorRate.add(res.status !== 200);
    apiDuration.add(res.timings.duration);
  });

  group('Get Results', () => {
    const res = http.get(`${BASE_URL}/api/monitor/results`);
    check(res, {
      'results status 200': (r) => r.status === 200,
    });
    errorRate.add(res.status !== 200);
    apiDuration.add(res.timings.duration);
  });

  group('Get Config', () => {
    const res = http.get(`${BASE_URL}/api/monitor/config`);
    check(res, {
      'config status 200': (r) => r.status === 200,
    });
    errorRate.add(res.status !== 200);
    apiDuration.add(res.timings.duration);
  });

  sleep(1);
}

// Smoke test - quick validation
export function smoke() {
  const res = http.get(`${BASE_URL}/api/actuator/health`);
  check(res, { 'smoke test passed': (r) => r.status === 200 });
}
