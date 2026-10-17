#!/usr/bin/env node
/**
 * Stages the Firebase Hosting payload.
 *
 * Firebase Hosting serves exactly one directory, but this repo has two
 * sources for the hosted site:
 *
 *   1. the Flutter web build            -> build/web   (generated)
 *   2. hand-authored static assets      -> public/     (tracked in git)
 *      - /.well-known/assetlinks.json        Android App Links
 *      - /.well-known/apple-app-site-association  iOS Universal Links
 *      - /r/index.html                       referral landing page
 *      - /privacy/, /delete-account/         store-listing URLs
 *
 * `hosting.public` points at `build/web`, so this script copies the tracked
 * `public/` assets into the freshly built Flutter output. Flutter never emits
 * these paths, so nothing is overwritten by the copy.
 *
 * Run automatically by the `hosting.predeploy` hook in firebase.json.
 * Requires `flutter build web --release` to have run first.
 */
'use strict';

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const webDir = path.join(root, 'build', 'web');
const publicDir = path.join(root, 'public');

const webIndex = path.join(webDir, 'index.html');
if (!fs.existsSync(webIndex)) {
  console.error(
    '[prepare_hosting] build/web/index.html was not found.\n' +
      '[prepare_hosting] Build the Flutter web app first:\n' +
      '[prepare_hosting]   flutter clean && flutter pub get && ' +
      'flutter build web --release',
  );
  process.exit(1);
}

if (!fs.existsSync(publicDir)) {
  console.error('[prepare_hosting] public/ directory is missing.');
  process.exit(1);
}

/** Recursively copies `src` into `dest`, creating directories as needed. */
function copyDir(src, dest) {
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    if (entry.name === '.DS_Store') continue;
    const from = path.join(src, entry.name);
    const to = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      fs.mkdirSync(to, { recursive: true });
      copyDir(from, to);
    } else {
      fs.copyFileSync(from, to);
    }
  }
}

copyDir(publicDir, webDir);

// Sanity check the assets the App Links / store-listing flows depend on.
const required = [
  '.well-known/assetlinks.json',
  '.well-known/apple-app-site-association',
  'r/index.html',
];
const missing = required.filter((rel) => !fs.existsSync(path.join(webDir, rel)));
if (missing.length > 0) {
  console.error(
    '[prepare_hosting] staged payload is missing: ' + missing.join(', '),
  );
  process.exit(1);
}

console.log(
  `[prepare_hosting] staged public/ assets into build/web ` +
    `(${required.length} association/landing files verified).`,
);
