import json
import math

def px_to_latlon(px_x, px_y, x0=219578, y0=107057, z=18):
    tile_x = x0 + px_x / 256.0
    tile_y = y0 + px_y / 256.0
    lon = (tile_x / (2**z)) * 360.0 - 180.0
    n = math.pi - 2.0 * math.pi * tile_y / (2**z)
    lat = math.degrees(math.atan(math.sinh(n)))
    return [round(lon, 7), round(lat, 7)]

# Load existing geojson files
with open('tools/map/usst_516_buildings.geojson', 'r', encoding='utf-8') as f:
    bld_data = json.load(f)

with open('tools/map/usst_516_roads.geojson', 'r', encoding='utf-8') as f:
    road_data = json.load(f)

with open('tools/map/usst_516_pois.geojson', 'r', encoding='utf-8') as f:
    poi_data = json.load(f)

# Northwest missing buildings pixel coordinates on esri_northwest.jpg (1024x1024)
# 1. 05 体育活动中心 (Large rectangular sports hall)
poly_05_px = [
    (425, 415), (700, 180), (885, 340), (610, 580), (425, 415)
]

# 2. A 第七学生公寓 (Dormitory complex with 3 wings facing southwest towards courtyard)
poly_A_px = [
    (310, 420), (360, 465), (425, 410), (405, 390), (455, 345),
    (435, 325), (490, 275), (470, 255), (515, 215), (475, 180),
    (270, 360), (310, 420)
]

# 3. 01 先进制造大楼 (High-rise with courtyard facing northeast towards A)
poly_01_px = [
    (335, 645), (405, 580), (465, 630), (525, 575), (575, 620),
    (535, 660), (510, 640), (470, 680), (435, 715), (370, 660),
    (335, 645)
]

# 4. 02 先进制造大楼辅楼
poly_02_px = [
    (320, 810), (375, 755), (430, 805), (375, 860), (320, 810)
]

# 5. 03 继续教育学院 / 创新创业学院
poly_03_px = [
    (220, 725), (255, 695), (285, 725), (250, 755), (220, 725)
]

# 6. 04 分析测试中心 / 电镜影像分中心(一)
poly_04_px = [
    (255, 690), (300, 650), (345, 690), (300, 730), (255, 690)
]

# 7. 06 工程实训中心 (Northeast of 05)
poly_06_px = [
    (740, 430), (870, 315), (960, 400), (830, 515), (740, 430)
]

# 8. 07 材料与化学学院 材料楼
poly_07_px = [
    (680, 555), (745, 495), (800, 545), (735, 605), (680, 555)
]

new_buildings = [
    {
        'code': '01',
        'name': '先进制造大楼',
        'category': 'teaching',
        'levels': '9',
        'px': poly_01_px
    },
    {
        'code': '02',
        'name': '先进制造大楼辅楼',
        'category': 'teaching',
        'subtitle': '信息化办公室 / 智慧校园建设推进办公室 / 高性能计算中心',
        'levels': '4',
        'px': poly_02_px
    },
    {
        'code': '03',
        'name': '继续教育学院 / 创新创业学院',
        'category': 'teaching',
        'levels': '3',
        'px': poly_03_px
    },
    {
        'code': '04',
        'name': '分析测试中心 / 电镜影像分中心(一)',
        'category': 'teaching',
        'levels': '3',
        'px': poly_04_px
    },
    {
        'code': '05',
        'name': '体育活动中心',
        'category': 'sports',
        'levels': '2',
        'px': poly_05_px
    },
    {
        'code': 'A',
        'name': '第七学生公寓',
        'category': 'dorm',
        'subtitle': '学生宿舍（原学生发展中心规划改造）',
        'levels': '6',
        'px': poly_A_px
    },
    {
        'code': '06',
        'name': '工程实训中心',
        'category': 'teaching',
        'levels': '3',
        'px': poly_06_px
    },
    {
        'code': '07',
        'name': '材料与化学学院 材料楼',
        'category': 'teaching',
        'levels': '4',
        'px': poly_07_px
    }
]

# Convert new buildings to GeoJSON features
for nb in new_buildings:
    coords = [px_to_latlon(p[0], p[1]) for p in nb['px']]
    feat = {
        'type': 'Feature',
        'id': f"manual/{nb['code']}",
        'properties': {
            'id': f"manual_{nb['code']}",
            'code': nb['code'],
            'name': nb['name'],
            'category': nb['category'],
            'subtitle': nb.get('subtitle', ''),
            'levels': nb.get('levels', '4'),
            'tags': {
                'name': nb['name'],
                'building': nb['category'],
                'code': nb['code'],
                'source': 'Official Map 2026 + Esri Satellite'
            }
        },
        'geometry': {
            'type': 'Polygon',
            'coordinates': [coords]
        }
    }
    bld_data['features'].append(feat)

# Now enrich existing buildings with official codes and names
# Match official numbers from official map
official_map_dict = {
    '第一教学楼': {'code': '40', 'category': 'teaching'},
    '第三教学楼': {'code': '15', 'category': 'teaching'},
    '第四教学楼': {'code': '03', 'category': 'teaching'},
    '综合楼': {'code': '21', 'category': 'teaching', 'subtitle': '东方泛血管器械创新研究院A区 / 教学楼BCD区'},
    '卓越楼': {'code': '15', 'category': 'teaching'},
    '格致堂': {'code': '45', 'category': 'teaching', 'subtitle': '沪江大学科学馆 / 机械学院 / 材化学院'},
    '大礼堂': {'code': '43', 'category': 'teaching'},
    '小礼堂': {'code': '47', 'category': 'sports', 'subtitle': '沪江大学体育馆'},
    '思福堂': {'code': '35', 'category': 'teaching'},
    '思雷堂': {'code': '24', 'category': 'teaching', 'subtitle': '能动学院一办'},
    '思孟堂': {'code': '25', 'category': 'teaching', 'subtitle': '能动学院二办'},
    '思晏堂': {'code': '44', 'category': 'teaching'},
    '音乐堂': {'code': '29', 'category': 'teaching'},
    '动力馆': {'code': '23', 'category': 'teaching', 'subtitle': '能源与动力工程学院'},
    '系统楼': {'code': '28', 'category': 'teaching', 'subtitle': '公共实验中心'},
    '光电信息与计算机工程学院': {'code': '10', 'category': 'teaching'},
    '第二食堂': {'code': '60', 'category': 'dining'},
    '第一食堂': {'code': '59', 'category': 'dining'},
    '第五食堂': {'code': '20', 'category': 'dining'},
    '图文信息中心': {'code': '17', 'category': 'library', 'subtitle': '图书馆 / 档案馆 / 计算中心'},
    '第七宿舍': {'code': 'M', 'category': 'dorm', 'name': '第七学生宿舍'},
    '第三宿舍 (思裴堂)': {'code': 'K', 'category': 'dorm', 'name': '思裴堂 (第三学生宿舍)'},
    '第四宿舍 (思伊堂)': {'code': 'L', 'category': 'dorm', 'name': '思伊堂 (第四学生宿舍)'},
    '第九学生宿舍': {'code': 'N', 'category': 'dorm'},
    '第十学生宿舍': {'code': 'O', 'category': 'dorm'},
    '第十一学生宿舍': {'code': 'P', 'category': 'dorm'},
    '第十二学生宿舍': {'code': 'Q', 'category': 'dorm'},
    '馥赉堂 (留学生公寓) (馥赉堂)': {'code': 'R', 'category': 'dorm', 'name': '馥赉堂 (留学生公寓一号楼)'},
    '第二学生公寓 1 号楼': {'code': 'U', 'category': 'dorm', 'name': '第二学生公寓一号楼'},
    '第二学生公寓 2 号楼': {'code': 'V', 'category': 'dorm', 'name': '第二学生公寓二号楼'},
    '第二学生公寓 3 号楼': {'code': 'W', 'category': 'dorm', 'name': '第二学生公寓三号楼'},
    '第四学生公寓 1 号楼': {'code': 'E', 'category': 'dorm', 'name': '第四学生公寓一号楼'},
    '第四学生公寓 2 号楼': {'code': 'F', 'category': 'dorm', 'name': '第四学生公寓二号楼'},
    '第四学生公寓 3 号楼': {'code': 'G', 'category': 'dorm', 'name': '第四学生公寓三号楼'},
    '第四学生公寓 4 号楼': {'code': 'H', 'category': 'dorm', 'name': '第四学生公寓四号楼'},
    '刘湛恩故居': {'code': '33', 'category': 'service', 'name': '刘湛恩烈士故居'},
    '教工之家': {'code': '50', 'category': 'service'},
    '保卫处': {'code': '19', 'category': 'service', 'name': '保卫处 校园110'},
    '医务室': {'code': '18', 'category': 'service', 'name': '校门诊部'},
    '勤工俭学中心 (红塔)': {'code': '46', 'category': 'service', 'name': '红塔 (沪江大学水塔)'},
    '体育健身中心': {'code': '65', 'category': 'sports'},
    '北区运动场': {'code': '64', 'category': 'sports'}
}

# Update properties in existing features
for feat in bld_data['features']:
    props = feat['properties']
    name = props.get('name', '')
    for match_k, meta in official_map_dict.items():
        if match_k in name:
            props['code'] = meta.get('code')
            props['category'] = meta.get('category')
            if 'subtitle' in meta:
                props['subtitle'] = meta['subtitle']
            if 'name' in meta:
                props['name'] = meta['name']
            break
    
    # Auto category if not set
    if 'category' not in props:
        if any(w in name for w in ['宿舍', '公寓']): props['category'] = 'dorm'
        elif any(w in name for w in ['食堂', '餐厅']): props['category'] = 'dining'
        elif any(w in name for w in ['图书馆', '图文']): props['category'] = 'library'
        elif any(w in name for w in ['体育', '运动', '健身']): props['category'] = 'sports'
        else: props['category'] = 'teaching'

# Add pedestrian walkway network connecting 580 gate to 01, A, 05, and existing network
# 580 Gate coordinate: lon 121.5463, lat 31.2938
gate_580_pt = [121.54630, 31.29380]
road_to_01 = [
    gate_580_pt,
    [121.54685, 31.29395],
    [121.54735, 31.29410],
    [121.54790, 31.29425]  # connects to existing road near 06 / 05
]
road_to_A = [
    [121.54685, 31.29395],
    [121.54715, 31.29450],
    [121.54755, 31.29465],
    [121.54780, 31.29490]  # links to 05 and A courtyard
]
road_around_05 = [
    [121.54755, 31.29465],
    [121.54820, 31.29490],
    [121.54865, 31.29440],
    [121.54790, 31.29425]
]

for i, seg in enumerate([road_to_01, road_to_A, road_around_05]):
    road_data['features'].append({
        'type': 'Feature',
        'id': f"manual/road_nw_{i}",
        'properties': {
            'id': f"manual_road_nw_{i}",
            'name': '580号门与先进制造/第七公寓步道',
            'highway': 'footway',
            'foot': 'yes',
            'bicycle': 'yes'
        },
        'geometry': {
            'type': 'LineString',
            'coordinates': seg
        }
    })

# Add official Gates to POIs
official_gates = [
    {'name': '军工路580号校门', 'coords': gate_580_pt, 'code': 'Gate 580'},
    {'name': '军工路516号校门 (主校门)', 'coords': [121.54890, 31.29170], 'code': 'Gate 516'},
    {'name': '军工路470号校门', 'coords': [121.55070, 31.28990], 'code': 'Gate 470'},
    {'name': '军工路334号校门 (南校区门)', 'coords': [121.55400, 31.28450], 'code': 'Gate 334'},
    {'name': '一号天桥 (连通南北区)', 'coords': [121.55730, 31.28820], 'code': 'Bridge 1'},
    {'name': '二号天桥 (连通南北区)', 'coords': [121.55760, 31.28870], 'code': 'Bridge 2'},
]

for g in official_gates:
    poi_data['features'].append({
        'type': 'Feature',
        'id': f"manual/gate_{g['name']}",
        'properties': {
            'name': g['name'],
            'amenity': 'gate',
            'code': g['code']
        },
        'geometry': {
            'type': 'Point',
            'coordinates': g['coords']
        }
    })

# Save updated files
with open('tools/map/usst_516_buildings.geojson', 'w', encoding='utf-8') as f:
    json.dump(bld_data, f, ensure_ascii=False, indent=2)

with open('tools/map/usst_516_roads.geojson', 'w', encoding='utf-8') as f:
    json.dump(road_data, f, ensure_ascii=False, indent=2)

with open('tools/map/usst_516_pois.geojson', 'w', encoding='utf-8') as f:
    json.dump(poi_data, f, ensure_ascii=False, indent=2)

print(f"Sync complete! Total buildings now: {len(bld_data['features'])}, Roads: {len(road_data['features'])}, POIs: {len(poi_data['features'])}")
