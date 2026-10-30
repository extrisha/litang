const bundle = await fetch('http://47.95.158.204:5173/assets/index-B3cCh_ig.js').then(r => r.text());

let idx = bundle.indexOf('function by(');
console.log(bundle.slice(idx, idx + 1500));
