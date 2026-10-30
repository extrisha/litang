import xml.etree.ElementTree as ET
import json

tree = ET.parse('tools/map/usst_516_raw.osm')
root = tree.getroot()

# 1. Collect all nodes
nodes = {}
for n in root.findall('node'):
    nid = n.get('id')
    lat = float(n.get('lat'))
    lon = float(n.get('lon'))
    tags = {t.get('k'): t.get('v') for t in n.findall('tag')}
    nodes[nid] = {'id': nid, 'lat': lat, 'lon': lon, 'tags': tags}

# 2. Collect ways
ways = []
for w in root.findall('way'):
    wid = w.get('id')
    tags = {t.get('k'): t.get('v') for t in w.findall('tag')}
    nds = [nd.get('ref') for nd in w.findall('nd')]
    ways.append({'id': wid, 'tags': tags, 'nodes': nds})

# Bounding box filter for USST 516 campus
# West: ~121.5470 (Jungong Rd), East: ~121.5585 (Huangpu River / Canal)
# South: ~31.2875 (Zhoujiazui Rd), North: ~31.2965 (Jungong Rd gate / canal)
MIN_LAT, MAX_LAT = 31.2870, 31.2970
MIN_LON, MAX_LON = 121.5470, 121.5590

def in_bbox(lat, lon):
    return MIN_LAT <= lat <= MAX_LAT and MIN_LON <= lon <= MAX_LON

def get_way_coords(nd_refs):
    coords = []
    for ref in nd_refs:
        if ref in nodes:
            coords.append([nodes[ref]['lon'], nodes[ref]['lat']])
    return coords

building_features = []
road_features = []
poi_features = []

# Process ways
for w in ways:
    tags = w['tags']
    nd_refs = w['nodes']
    coords = get_way_coords(nd_refs)
    if len(coords) < 2:
        continue

    # Center check
    avg_lat = sum(c[1] for c in coords) / len(coords)
    avg_lon = sum(c[0] for c in coords) / len(coords)
    if not in_bbox(avg_lat, avg_lon):
        continue

    name = tags.get('name:zh') or tags.get('name') or ''

    # Building
    if 'building' in tags:
        # Check if closed polygon
        if coords[0] != coords[-1]:
            coords.append(coords[0])
        feat = {
            'type': 'Feature',
            'id': f"way/{w['id']}",
            'properties': {
                'id': w['id'],
                'name': name,
                'building': tags.get('building'),
                'type': tags.get('building'),
                'levels': tags.get('building:levels') or tags.get('levels') or '4',
                'tags': tags
            },
            'geometry': {
                'type': 'Polygon',
                'coordinates': [coords]
            }
        }
        building_features.append(feat)

    # Road / Highway
    elif 'highway' in tags:
        feat = {
            'type': 'Feature',
            'id': f"way/{w['id']}",
            'properties': {
                'id': w['id'],
                'name': name,
                'highway': tags.get('highway'),
                'foot': tags.get('foot'),
                'bicycle': tags.get('bicycle'),
                'surface': tags.get('surface'),
                'tags': tags
            },
            'geometry': {
                'type': 'LineString',
                'coordinates': coords
            }
        }
        road_features.append(feat)

# Process nodes for POIs
for nid, n in nodes.items():
    if not in_bbox(n['lat'], n['lon']):
        continue
    tags = n['tags']
    if not tags:
        continue
    name = tags.get('name:zh') or tags.get('name') or ''
    # POI criteria
    is_poi = (
        'amenity' in tags or 'barrier' in tags or 'highway' in tags or
        'shop' in tags or 'entrance' in tags or 'public_transport' in tags or
        name != ''
    )
    if is_poi:
        feat = {
            'type': 'Feature',
            'id': f"node/{nid}",
            'properties': {
                'id': nid,
                'name': name,
                'amenity': tags.get('amenity'),
                'entrance': tags.get('entrance'),
                'barrier': tags.get('barrier'),
                'tags': tags
            },
            'geometry': {
                'type': 'Point',
                'coordinates': [n['lon'], n['lat']]
            }
        }
        poi_features.append(feat)

# Write geojson files
buildings_fc = {'type': 'FeatureCollection', 'features': building_features}
roads_fc = {'type': 'FeatureCollection', 'features': road_features}
pois_fc = {'type': 'FeatureCollection', 'features': poi_features}

with open('tools/map/usst_516_buildings.geojson', 'w', encoding='utf-8') as f:
    json.dump(buildings_fc, f, ensure_ascii=False, indent=2)

with open('tools/map/usst_516_roads.geojson', 'w', encoding='utf-8') as f:
    json.dump(roads_fc, f, ensure_ascii=False, indent=2)

with open('tools/map/usst_516_pois.geojson', 'w', encoding='utf-8') as f:
    json.dump(pois_fc, f, ensure_ascii=False, indent=2)

print(f"Extracted USST 516 Campus:")
print(f" - Buildings: {len(building_features)} (Named: {sum(1 for b in building_features if b['properties']['name'])})")
print(f" - Roads/Walkways: {len(road_features)}")
print(f" - POIs/Entrances: {len(poi_features)}")
