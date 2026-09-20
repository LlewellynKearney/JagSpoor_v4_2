"use strict";

// Regression guard for the deploy-time failure:
//
//   "User code failed to load. Cannot determine backend specification.
//    Timeout after 10000."
//
// The Firebase CLI discovers triggers by loading the functions entry point in a
// child process with a HARD 10s budget. Anything that makes that module graph
// expensive to evaluate at load time can exhaust the budget and fail the
// deploy — even though the code is perfectly valid.
//
// The original culprit was `import { google } from "googleapis"`: the
// aggregator root eagerly evaluates every Google API client (1400+ modules /
// ~30MB of JS). Pulling in the per-API package instead cuts the load to ~560
// modules / ~4MB.
//
// These assertions are deliberately structural (no timing-based flakiness) so
// they fail deterministically if the umbrella import is reintroduced.

const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const ROOT = path.resolve(__dirname, "..");
const ENTRY = path.join(ROOT, "lib", "index.js");
const ENTITLEMENT_SRC = path.join(ROOT, "src", "entitlement.ts");

/**
 * Strips line + block comments so source assertions inspect real code only.
 * The fix's own explanatory comment legitimately mentions the umbrella import.
 */
function stripComments(source) {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");
}

/**
 * Loads the compiled entry point in a clean child process and reports the
 * modules it pulled from node_modules plus the wall time.
 */
function measureEntryLoad() {
  const script = `
    const t0 = Date.now();
    require(${JSON.stringify(ENTRY)});
    const ms = Date.now() - t0;
    const modules = Object.keys(require.cache)
      .filter((f) => f.includes("node_modules"));
    process.stdout.write(JSON.stringify({ ms, count: modules.length, modules }));
  `;
  const out = execFileSync(process.execPath, ["-e", script], {
    cwd: ROOT,
    encoding: "utf8",
    env: { ...process.env, GCLOUD_PROJECT: "jagspoor-load-budget" },
    timeout: 30000,
  });
  return JSON.parse(out);
}

test("entry point does not load the googleapis umbrella package", () => {
  const { modules } = measureEntryLoad();
  const umbrella = modules.filter((f) =>
    /node_modules[\\/]googleapis[\\/]/.test(f)
  );
  assert.deepEqual(
    umbrella,
    [],
    `lib/index.js must not pull in the "googleapis" aggregator at load time; ` +
      `found ${umbrella.length} module(s): ${umbrella.slice(0, 3).join(", ")}`
  );
});

test("entry point loads a bounded module graph within the CLI discovery budget", () => {
  const { count, ms } = measureEntryLoad();

  // The umbrella import produced ~1400 modules; the per-API import ~560.
  // 900 leaves headroom for transitive changes while still catching a
  // reintroduced aggregator import.
  assert.ok(
    count < 900,
    `lib/index.js loaded ${count} node_modules — too heavy for trigger discovery`
  );

  // Real budget is 10s. Stay well under it so a slow CI runner cannot flake
  // into a false pass of a genuinely broken graph.
  assert.ok(
    ms < 8000,
    `lib/index.js took ${ms}ms to load — dangerously close to the 10s budget`
  );
});

test("entitlement source imports the per-API package, not the umbrella", () => {
  const src = stripComments(fs.readFileSync(ENTITLEMENT_SRC, "utf8"));

  // The exact umbrella form that caused the timeout.
  assert.ok(
    !/from\s+["']googleapis["']/.test(src),
    'src/entitlement.ts must not import from "googleapis" (the umbrella root)'
  );
  assert.ok(
    !/require\(\s*["']googleapis["']\s*\)/.test(src),
    'src/entitlement.ts must not require("googleapis")'
  );

  // The intended narrow import.
  assert.match(
    src,
    /from\s+["']@googleapis\/androidpublisher["']/,
    "src/entitlement.ts should import the per-API @googleapis/androidpublisher"
  );
});

test("package.json does not depend on the googleapis umbrella", () => {
  const pkg = require(path.join(ROOT, "package.json"));
  const deps = pkg.dependencies || {};
  assert.ok(
    !Object.prototype.hasOwnProperty.call(deps, "googleapis"),
    "the googleapis umbrella must not be a dependency"
  );
  assert.ok(
    Object.prototype.hasOwnProperty.call(deps, "@googleapis/androidpublisher"),
    "@googleapis/androidpublisher must be a declared dependency"
  );
});

test("GoogleAuth is constructed lazily inside the handler, not at module scope", () => {
  const src = stripComments(fs.readFileSync(ENTITLEMENT_SRC, "utf8"));

  // A module-scope instantiation would run during discovery.
  assert.ok(
    !/^const\s+\w+\s*=\s*new\s+GoogleAuth\(/m.test(src),
    "GoogleAuth must not be instantiated at module scope"
  );

  // It should live inside the lazily-invoked factory.
  assert.match(
    src,
    /function androidPublisher\(\)[\s\S]*?new GoogleAuth\(/,
    "GoogleAuth should be constructed inside the androidPublisher() factory"
  );
});

test("entry point still exports the full entitlement + trigger surface", () => {
  const index = require(ENTRY);
  for (const name of [
    "initializeNewUserTrial",
    "validateGooglePlayPurchase",
    "onGooglePlayRTDN",
    "payfastITN",
    "writeEntitlement",
    "getPlayPurchaseInfo",
  ]) {
    assert.ok(index[name], `${name} must still be exported`);
  }
});
