async function run() {
  const base = 'http://47.95.158.204:5173/api/v1';

  console.log('Logging in to 校园寻物局...');
  const loginRes = await fetch(`${base}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: 'nig', password: '114514' }),
  });

  const loginData = await loginRes.json();
  console.log('Login response status:', loginRes.status);
  console.log('Login response data:', loginData);

  const token = loginData.token || loginData.access_token || loginData.data?.token || loginData.data?.access_token;
  const headers = {
    'Content-Type': 'application/json',
    ...(token ? { 'Authorization': `Bearer ${token}` } : {})
  };

  // Fetch /map/meta
  try {
    const metaRes = await fetch(`${base}/map/meta`, { headers });
    const meta = await metaRes.json();
    console.log('\n--- /map/meta ---');
    console.log(JSON.stringify(meta, null, 2));
  } catch (e) {
    console.error('meta error:', e.message);
  }

  // Fetch /layers
  try {
    const layersRes = await fetch(`${base}/layers`, { headers });
    const layers = await layersRes.json();
    console.log('\n--- /layers ---');
    console.log(JSON.stringify(layers, null, 2));
  } catch (e) {
    console.error('layers error:', e.message);
  }

  // Fetch /buildings
  try {
    const bldRes = await fetch(`${base}/buildings`, { headers });
    const blds = await bldRes.json();
    console.log('\n--- /buildings count ---');
    const list = Array.isArray(blds) ? blds : blds.data || blds.items || [];
    console.log('Buildings count:', list.length);
    console.log('Sample building:', JSON.stringify(list[0], null, 2));
  } catch (e) {
    console.error('buildings error:', e.message);
  }
}
run();
