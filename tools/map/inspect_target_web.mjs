import fs from 'fs';

async function run() {
  const url = 'http://47.95.158.204:5173/assets/index-B3cCh_ig.js';
  const res = await fetch(url);
  const js = await res.text();

  // Find occurrences of tileLayer or similar
  const tileMatches = [];
  let idx = 0;
  while ((idx = js.indexOf('tileLayer', idx + 1)) !== -1) {
    tileMatches.push(js.slice(Math.max(0, idx - 100), Math.min(js.length, idx + 200)));
  }
  console.log('--- tileLayer contexts (first 5) ---');
  tileMatches.slice(0, 5).forEach((m, i) => console.log(`[${i}]:\n${m}\n`));

  // Look for quotes containing {z} or {x} or /map
  const zxMatches = js.match(/['"][^'"]*?\{z\}[^'"]*?['"]/g) || [];
  console.log('--- {z} pattern URLs ---');
  console.log(zxMatches);

  // Look for any string containing /tiles or /map or .json
  const pathMatches = js.match(/['"][^'"]*?(?:tiles|geojson|campus|buildings)[^'"]*?['"]/gi) || [];
  console.log('--- path matches ---');
  console.log([...new Set(pathMatches)]);
}
run();
