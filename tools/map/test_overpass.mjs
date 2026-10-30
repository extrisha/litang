async function run() {
  const query = `[out:json][timeout:25];
  (
    way["building"](31.287,121.545,31.300,121.564);
    way["highway"](31.287,121.545,31.300,121.564);
  );
  out tags;`;

  try {
    const res = await fetch('https://overpass-api.de/api/interpreter', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: 'data=' + encodeURIComponent(query)
    });
    const d = await res.json();
    console.log('Total elements in 516 bbox:', d.elements.length);
    const withNames = d.elements.filter(e => e.tags && (e.tags.name || e.tags['name:zh']));
    console.log('Elements with names:', withNames.length);
    console.log('Sample names:', withNames.slice(0, 15).map(e => e.tags.name || e.tags['name:zh']));
  } catch (err) {
    console.error('Fetch error:', err.message);
  }
}
run();
