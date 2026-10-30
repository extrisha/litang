import fs from 'fs';

async function run() {
  const base = 'http://47.95.158.204:5173/api/v1';
  const loginRes = await fetch(`${base}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: 'nig', password: '114514' }),
  });
  const { token } = await loginRes.json();
  const headers = { 'Authorization': `Bearer ${token}` };

  const bldsRes = await fetch(`${base}/buildings`, { headers });
  const rawBlds = await bldsRes.json();
  const blds = Array.isArray(rawBlds) ? rawBlds : rawBlds.items || rawBlds.data || rawBlds.buildings || [];
  console.log('Buildings count:', blds.length);
  if (blds.length > 0) {
    console.log('Building names:', blds.map(b => b.name));
    fs.writeFileSync('tools/map/target_buildings.json', JSON.stringify(blds, null, 2), 'utf8');
  } else {
    console.log('rawBlds keys:', Object.keys(rawBlds));
  }

  const flatLayerId = '530b488c-2bd3-4c7a-9576-33928a1cbc52';
  const isoLayerId = '217d72fb-ac55-4e9d-94a4-0dd2d04b4d72';

  // Check points
  for (const lid of [flatLayerId, isoLayerId]) {
    const pRes = await fetch(`${base}/layers/${lid}/points`, { headers });
    const pData = await pRes.json();
    console.log(`Layer ${lid} points response:`, Array.isArray(pData) ? pData.length : Object.keys(pData));
    fs.writeFileSync(`tools/map/points_${lid}.json`, JSON.stringify(pData, null, 2), 'utf8');
  }

  // Check image size and download
  for (const [name, lid] of [['flat', flatLayerId], ['iso', isoLayerId]]) {
    const imgRes = await fetch(`${base}/layers/${lid}/image`, { headers });
    console.log(`Image ${name} status:`, imgRes.status, 'Type:', imgRes.headers.get('content-type'));
    const buf = await imgRes.arrayBuffer();
    console.log(`Image ${name} size:`, (buf.byteLength / 1024).toFixed(1), 'KB');
    fs.writeFileSync(`tools/map/layer_${name}.webp`, Buffer.from(buf));
  }
}
run();
