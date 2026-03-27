import { textSummary } from 'https://jslib.k6.io/k6-summary/0.1.0/index.js';

const BASELINES_DIR = __ENV.K6_BASELINES_DIR || 'tests/k6/baselines';
const RESULTS_DIR = __ENV.K6_RESULTS_DIR || '/tmp/k6-results';
const REGRESSION_THRESHOLD = 0.2; // 20% regression triggers warning

function extractMetrics(data) {
  const d = data.metrics;
  return {
    timestamp: new Date().toISOString(),
    http_req_duration_p95: d.http_req_duration?.values?.['p(95)'] || 0,
    http_req_duration_p99: d.http_req_duration?.values?.['p(99)'] || 0,
    http_req_duration_avg: d.http_req_duration?.values?.avg || 0,
    http_req_failed_rate: d.http_req_failed?.values?.rate || 0,
    http_reqs_count: d.http_reqs?.values?.count || 0,
    http_reqs_rate: d.http_reqs?.values?.rate || 0,
    checks_rate: d.checks?.values?.rate || 0,
    iterations: d.iterations?.values?.count || 0,
    vus_max: d.vus_max?.values?.max || 0,
  };
}

function compareWithBaseline(current, baselinePath) {
  let baseline;
  try {
    baseline = JSON.parse(open(baselinePath));
  } catch {
    return '  No baseline found — save one with K6_SAVE_BASELINE=true\n';
  }

  const comparisons = [
    ['p95 (ms)', 'http_req_duration_p95', 'lower'],
    ['p99 (ms)', 'http_req_duration_p99', 'lower'],
    ['avg (ms)', 'http_req_duration_avg', 'lower'],
    ['error rate', 'http_req_failed_rate', 'lower'],
    ['throughput (rps)', 'http_reqs_rate', 'higher'],
    ['checks pass', 'checks_rate', 'higher'],
  ];

  let output = '';
  let regressions = 0;

  for (const [label, key, direction] of comparisons) {
    const curr = current[key];
    const base = baseline[key];
    if (!base || base === 0) continue;

    const diff = (curr - base) / base;
    const isRegression = direction === 'lower' ? diff > REGRESSION_THRESHOLD : diff < -REGRESSION_THRESHOLD;
    const arrow = diff > 0 ? '↑' : diff < 0 ? '↓' : '→';
    const pct = (diff * 100).toFixed(1);
    const flag = isRegression ? ' ⚠ REGRESSION' : '';

    if (isRegression) regressions++;
    output += `  ${label.padEnd(20)} ${curr.toFixed(2).padStart(10)} (baseline: ${base.toFixed(2)}, ${arrow} ${pct}%)${flag}\n`;
  }

  if (regressions > 0) {
    output = `  ⚠ ${regressions} regression(s) detected (>${REGRESSION_THRESHOLD * 100}% change)\n\n` + output;
  } else {
    output = '  ✓ No regressions\n\n' + output;
  }

  return output;
}

export function handleSummary(data) {
  const testName = __ENV.K6_TEST_NAME || 'load-test';
  const current = extractMetrics(data);
  const baselinePath = `${BASELINES_DIR}/${testName}.json`;
  const resultPath = `${RESULTS_DIR}/${testName}-${Date.now()}.json`;

  const comparison = compareWithBaseline(current, baselinePath);

  const outputs = {
    stdout: textSummary(data, { indent: ' ', enableColors: true })
      + '\n\n── Baseline Comparison ──\n' + comparison,
    [resultPath]: JSON.stringify(current, null, 2),
  };

  if (__ENV.K6_SAVE_BASELINE === 'true') {
    outputs[baselinePath] = JSON.stringify(current, null, 2);
    outputs.stdout += `\n  Baseline saved to ${baselinePath}\n`;
  }

  return outputs;
}
