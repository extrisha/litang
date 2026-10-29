// tools/map/fetch_campus_tiles.mjs
// 下载上理各校区（军工路516号、1100号、复兴路校区、营口路校区）离线地图瓦片

import fs from 'fs';
import path from 'path';

const OUT_DIR = path.resolve('assets/tiles');
if (!fs.existsSync(OUT_DIR)) {
  fs.mkdirSync(OUT_DIR, { recursive: true });
}

function lon2tile(lon, zoom) {
  return Math.floor(((lon + 180) / 360) * Math.pow(2, zoom));
}

function lat2tile(lat, zoom) {
  return Math.floor(
    ((1 -
      Math.log(
        Math.tan((lat * Math.PI) / 180) + 1 / Math.cos((lat * Math.PI) / 180)
      ) /
        Math.PI) /
      2) *
      Math.pow(2, zoom)
  );
}

// 各校区真实地理包围盒（WGS-84）
const CAMPUSES = [
  {
    name: '军工路516+1100号校区',
    minLat: 31.2800,
    maxLat: 31.2985,
    minLng: 121.5470,
    maxLng: 121.5620,
    zooms: [15, 16, 17, 18],
  },
  {
    name: '复兴路校区(SBC)',
    minLat: 31.2115,
    maxLat: 31.2165,
    minLng: 121.4555,
    maxLng: 121.4625,
    zooms: [15, 16, 17, 18],
  },
  {
    name: '营口路校区',
    minLat: 31.3055,
    maxLat: 31.3115,
    minLng: 121.5340,
    maxLng: 121.5405,
    zooms: [15, 16, 17, 18],
  },
];

const tileQueue = [];
const seen = new Set();

for (const c of CAMPUSES) {
  for (const z of c.zooms) {
    const x0 = lon2tile(c.minLng, z);
    const x1 = lon2tile(c.maxLng, z);
    const y0 = lat2tile(c.maxLat, z);
    const y1 = lat2tile(c.minLat, z);
    for (let x = x0; x <= x1; x++) {
      for (let y = y0; y <= y1; y++) {
        const key = `${z}_${x}_${y}`;
        if (!seen.has(key)) {
          seen.add(key);
          tileQueue.push({ z, x, y, key });
        }
      }
    }
  }
}

console.log(`准备下载校区离线瓦片，总计: ${tileQueue.length} 块`);

async function fetchTileWithRetry(t, maxRetries = 3) {
  const filePath = path.join(OUT_DIR, `${t.key}.png`);
  if (fs.existsSync(filePath) && fs.statSync(filePath).size > 1000) {
    return 'skipped';
  }

  const url = `https://tile.openstreetmap.de/${t.z}/${t.x}/${t.y}.png`;
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      const res = await fetch(url, {
        headers: {
          'User-Agent': 'USST-App-OfflineTiles/1.0 (https://github.com/project_usst)',
          'Accept': 'image/png,image/*;q=0.8',
        },
      });
      if (res.status === 200) {
        const buf = await res.arrayBuffer();
        if (buf.byteLength > 200) {
          fs.writeFileSync(filePath, Buffer.from(buf));
          return 'downloaded';
        }
      }
      if (res.status === 404) {
        return 'not_found';
      }
    } catch (err) {
      if (attempt === maxRetries) {
        throw err;
      }
      await new Promise((r) => setTimeout(r, 600 * attempt));
    }
  }
  return 'failed';
}

async function run() {
  const concurrency = 2;
  let downloaded = 0;
  let skipped = 0;
  let failed = 0;
  let index = 0;

  async function worker() {
    while (index < tileQueue.length) {
      const current = tileQueue[index++];
      try {
        const status = await fetchTileWithRetry(current);
        if (status === 'downloaded') downloaded++;
        else if (status === 'skipped') skipped++;
        else failed++;
      } catch (e) {
        failed++;
      }
      if ((downloaded + skipped + failed) % 20 === 0 || index === tileQueue.length) {
        process.stdout.write(
          `\r进度: ${downloaded + skipped + failed}/${tileQueue.length} (新下载: ${downloaded}, 已存在: ${skipped}, 失败: ${failed})`
        );
      }
      await new Promise((r) => setTimeout(r, 150)); // 礼貌限速
    }
  }

  const workers = Array.from({ length: concurrency }, () => worker());
  await Promise.all(workers);
  console.log(`\n完成! 总计: ${tileQueue.length}, 成功: ${downloaded + skipped}, 失败: ${failed}`);
}

run();
