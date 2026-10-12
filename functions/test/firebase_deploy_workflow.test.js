"use strict";

// Regression guard for the CI failure:
//
//   Firebase Deploy / Deploy Functions & Firestore Rules  (ba74c1f)
//   Error: Failed to authenticate, have you run firebase login?
//
// Root cause: the workflow passed `--token "${{ secrets.FIREBASE_TOKEN }}"`,
// but that repo secret was never configured — so the command ran as
// `--token ""` and firebase-tools aborted immediately. The workflow had no
// guard for a missing credential.
//
// These assertions are structural (source-parsing, no network / no Firebase
// credentials) so they fail deterministically if the regression returns.

const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..", "..");
const WORKFLOW = path.join(ROOT, ".github", "workflows", "firebase-deploy.yml");
const FIREBASE_JSON = path.join(ROOT, "firebase.json");
const FIREBASERC = path.join(ROOT, ".firebaserc");

function read(p) {
  return fs.readFileSync(p, "utf8");
}

// Comments legitimately mention the old `--token ""` bug, so assertions about
// the executable YAML must inspect real lines only.
function stripYamlComments(source) {
  return source
    .split("\n")
    .filter((line) => !/^\s*#/.test(line))
    .join("\n");
}

test("firebase deploy workflow exists and triggers on main", () => {
  const raw = read(WORKFLOW);
  assert.match(raw, /name:\s*Firebase Deploy/);
  assert.match(raw, /branches:\s*\[main\]/);
});

test("workflow never passes an empty --token (the ba74c1f root cause)", () => {
  const yml = stripYamlComments(read(WORKFLOW));
  // The exact bug shape: `--token "${{ secrets.FIREBASE_TOKEN }}"` executed
  // unconditionally. It must only ever appear inside a token-mode branch.
  const lines = yml.split("\n").filter((l) => l.includes("--token"));
  for (const line of lines) {
    assert.doesNotMatch(
      line.trim(),
      /^--token\s+"\$\{\{\s*secrets\.FIREBASE_TOKEN\s*\}\}"$/,
      "an unconditional `--token <secret>` line reproduces the ba74c1f failure"
    );
  }
});

test("the deploy job never runs on pull_request", () => {
  const yml = stripYamlComments(read(WORKFLOW));
  // A PR must exercise the verify job only; it must never deploy.
  assert.match(yml, /if:\s*github\.event_name != 'pull_request'/);
});

test("workflow probes FIREBASE_SERVICE_ACCOUNT and FIREBASE_TOKEN, fails open", () => {
  const yml = stripYamlComments(read(WORKFLOW));
  assert.match(yml, /secrets\.FIREBASE_SERVICE_ACCOUNT/);
  assert.match(yml, /secrets\.FIREBASE_TOKEN/);
  // The probe must write a `deploy` output so later steps can gate on it.
  assert.match(yml, /echo "deploy=true"/);
  assert.match(yml, /echo "deploy=false"/);
  // A missing credential warns (does not fail).
  assert.match(yml, /::warning::/);
});

test("every credential-dependent step is gated on the probe output", () => {
  const yml = stripYamlComments(read(WORKFLOW));
  const deployStep = yml.slice(yml.indexOf("Deploy to Firebase"));
  assert.match(
    deployStep,
    /if:\s*steps\.creds\.outputs\.deploy == 'true'/,
    "the deploy step must be skipped when no credential is configured"
  );
});

test("default deploy target set excludes functions (no EMAIL_PASS needed in CI)", () => {
  const yml = stripYamlComments(read(WORKFLOW));
  assert.match(yml, /value=hosting,firestore:rules,storage/);
  // Functions are opt-in via the workflow_dispatch input, never the default.
  assert.match(yml, /deploy_functions/);
  assert.match(yml, /hosting,firestore:rules,storage,functions/);
});

test("deploy pins the project id and runs non-interactively", () => {
  const yml = stripYamlComments(read(WORKFLOW));
  assert.match(yml, /--project "\$FIREBASE_PROJECT_ID"/);
  assert.match(yml, /--non-interactive/);
});

test(".firebaserc targets the jagspoor project", () => {
  const rc = JSON.parse(read(FIREBASERC));
  assert.equal(rc.projects.default, "jagspoor");
});

test("firebase.json predeploy installs from the lockfile then builds via $RESOURCE_DIR", () => {
  const cfg = JSON.parse(read(FIREBASE_JSON));
  const pre = cfg.functions.predeploy || [];
  assert.ok(
    pre.some((cmd) => /npm\b.*--prefix\s+"?\$RESOURCE_DIR"?\s+ci/.test(cmd)),
    "predeploy must run `npm --prefix \"$RESOURCE_DIR\" ci` (lockfile-exact)"
  );
  assert.ok(
    pre.some((cmd) => /npm\b.*--prefix\s+"?\$RESOURCE_DIR"?\s+run build/.test(cmd)),
    "predeploy must run `npm --prefix \"$RESOURCE_DIR\" run build`"
  );
});
