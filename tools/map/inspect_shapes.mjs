import fs from 'fs';

const placesSrc = fs.readFileSync('lib/data/campus_places.dart', 'utf8');
const shapesSrc = fs.readFileSync('lib/data/campus_shapes.dart', 'utf8');
const configSrc = fs.readFileSync('lib/data/geo/campus_config.dart', 'utf8');

// Parse shapes
const shapeRegex = /CampusShape\(\s*points:\s*<Offset>\[([\s\S]*?)\],\s*names:\s*<String>\[([\s\S]*?)\],\s*\)/g;
let match;
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

console.log('Parsed shapes count:', shapes.length);
console.log('Sample shape 0:', shapes[0].names, shapes[0].points.length, 'points');

// Let's find 一教
const yijiao = shapes.find(s => s.names.some(n => n.includes('第一教学楼')));
if (yijiao) {
  console.log('一教 points count:', yijiao.points.length);
  // calculate bounding box in x, y
  const xs = yijiao.points.map(p => p.x);
  const ys = yijiao.points.map(p => p.y);
  const minX = Math.min(...xs), maxX = Math.max(...xs);
  const minY = Math.min(...ys), maxY = Math.max(...ys);
  console.log('一教 bbox (normalized):', { dx: (maxX - minX).toFixed(4), dy: (maxY - minY).toFixed(4) });
  // in meters:
  console.log('一教 approx meters:', {
    widthM: ((maxX - minX) * 1230).toFixed(1) + 'm',
    heightM: ((maxY - minY) * 1500).toFixed(1) + 'm'
  });
}
