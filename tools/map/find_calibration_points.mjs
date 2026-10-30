import fs from 'fs';

const placesSrc = fs.readFileSync('lib/data/campus_places.dart', 'utf8');
const configSrc = fs.readFileSync('lib/data/geo/campus_config.dart', 'utf8');

// Parse kCampusPlaces: CampusPlace(name: '...', anchor: Offset(x, y))
const placeRegex = /CampusPlace\(name:\s*'([^']+)',\s*anchor:\s*Offset\(([\d.]+),\s*([\d.]+)\)\)/g;
const places = {};
let match;
while ((match = placeRegex.exec(placesSrc)) !== null) {
  places[match[1]] = { x: parseFloat(match[2]), y: parseFloat(match[3]) };
}

// Parse CampusPoi: name: '...', campusId: 'jungong516', location: LatLng(lat, lng)
const poiRegex = /name:\s*'([^']+)',\s*campusId:\s*'([^']+)',\s*location:\s*LatLng\(([\d.]+),\s*([\d.]+)\)/g;
const pois = {};
while ((match = poiRegex.exec(configSrc)) !== null) {
  pois[match[1]] = { campusId: match[2], lat: parseFloat(match[3]), lng: parseFloat(match[4]) };
}

console.log('Places count:', Object.keys(places).length);
console.log('POIs count:', Object.keys(pois).length);

const matched = [];
for (const [name, poi] of Object.entries(pois)) {
  if (poi.campusId !== 'jungong516') continue;
  if (places[name]) {
    matched.push({ name, x: places[name].x, y: places[name].y, lat: poi.lat, lng: poi.lng });
  } else {
    // Try substring matching
    for (const [pname, pcoord] of Object.entries(places)) {
      if (pname.includes(name) || name.includes(pname)) {
        matched.push({ name: `${name} ~ ${pname}`, x: pcoord.x, y: pcoord.y, lat: poi.lat, lng: poi.lng });
        break;
      }
    }
  }
}

console.log('Matched points count in 516:', matched.length);
console.table(matched);
