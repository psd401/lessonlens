// Tests for the pure functions in Code.gs. Run: bun test scripts/vertex-usage-report
import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import vm from 'node:vm';

// Code.gs is plain Apps Script JavaScript, so load it in a sandbox with a
// `module` object instead of importing it.
const sandbox: { module: { exports: any } } = { module: { exports: {} } };
vm.runInNewContext(readFileSync(join(import.meta.dir, 'Code.gs'), 'utf8'), sandbox);
const report = sandbox.module.exports;

function series(model: string, labels: Record<string, string>, ...values: number[]) {
  return {
    resource: { labels: { model_user_id: model } },
    metric: { labels },
    points: values.map((v) => ({ value: { int64Value: String(v) } })),
  };
}

describe('reportWindows', () => {
  test('since July 1 uses this year after July', () => {
    const now = new Date(2026, 9, 26, 9, 0);
    const [week, month, year] = report.reportWindows(now);
    expect(week.label).toBe('Last 7 days');
    expect(now.getTime() - week.start.getTime()).toBe(7 * 86400000);
    expect(now.getTime() - month.start.getTime()).toBe(30 * 86400000);
    expect(year.start).toEqual(new Date(2026, 6, 1));
  });

  test('since July 1 uses last year before July', () => {
    const [, , year] = report.reportWindows(new Date(2027, 2, 15));
    expect(year.start).toEqual(new Date(2026, 6, 1));
  });
});

describe('summarize', () => {
  test('counts non-2xx codes as errors and sums all points', () => {
    const models = report.summarize(
      [
        series('gemini-a', { response_code: '200' }, 5, 3),
        series('gemini-a', { response_code: '429' }, 2),
        series('gemini-a', { response_code: '500' }, 1),
      ],
      [
        series('gemini-a', { type: 'input' }, 1000, 500),
        series('gemini-a', { type: 'output' }, 200),
      ],
    );
    expect(models['gemini-a']).toEqual({
      requests: 11,
      errors: 3,
      errorsByCode: { '429': 2, '500': 1 },
      inputTokens: 1500,
      outputTokens: 200,
    });
  });

  test('keeps models apart and ignores other token types', () => {
    const models = report.summarize(
      [series('gemini-a', { response_code: '200' }, 1), series('gemini-b', { response_code: '200' }, 4)],
      [series('gemini-b', { type: 'thinking' }, 99)],
    );
    expect(models['gemini-a'].requests).toBe(1);
    expect(models['gemini-b'].requests).toBe(4);
    expect(models['gemini-b'].inputTokens).toBe(0);
    expect(models['gemini-b'].outputTokens).toBe(0);
  });

  test('no series gives no models', () => {
    expect(report.summarize([], [])).toEqual({});
  });
});

describe('formatErrors', () => {
  test('shows count, rate and codes', () => {
    expect(report.formatErrors({ requests: 8, errors: 2, errorsByCode: { '500': 1, '429': 1 } }))
      .toBe('2 (25.0%; 429: 1, 500: 1)');
  });

  test('zero errors is just 0', () => {
    expect(report.formatErrors({ requests: 8, errors: 0, errorsByCode: {} })).toBe('0');
  });
});

describe('formatting', () => {
  test('numbers get thousands separators', () => {
    // 8 digits: the security scan flags 7-digit numbers as possible student IDs.
    expect(report.formatNumber(12345678)).toBe('12,345,678');
    expect(report.formatNumber(999)).toBe('999');
  });

  test('dates use the local day, not UTC', () => {
    expect(report.formatDate(new Date(2026, 9, 26, 23, 30))).toBe('2026-10-26');
  });
});

describe('fetchSeries', () => {
  test('sends the aggregation query and follows pages', () => {
    const urls: string[] = [];
    const pages = [
      { timeSeries: [series('a', { response_code: '200' }, 1)], nextPageToken: 'p2' },
      { timeSeries: [series('b', { response_code: '200' }, 2)] },
    ];
    const result = report.fetchSeries(
      'my-project', 'model_invocation_count', ['resource.label.model_user_id', 'metric.label.response_code'],
      new Date('2026-10-19T00:00:00Z'), new Date('2026-10-26T00:00:00Z'),
      (url: string) => { urls.push(url); return pages[urls.length - 1]; },
    );
    expect(result).toHaveLength(2);
    const first = new URL(urls[0]);
    expect(first.pathname).toBe('/v3/projects/my-project/timeSeries');
    expect(first.searchParams.get('filter'))
      .toBe('metric.type="aiplatform.googleapis.com/publisher/online_serving/model_invocation_count"');
    expect(first.searchParams.get('aggregation.alignmentPeriod')).toBe('604800s');
    expect(first.searchParams.getAll('aggregation.groupByFields'))
      .toEqual(['resource.label.model_user_id', 'metric.label.response_code']);
    expect(first.searchParams.has('pageToken')).toBe(false);
    expect(new URL(urls[1]).searchParams.get('pageToken')).toBe('p2');
  });
});

describe('buildReport', () => {
  const now = new Date(2026, 9, 26, 9, 0);

  test('reports each window and the billing link', () => {
    const fake = (url: string) => (url.includes('model_invocation_count')
      ? { timeSeries: [series('gemini-a', { response_code: '200' }, 8)] }
      : { timeSeries: [series('gemini-a', { type: 'input' }, 100)] });
    const out = report.buildReport({ project: 'p1', billingAccount: 'AAA-BBB' }, now, fake);
    expect(out.text).toContain('Last 7 days');
    expect(out.text).toContain('Last 30 days');
    expect(out.text).toContain('Since July 1');
    expect(out.text).toContain('gemini-a: 8 requests, errors 0, tokens in 100 / out 0');
    expect(out.text).toContain('https://console.cloud.google.com/billing/AAA-BBB/reports;grouping=GROUP_BY_SKU;projects=p1?project=p1');
    expect(out.html).toContain('<td');
  });

  test('a window with no traffic says so and skips the link without an account', () => {
    const out = report.buildReport({ project: 'p1', billingAccount: '' }, now, () => ({}));
    expect(out.text).toContain('No requests.');
    expect(out.text).not.toContain('console.cloud.google.com');
    expect(out.html).toContain('<p>No requests.</p>');
  });

  test('escapes model names in HTML', () => {
    const fake = () => ({ timeSeries: [series('<b>x</b>', { response_code: '200' }, 1)] });
    const out = report.buildReport({ project: 'p1', billingAccount: '' }, now, fake);
    expect(out.html).toContain('&lt;b&gt;x&lt;/b&gt;');
    expect(out.html).not.toContain('<b>x</b>');
  });
});
