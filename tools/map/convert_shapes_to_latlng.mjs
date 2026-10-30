import fs from 'fs';

const shapesSrc = fs.readFileSync('lib/data/campus_shapes.dart', 'utf8');
const configSrc = fs.readFileSync('lib/data/geo/campus_config.dart', 'utf8');

const poiRegex = /name:\s*'([^']+)',\s*campusId:\s*'([^']+)',\s*location:\s*LatLng\(([\d.]+),\s*([\d.]+)\)/g;
const pois = {};
let match;
while ((match = poiRegex.exec(configSrc)) !== null) {
  pois[match[1]] = { campusId: match[2], lat: parseFloat(match[3]), lng: parseFloat(match[4]) };
}

const shapeRegex = /CampusShape\(\s*points:\s*<Offset>\[([\s\S]*?)\],\s*names:\s*<String>\[([\s\S]*?)\],\s*\)/g;
const shapes = [];
while ((match = shapeRegex.exec(shapesSrc)) !== null) {
  const ptsRaw = match[1];
  const namesRaw = match[2];
  const pts = [];
  const ptRegex = /Offset\(([\d.]+),\s*([\d.]+)\)/g;
  let pm;
  while ((pm = ptRegex.exec(ptsRaw)) !== null) {
    pts.push({ x: parseFloat(pm[1]), y: parseFloat(pm[2]) });
  }
  const names = namesRaw.split(',').map(s => s.trim().replace(/'/g, '')).filter(Boolean);
  shapes.push({ points: pts, names });
}

// Global affine transform parameters
const a1 = -0.007867050423101318;
const b1 = -0.0022885688440883456;
const c1 = 31.29626612402126;

const a2 = 0.013801371677175212;
const b2 = -0.003988435707579896;
const c2 = 121.54748052057998;

function toLatLng(p) {
  return {
    lat: a1 * p.x + b1 * p.y + c1,
    lng: a2 * p.x + b2 * p.y + c2
  };
}

console.log('Transforming', shapes.length, 'shapes to LatLng polygons...');
const converted = shapes.map((shape, idx) => {
  // calculate centroid of the raw shape
  let cx = 0, cy = 0;
  for (const pt of shape.points) {
    cx += pt.x;
    cy += pt.y;
  }
  cx /= shape.points.length;
  cy /= shape.points.length;

  const rawCenter = toLatLng({ x: cx, y: cy });

  // Check if any name matches a POI
  let matchedPoi = null;
  for (const n of shape.names) {
    if (pois[n]) {
      matchedPoi = pois[n];
      break;
    }
  }

  // If matched, adjust offset so centroid matches POI location exactly
  const dLat = matchedPoi ? matchedPoi.lat - rawCenter.lat : 0;
  const dLng = matchedPoi ? matchedPoi.lng - rawCenter.lng : 0;

  const latLngs = shape.points.map(pt => {
    const raw = toLatLng(pt);
    return {
      lat: +(raw.lat + dLat).toFixed(6),
      lng: +(raw.lng + dLng).toFixed(6)
    };
  });

  return {
    id: `bld_516_${idx + 1}`,
    name: shape.names[0] || `建筑_${idx + 1}`,
    aliases: shape.names.slice(1),
    names: shape.names,
    center: matchedPoi ? { lat: matchedPoi.lat, lng: matchedPoi.lng } : { lat: +rawCenter.lat.toFixed(6), lng: +rawCenter.lng.toFixed(6) },
    points: latLngs
  };
});

console.log('Sample converted:', JSON.stringify(converted[1], null, 2));
console.log('Total converted shapes:', converted.length);
