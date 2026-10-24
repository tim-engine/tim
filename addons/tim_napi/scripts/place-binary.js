'use strict';
// Places the freshly built addon binary into the per-arch package slot:
//   addons/tim_napi/bin/<platform>-<arch>/tim.node
//
// Run from the repository root after `denim build` (see the `build`
// npm script). Native addons cannot be cross-compiled, so this runs on
// each target host (or CI runner) and the resulting files are packed
// together for publishing.

const fs = require('fs');
const os = require('os');
const path = require('path');

const PLATFORMS = {
  darwin: ['arm64', 'x64'],
  linux: ['arm64', 'x64'],
};

const repoRoot = path.resolve(__dirname, '..', '..', '..');
const src = path.join(repoRoot, 'bin', 'tim.node');

const plat = PLATFORMS[os.platform()] ? os.platform() : null;
if (plat === null || !PLATFORMS[plat].includes(os.arch())) {
  console.error(
    `tim-napi: unsupported host ${os.platform()}-${os.arch()}. ` +
      'Supported: ' +
      Object.entries(PLATFORMS)
        .map(([p, archs]) => archs.map((a) => `${p}-${a}`).join(', '))
        .join(', ')
  );
  process.exit(1);
}

if (!fs.existsSync(src)) {
  console.error(`tim-napi: ${src} not found. Run denim build first.`);
  process.exit(1);
}

const destDir = path.join(__dirname, '..', 'bin', `${plat}-${os.arch()}`);
fs.mkdirSync(destDir, { recursive: true });
fs.copyFileSync(src, path.join(destDir, 'tim.node'));
console.log(`tim-napi: placed binary for ${plat}-${os.arch()}`);
