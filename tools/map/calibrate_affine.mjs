import fs from 'fs';

const placesSrc = fs.readFileSync('lib/data/campus_places.dart', 'utf8');
const configSrc = fs.readFileSync('lib/data/geo/campus_config.dart', 'utf8');

const placeRegex = /CampusPlace\(name:\s*'([^']+)',\s*anchor:\s*Offset\(([\d.]+),\s*([\d.]+)\)\)/g;
const places = {};
let match;
while ((match = placeRegex.exec(placesSrc)) !== null) {
  places[match[1]] = { x: parseFloat(match[2]), y: parseFloat(match[3]) };
}

const poiRegex = /name:\s*'([^']+)',\s*campusId:\s*'([^']+)',\s*location:\s*LatLng\(([\d.]+),\s*([\d.]+)\)/g;
const pois = {};
while ((match = poiRegex.exec(configSrc)) !== null) {
  pois[match[1]] = { campusId: match[2], lat: parseFloat(match[3]), lng: parseFloat(match[4]) };
}

const pts = [];
for (const [name, poi] of Object.entries(pois)) {
  if (poi.campusId !== 'jungong516') continue;
  if (places[name]) {
    pts.push({ name, x: places[name].x, y: places[name].y, lat: poi.lat, lng: poi.lng });
  }
}

// Fit 2D Affine transform using Least Squares:
// [lat] = [x y 1] * [a1, b1, c1]^T
// [lng] = [x y 1] * [a2, b2, c2]^T

function solve3x3(A, B) {
  // Solve (A^T * A) * X = A^T * B
  const ATA = [
    [0, 0, 0],
    [0, 0, 0],
    [0, 0, 0]
  ];
  const ATB = [0, 0, 0];

  for (let i = 0; i < A.length; i++) {
    const r = A[i];
    const b = B[i];
    for (let j = 0; j < 3; j++) {
      ATB[j] += r[j] * b;
      for (let k = 0; k < 3; k++) {
        ATA[j][k] += r[j] * r[k];
      }
    }
  }

  // Gaussian elimination
  const M = ATA.map((row, i) => [...row, ATB[i]]);
  for (let i = 0; i < 3; i++) {
    let maxRow = i;
    for (let k = i + 1; k < 3; k++) {
      if (Math.abs(M[k][i]) > Math.abs(M[maxRow][i])) maxRow = k;
    }
    const tmp = M[i]; M[i] = M[maxRow]; M[maxRow] = tmp;

    const pivot = M[i][i];
    for (let j = i; j <= 3; j++) M[i][j] /= pivot;

    for (let k = 0; k < 3; k++) {
      if (k !== i) {
        const factor = M[k][i];
        for (let j = i; j <= 3; j++) {
          M[k][j] -= factor * M[i][j];
        }
      }
    }
  }

  return [M[0][3], M[1][3], M[2][3]];
}

const A = pts.map(p => [p.x, p.y, 1]);
const B_lat = pts.map(p => p.lat);
const B_lng = pts.map(p => p.lng);

const [a1, b1, c1] = solve3x3(A, B_lat);
const [a2, b2, c2] = solve3x3(A, B_lng);

console.log('Affine Transformation Parameters:');
console.log(`lat = ${a1} * x + ${b1} * y + ${c1}`);
console.log(`lng = ${a2} * x + ${b2} * y + ${c2}`);

// Check residual errors
let maxDistMeters = 0;
let avgDistMeters = 0;

for (const p of pts) {
  const predLat = a1 * p.x + b1 * p.y + c1;
  const predLng = a2 * p.x + b2 * p.y + c2;

  // Approx distance in meters: 1 deg lat ~ 111,000m, 1 deg lng ~ 111,000 * cos(31.29 deg) ~ 95,000m
  const dLatM = (predLat - p.lat) * 111000;
  const dLngM = (predLng - p.lng) * 95000;
  const distM = Math.sqrt(dLatM * dLatM + dLngM * dLngM);

  avgDistMeters += distM;
  if (distM > maxDistMeters) maxDistMeters = distM;
}

avgDistMeters /= pts.length;
console.log(`Average error: ${avgDistMeters.toFixed(2)} meters`);
console.log(`Max error: ${maxDistMeters.toFixed(2)} meters`);
