import xml.etree.ElementTree as ET
import json

tree = ET.parse('tools/map/usst_516_raw.osm')
root = tree.getroot()

nodes = {}
for n in root.findall('node'):
    nid = n.get('id')
    lat = float(n.get('lat'))
    lon = float(n.get('lon'))
    tags = {t.get('k'): t.get('v') for t in n.findall('tag')}
    nodes[nid] = {'id': nid, 'lat': lat, 'lon': lon, 'tags': tags}

ways = []
for w in root.findall('way'):
    wid = w.get('id')
    tags = {t.get('k'): t.get('v') for t in w.findall('tag')}
    nds = [nd.get('ref') for nd in w.findall('nd')]
    ways.append({'id': wid, 'tags': tags, 'nodes': nds})

buildings = [w for w in ways if 'building' in w['tags']]
named_buildings = []
for b in buildings:
    name = b['tags'].get('name:zh') or b['tags'].get('name')
    if name:
        named_buildings.append({
            'id': b['id'],
            'name': name,
            'type': b['tags'].get('building'),
            'tags': b['tags']
        })

highways = [w for w in ways if 'highway' in w['tags']]
hw_summary = {}
for h in highways:
    ht = h['tags']['highway']
    hw_summary[ht] = hw_summary.get(ht, 0) + 1

res = {
    'total_nodes': len(nodes),
    'total_ways': len(ways),
    'total_buildings': len(buildings),
    'named_buildings_count': len(named_buildings),
    'named_buildings_list': [b['name'] for b in named_buildings],
    'highway_summary': hw_summary,
    'total_highways': len(highways)
}

with open('tools/map/osm_analysis.json', 'w', encoding='utf-8') as f:
    json.dump(res, f, ensure_ascii=False, indent=2)

print("Saved osm_analysis.json")
