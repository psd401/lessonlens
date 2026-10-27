/**
 * LessonLens Vertex AI usage report (Google Apps Script).
 *
 * Reads aggregate Gemini request and token counts for the LessonLens project
 * from Cloud Monitoring and builds a short report for three windows: the last
 * 7 days, the last 30 days, and since July 1 (school year to date). Counts are
 * project-wide totals; no per-teacher or per-request data is read.
 *
 * Script Properties (Project Settings > Script Properties):
 *   GCP_PROJECT      - the Cloud project that runs the LessonLens backend
 *   BILLING_ACCOUNT  - its billing account ID, used only for the cost link
 *   REPORT_TO        - email address(es) for sendWeeklyReport, comma-separated
 *
 * Run previewReport() from the editor to log the report without sending it.
 * Run installWeeklyTrigger() once to email the report every Monday morning.
 */

var METRIC_PREFIX = 'aiplatform.googleapis.com/publisher/online_serving/';
var DAY_MS = 24 * 60 * 60 * 1000;

// Vertex AI calls began on 2026-09-28; earlier usage ran on the retired
// AI Studio key and is not in this project's metrics.
var VERTEX_START_NOTE = 'LessonLens moved to Vertex AI on 2026-09-28; earlier usage is not included.';

function previewReport() {
  var report = buildReport(getConfig_(), new Date());
  Logger.log(report.text);
}

/** Emails the report to REPORT_TO. The weekly trigger runs this. */
function sendWeeklyReport() {
  var config = getConfig_();
  if (!config.reportTo) throw new Error('Set the REPORT_TO script property.');
  var now = new Date();
  var report = buildReport(config, now);
  MailApp.sendEmail({
    to: config.reportTo,
    subject: reportSubject(now),
    body: report.text,
    htmlBody: report.html,
  });
}

/**
 * Schedules sendWeeklyReport for Mondays in the 7-8 AM hour (the script's
 * time zone). Replaces any earlier schedule, so running it twice is safe.
 */
function installWeeklyTrigger() {
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (t.getHandlerFunction() === 'sendWeeklyReport') ScriptApp.deleteTrigger(t);
  });
  ScriptApp.newTrigger('sendWeeklyReport').timeBased()
    .onWeekDay(ScriptApp.WeekDay.MONDAY).atHour(7).create();
}

function getConfig_() {
  var props = PropertiesService.getScriptProperties();
  var project = props.getProperty('GCP_PROJECT');
  if (!project) throw new Error('Set the GCP_PROJECT script property.');
  return {
    project: project,
    billingAccount: props.getProperty('BILLING_ACCOUNT') || '',
    reportTo: props.getProperty('REPORT_TO') || '',
  };
}

function reportSubject(now) {
  return 'LessonLens Vertex usage — week ending ' + formatDate(now);
}

/** Builds the report for all windows ending at `now`. Returns {text, html}. */
function buildReport(config, now, fetchFn) {
  var windows = reportWindows(now);
  var sections = windows.map(function (w) {
    var invocations = fetchSeries(config.project, 'model_invocation_count',
      ['resource.label.model_user_id', 'metric.label.response_code'], w.start, w.end, fetchFn);
    var tokens = fetchSeries(config.project, 'token_count',
      ['resource.label.model_user_id', 'metric.label.type'], w.start, w.end, fetchFn);
    return { window: w, models: summarize(invocations, tokens) };
  });
  var link = config.billingAccount ? billingReportUrl(config.billingAccount, config.project) : '';
  return { text: renderText(sections, link), html: renderHtml(sections, link) };
}

/** Last 7 days, last 30 days, and since July 1 of the current school year. */
function reportWindows(now) {
  var july1Year = now.getMonth() >= 6 ? now.getFullYear() : now.getFullYear() - 1;
  return [
    { label: 'Last 7 days', start: new Date(now.getTime() - 7 * DAY_MS), end: now },
    { label: 'Last 30 days', start: new Date(now.getTime() - 30 * DAY_MS), end: now },
    { label: 'Since July 1', start: new Date(july1Year, 6, 1), end: now },
  ];
}

/**
 * Sums one Vertex metric over [start, end], grouped by the given labels.
 * Returns the API's timeSeries list (all pages).
 */
function fetchSeries(project, metric, groupBy, start, end, fetchFn) {
  var fetch = fetchFn || fetchJson_;
  var seconds = Math.max(60, Math.ceil((end.getTime() - start.getTime()) / 1000));
  var params = [
    ['filter', 'metric.type="' + METRIC_PREFIX + metric + '"'],
    ['interval.startTime', start.toISOString()],
    ['interval.endTime', end.toISOString()],
    ['aggregation.alignmentPeriod', seconds + 's'],
    ['aggregation.perSeriesAligner', 'ALIGN_SUM'],
    ['aggregation.crossSeriesReducer', 'REDUCE_SUM'],
  ];
  groupBy.forEach(function (field) { params.push(['aggregation.groupByFields', field]); });

  var series = [];
  var pageToken = '';
  do {
    var query = params.concat(pageToken ? [['pageToken', pageToken]] : [])
      .map(function (p) { return encodeURIComponent(p[0]) + '=' + encodeURIComponent(p[1]); })
      .join('&');
    var body = fetch('https://monitoring.googleapis.com/v3/projects/' +
      encodeURIComponent(project) + '/timeSeries?' + query, project);
    series = series.concat(body.timeSeries || []);
    pageToken = body.nextPageToken || '';
  } while (pageToken);
  return series;
}

// X-Goog-User-Project bills the API call to the LessonLens project. Without
// it, the call counts against Apps Script's hidden default project, where the
// Monitoring API is off (HTTP 403).
function fetchJson_(url, quotaProject) {
  var response = UrlFetchApp.fetch(url, {
    headers: {
      Authorization: 'Bearer ' + ScriptApp.getOAuthToken(),
      'X-Goog-User-Project': quotaProject,
    },
    muteHttpExceptions: true,
  });
  var code = response.getResponseCode();
  if (code !== 200) {
    throw new Error('Cloud Monitoring returned HTTP ' + code + ': ' + response.getContentText().slice(0, 300));
  }
  return JSON.parse(response.getContentText());
}

/** Adds up a series' points (a window can span more than one aligned point). */
function sumPoints(series) {
  return (series.points || []).reduce(function (total, p) {
    return total + Number(p.value.int64Value || 0);
  }, 0);
}

/**
 * Combines invocation and token series into per-model totals:
 * {model: {requests, errors, errorsByCode: {code: n}, inputTokens, outputTokens}}
 * Any response code outside 2xx counts as an error.
 */
function summarize(invocationSeries, tokenSeries) {
  var models = {};
  function entry(model) {
    if (!models[model]) {
      models[model] = { requests: 0, errors: 0, errorsByCode: {}, inputTokens: 0, outputTokens: 0 };
    }
    return models[model];
  }
  invocationSeries.forEach(function (s) {
    var m = entry(s.resource.labels.model_user_id || 'unknown');
    var code = s.metric.labels.response_code || 'unknown';
    var n = sumPoints(s);
    m.requests += n;
    if (!/^2\d\d$/.test(code)) {
      m.errors += n;
      m.errorsByCode[code] = (m.errorsByCode[code] || 0) + n;
    }
  });
  tokenSeries.forEach(function (s) {
    var m = entry(s.resource.labels.model_user_id || 'unknown');
    var type = s.metric.labels.type;
    if (type === 'input') m.inputTokens += sumPoints(s);
    else if (type === 'output') m.outputTokens += sumPoints(s);
  });
  return models;
}

/** Cloud Billing cost report for one project, grouped by SKU. */
function billingReportUrl(billingAccount, project) {
  return 'https://console.cloud.google.com/billing/' + encodeURIComponent(billingAccount) +
    '/reports;grouping=GROUP_BY_SKU;projects=' + encodeURIComponent(project) +
    '?project=' + encodeURIComponent(project);
}

function formatErrors(m) {
  if (!m.errors) return '0';
  var codes = Object.keys(m.errorsByCode).sort().map(function (c) {
    return c + ': ' + m.errorsByCode[c];
  });
  var rate = (100 * m.errors / m.requests).toFixed(1);
  return m.errors + ' (' + rate + '%; ' + codes.join(', ') + ')';
}

// Local date (the script's time zone), not UTC.
function formatDate(d) {
  return d.getFullYear() + '-' + ('0' + (d.getMonth() + 1)).slice(-2) + '-' + ('0' + d.getDate()).slice(-2);
}

function formatNumber(n) {
  return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

function renderText(sections, billingLink) {
  var lines = ['LessonLens Vertex AI usage', VERTEX_START_NOTE, ''];
  sections.forEach(function (s) {
    lines.push(s.window.label + ' (' + formatDate(s.window.start) + ' to ' + formatDate(s.window.end) + ')');
    var names = Object.keys(s.models).sort();
    if (!names.length) lines.push('  No requests.');
    names.forEach(function (name) {
      var m = s.models[name];
      lines.push('  ' + name + ': ' + formatNumber(m.requests) + ' requests, errors ' + formatErrors(m) +
        ', tokens in ' + formatNumber(m.inputTokens) + ' / out ' + formatNumber(m.outputTokens));
    });
    lines.push('');
  });
  if (billingLink) lines.push('Cost by SKU (this project only): ' + billingLink);
  return lines.join('\n');
}

function escapeHtml(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function renderHtml(sections, billingLink) {
  var cell = 'style="padding:4px 10px;border-bottom:1px solid #ddd;text-align:right"';
  var head = 'style="padding:4px 10px;border-bottom:2px solid #999;text-align:right"';
  var html = ['<h2>LessonLens Vertex AI usage</h2>', '<p>' + escapeHtml(VERTEX_START_NOTE) + '</p>'];
  sections.forEach(function (s) {
    html.push('<h3>' + escapeHtml(s.window.label) + ' <small>(' + formatDate(s.window.start) +
      ' to ' + formatDate(s.window.end) + ')</small></h3>');
    var names = Object.keys(s.models).sort();
    if (!names.length) { html.push('<p>No requests.</p>'); return; }
    html.push('<table style="border-collapse:collapse"><tr>' +
      ['Model', 'Requests', 'Errors', 'Input tokens', 'Output tokens'].map(function (h) {
        return '<th ' + head + '>' + h + '</th>';
      }).join('') + '</tr>');
    names.forEach(function (name) {
      var m = s.models[name];
      html.push('<tr>' + [name, formatNumber(m.requests), formatErrors(m),
        formatNumber(m.inputTokens), formatNumber(m.outputTokens)].map(function (v) {
        return '<td ' + cell + '>' + escapeHtml(v) + '</td>';
      }).join('') + '</tr>');
    });
    html.push('</table>');
  });
  if (billingLink) {
    html.push('<p><a href="' + escapeHtml(billingLink) + '">Cost by SKU (this project only)</a></p>');
  }
  return html.join('\n');
}

// Lets bun tests load the pure functions; Apps Script has no `module`.
if (typeof module !== 'undefined') {
  module.exports = {
    sendWeeklyReport: sendWeeklyReport, installWeeklyTrigger: installWeeklyTrigger, reportSubject: reportSubject,
    buildReport: buildReport, reportWindows: reportWindows, fetchSeries: fetchSeries, fetchJson_: fetchJson_,
    sumPoints: sumPoints, summarize: summarize, billingReportUrl: billingReportUrl,
    formatErrors: formatErrors, formatDate: formatDate, formatNumber: formatNumber, renderText: renderText, renderHtml: renderHtml,
  };
}
