import json

with open('tools/map/target_buildings.json', 'r', encoding='utf-8') as f:
    tb = json.load(f)

with open('tools/map/osm_analysis.json', 'r', encoding='utf-8') as f:
    osm = json.load(f)

osm_names = set(osm['named_buildings_list'])
tb_names = [b.get('name') for b in tb if b.get('name')]

matched = []
unmatched = []
for name in tb_names:
    found = False
    for on in osm_names:
        if name in on or on in name:
            matched.append((name, on))
            found = True
            break
    if not found:
        unmatched.append(name)

comp = {
    'target_count': len(tb_names),
    'matched_count': len(matched),
    'matched': matched,
    'unmatched_count': len(unmatched),
    'unmatched': unmatched
}

with open('tools/map/comparison.json', 'w', encoding='utf-8') as f:
    json.dump(comp, f, ensure_ascii=False, indent=2)

print("Comparison written to tools/map/comparison.json")
