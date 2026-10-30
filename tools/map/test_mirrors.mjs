async function test() {
  const mirrors = [
    'https://overpass.kumi.systems/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
    'https://overpass.private.coffee/api/interpreter'
  ];
  const q = `[out:json][timeout:15];
  (
    way["building"](31.288,121.548,31.295,121.558);
  );
  out geom 10;`;
  for (const m of mirrors) {
    try {
      console.log('Testing', m);
      const res = await fetch(m, {
        method: 'POST',
        headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' },
        body: 'data=' + encodeURIComponent(q)
      });
      const data = await res.json();
      console.log('SUCCESS from', m, 'count:', data.elements.length);
      console.log('Sample element:', JSON.stringify(data.elements[0], null, 2));
      return;
    } catch (e) {
      console.log('Failed', m, e.message);
    }
  }
}
test();
