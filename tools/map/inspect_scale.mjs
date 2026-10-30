const bundle = await fetch('http://47.95.158.204:5173/assets/index-B3cCh_ig.js').then(r => r.text());

let idx = 0;
while ((idx = bundle.indexOf('scale_calibrated', idx + 1)) !== -1) {
  console.log('=== scale_calibrated context ===');
  console.log(bundle.slice(Math.max(0, idx - 100), idx + 200));
}
