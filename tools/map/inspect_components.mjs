import fs from 'fs';

const js = fs.readFileSync('tools/map/inspect_target_web.mjs', 'utf8'); // wait, inspect from downloaded bundle
const bundle = await fetch('http://47.95.158.204:5173/assets/index-B3cCh_ig.js').then(r => r.text());

// Let's find definition of Gf, jy, by
function findFunction(name) {
  const patterns = [
    `function ${name}(`,
    `const ${name}=`,
    `var ${name}=`
  ];
  for (const p of patterns) {
    const idx = bundle.indexOf(p);
    if (idx !== -1) {
      console.log(`=== Found ${name} ===`);
      console.log(bundle.slice(idx, idx + 800));
      return;
    }
  }
  console.log(`=== Not found: ${name} ===`);
}

findFunction('Gf');
findFunction('jy');
findFunction('by');
