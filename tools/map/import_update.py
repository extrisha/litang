import sys
import json
import os

if len(sys.argv) < 2:
    print("Usage: python tools/map/import_update.py <path_to_update_bundle.json>")
    sys.exit(1)

bundle_path = sys.argv[1]
with open(bundle_path, 'r', encoding='utf-8') as f:
    bundle = json.load(f)

print(f"Loading update bundle from {bundle_path}...")
if 'buildings' in bundle:
    with open('tools/map/usst_516_buildings.geojson', 'w', encoding='utf-8') as f:
        json.dump(bundle['buildings'], f, ensure_ascii=False, indent=2)
    print("Updated tools/map/usst_516_buildings.geojson!")

if 'roads' in bundle:
    with open('tools/map/usst_516_roads.geojson', 'w', encoding='utf-8') as f:
        json.dump(bundle['roads'], f, ensure_ascii=False, indent=2)
    print("Updated tools/map/usst_516_roads.geojson!")

print("All changes successfully merged into Project_USST!")
