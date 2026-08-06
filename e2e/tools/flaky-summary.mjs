// Surfaces the tests that only passed on a retry.
//
// A retry turns a flake into a green run, which is the point and also
// the problem: the suite reports success and the test that needed two
// goes leaves no trace anybody reads. This walks Playwright's JSON
// report after the run and says so out loud - a warning annotation on
// the test's own line, and a table in the job summary - so a test that
// starts needing retries is visible before it starts failing outright.
//
// Never fails the job: the run's own exit code already decided that.
// Writes `flaky` and `count` to $GITHUB_OUTPUT for the steps that
// decide whether to keep the artifacts.

import { appendFileSync, readFileSync, existsSync } from 'node:fs';
import { relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// A `::warning file=` annotation is resolved against the repository
// root, so the path has to be repo-relative whatever directory this was
// launched from - `node e2e/tools/flaky-summary.mjs` and
// `cd e2e && node tools/flaky-summary.mjs` must produce the same
// annotation. Derived from this file's own location (e2e/tools/) rather
// than from cwd, which is the thing that varies.
const repoRoot = fileURLToPath(new URL('../..', import.meta.url));

const reportPath = process.argv[2] ?? 'test-results/report.json';
// What to call this pass in the job summary. The soak walks the project
// graph one project at a time and so writes several sections; without a
// label they would all be headed "e2e" and read as one.
const label = process.argv[3] ?? 'e2e';

if (!existsSync(reportPath)) {
  // A run that died before the reporter wrote anything - the failure is
  // already reported by whatever killed it.
  console.log(`no JSON report at ${reportPath}; nothing to summarize`);
  emit(0);
  process.exit(0);
}

// Parsed defensively for the same reason the writes are guarded: a run
// that was killed leaves a half-written report, `existsSync` is happy
// with it, and a SyntaxError here would take the job red for a reason
// that has nothing to do with the tests. In the soak the loop runs under
// `set -e`, so the first corrupt report would abort the whole step.
let report;
try {
  report = JSON.parse(readFileSync(reportPath, 'utf8'));
} catch (e) {
  console.log(`could not read the JSON report at ${reportPath}: ${e}`);
  emit(0);
  process.exit(0);
}
const rootDir = report.config?.rootDir ?? process.cwd();

// Specs live on the file suite and on every `describe` nested under it.
const flaky = [];
const failed = [];
const walk = (suite) => {
  for (const spec of suite.specs ?? []) {
    for (const test of spec.tests ?? []) {
      const bucket =
        test.status === 'flaky' ? flaky : test.status === 'unexpected' ? failed : null;
      if (bucket === null) continue;
      bucket.push({
        file: relative(repoRoot, resolve(rootDir, spec.file)),
        line: spec.line,
        title: spec.title,
        project: test.projectName,
        attempts: (test.results ?? []).length,
      });
    }
  }
  for (const child of suite.suites ?? []) walk(child);
};
for (const suite of report.suites ?? []) walk(suite);

const stats = report.stats ?? {};
console.log(
  `${label}: ${stats.expected ?? 0} passed, ${stats.unexpected ?? 0} failed, ` +
    `${flaky.length} flaky, ${stats.skipped ?? 0} skipped`,
);

for (const t of flaky) {
  const where = `${t.file}:${t.line}`;
  console.log(
    `::warning file=${t.file},line=${t.line},title=Flaky test::` +
      `[${t.project}] ${t.title} passed on retry (${t.attempts} attempts) - ${where}`,
  );
}

const summaryPath = process.env.GITHUB_STEP_SUMMARY;
if (summaryPath) {
  const lines = [
    `## ${label}`,
    '',
    `${stats.expected ?? 0} passed | ${stats.unexpected ?? 0} failed | ` +
      `${flaky.length} flaky | ${stats.skipped ?? 0} skipped`,
    '',
  ];
  // Failures listed as well as flakes: with no retries the soak has no
  // flaky bucket at all, and which tests fell over is the whole answer
  // it exists to give.
  const table = (heading, rows) =>
    rows.length === 0
      ? []
      : [
          heading,
          '',
          '| Test | Project | Attempts | Location |',
          '| --- | --- | --- | --- |',
          ...rows.map(
            (t) => `| ${t.title} | ${t.project} | ${t.attempts} | \`${t.file}:${t.line}\` |`,
          ),
          '',
        ];
  lines.push(
    ...table('### Failed', failed),
    ...table('### Flaky (passed on retry)', flaky),
  );
  append(summaryPath, `${lines.join('\n')}\n`, 'the job summary');
}

emit(flaky.length);

function emit(count) {
  const out = process.env.GITHUB_OUTPUT;
  if (!out) return;
  append(out, `count=${count}\nflaky=${count > 0}\n`, "the step's outputs");
}

/// Report-writing never fails the job.
///
/// The line at the top of this file is a promise: the run's own exit
/// code already decided whether the suite passed, and a summary that
/// could not be written must not change that answer. Both destinations
/// are paths handed over in the environment - a runner sets them, and
/// anybody reproducing a CI failure locally may well export a stale one
/// - so an unwritable path says so on stdout and the script carries on.
function append(path, text, what) {
  try {
    appendFileSync(path, text);
  } catch (e) {
    console.log(`could not write ${what} to ${path}: ${e}`);
  }
}
