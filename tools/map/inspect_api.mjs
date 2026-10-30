async function run() {
  const js = await fetch('http://47.95.158.204:5173/assets/index-B3cCh_ig.js').then(r => r.text());

  const calls = [];
  const re = /be\.(get|post|put|delete)\(([^)]+)\)/g;
  let m;
  while ((m = re.exec(js)) !== null) {
    calls.push(`${m[1].toUpperCase()} ${m[2].slice(0, 50)}`);
  }
  console.log('API calls found:');
  console.log(calls);
}
run();
