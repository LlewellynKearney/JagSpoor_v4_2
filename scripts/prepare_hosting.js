// scripts/prepare_hosting.js - FIXED: never overwrites Flutter index.html
const fs = require('fs');
const path = require('path');
const publicDir = path.join(__dirname, '..', 'public');
const buildDir = path.join(__dirname, '..', 'build', 'web');
function copyRecursive(src, dest) {
  if (!fs.existsSync(src)) return;
  const stat = fs.statSync(src);
  if (stat.isDirectory()) {
    if (!fs.existsSync(dest)) fs.mkdirSync(dest, { recursive: true });
    for (const file of fs.readdirSync(src)) {
      copyRecursive(path.join(src, file), path.join(dest, file));
    }
  } else {
    if (dest === path.join(buildDir, 'index.html')) {
      console.log('[prepare_hosting] SKIPPING overwrite of Flutter index.html');
      return;
    }
    if (!fs.existsSync(path.dirname(dest))) fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.copyFileSync(src, dest);
  }
}
if (!fs.existsSync(buildDir)) {
  console.log('[prepare_hosting] build/web does not exist yet, skipping');
  process.exit(0);
}
const allowed = ['.well-known', 'r', 'privacy', 'delete-account', '404.html'];
let staged = 0;
for (const item of allowed) {
  const src = path.join(publicDir, item);
  const dest = path.join(buildDir, item);
  if (fs.existsSync(src)) {
    copyRecursive(src, dest);
    staged++;
    console.log(`[prepare_hosting] staged ${item} -> build/web/${item}`);
  }
}
console.log(`[prepare_hosting] done - staged ${staged} auxiliary assets, Flutter index.html preserved.`);
