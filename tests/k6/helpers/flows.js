import http from 'k6/http';
import { check, group, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

export function publicFlow() {
  group('frontend', () => {
    const r = http.get(`${BASE_URL}/`);
    check(r, { 'frontend 200': (r) => r.status === 200 });
  });
  sleep(Math.random() * 2 + 1);

  group('health', () => {
    const r = http.get(`${BASE_URL}/api/health`);
    check(r, { 'health 200': (r) => r.status === 200 });
  });
}

export function browseMonitors(auth) {
  group('pages', () => {
    const r = http.get(`${BASE_URL}/api/monitor/pages`, auth);
    check(r, { 'pages 200': (r) => r.status === 200 });
  });
  sleep(Math.random() * 2 + 1);

  group('monitor-config', () => {
    const r = http.get(`${BASE_URL}/api/monitor/config`, auth);
    check(r, { 'config 200': (r) => r.status === 200 });
  });
}

export function browseRss(auth) {
  group('rss-feeds', () => {
    const r = http.get(`${BASE_URL}/api/rss/feeds`, auth);
    check(r, { 'feeds 200': (r) => r.status === 200 });
  });
  sleep(Math.random() * 2 + 1);

  group('rss-config', () => {
    const r = http.get(`${BASE_URL}/api/rss/config`, auth);
    check(r, { 'rss-config 200': (r) => r.status === 200 });
  });
}

export function browseChat(auth) {
  group('channels', () => {
    const r = http.get(`${BASE_URL}/api/chat/channels`, auth);
    check(r, { 'channels 200': (r) => r.status === 200 });
  });
}

export function browseInbox(auth) {
  group('inbox', () => {
    const r = http.get(`${BASE_URL}/api/inbox/emails`, auth);
    check(r, { 'inbox 200': (r) => r.status === 200 });
  });
}

export function userSession(auth) {
  publicFlow();
  sleep(Math.random() * 2 + 1);

  browseMonitors(auth);
  sleep(Math.random() * 2 + 1);

  browseRss(auth);
  sleep(Math.random() * 2 + 1);

  // 50% of users check chat
  if (Math.random() > 0.5) {
    browseChat(auth);
    sleep(Math.random() + 1);
  }

  // 30% check inbox
  if (Math.random() > 0.7) {
    browseInbox(auth);
  }
}
