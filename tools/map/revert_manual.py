import json

# 1. Buildings
with open('tools/map/usst_516_buildings.geojson', 'r', encoding='utf-8') as f:
    bld_data = json.load(f)

initial_count = len(bld_data['features'])
removed_blds = []
clean_blds = []

for feat in bld_data['features']:
    fid = str(feat.get('id', ''))
    pid = str(feat.get('properties', {}).get('id', ''))
    name = feat.get('properties', {}).get('name', '')
    if fid.startswith('manual/') or pid.startswith('manual_'):
        removed_blds.append(f"[{feat['properties'].get('code')}] {name}")
    else:
        clean_blds.append(feat)

bld_data['features'] = clean_blds

with open('tools/map/usst_516_buildings.geojson', 'w', encoding='utf-8') as f:
    json.dump(bld_data, f, ensure_ascii=False, indent=2)

print(f"Removed {len(removed_blds)} manual buildings:")
for r in removed_blds:
    print(" -", r)
print(f"Buildings count: {initial_count} -> {len(clean_blds)}")

# 2. Roads
with open('tools/map/usst_516_roads.geojson', 'r', encoding='utf-8') as f:
    road_data = json.load(f)

clean_roads = [f for f in road_data['features'] if not str(f.get('id', '')).startswith('manual/')]
road_data['features'] = clean_roads

with open('tools/map/usst_516_roads.geojson', 'w', encoding='utf-8') as f:
    json.dump(road_data, f, ensure_ascii=False, indent=2)

print(f"Roads cleaned: {len(clean_roads)} roads kept.")

# 3. POIs
with open('tools/map/usst_516_pois.geojson', 'r', encoding='utf-8') as f:
    poi_data = json.load(f)

clean_pois = [f for f in poi_data['features'] if not str(f.get('id', '')).startswith('manual/')]
poi_data['features'] = clean_pois

with open('tools/map/usst_516_pois.geojson', 'w', encoding='utf-8') as f:
    json.dump(poi_data, f, ensure_ascii=False, indent=2)

print(f"POIs cleaned: {len(clean_pois)} pois kept.")
