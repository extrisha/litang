import fs from 'fs';

const shapesSrc = fs.readFileSync('lib/data/campus_shapes.dart', 'utf8');
const configSrc = fs.readFileSync('lib/data/geo/campus_config.dart', 'utf8');

// Parse POIs
const poiRegex = /name:\s*'([^']+)',\s*campusId:\s*'([^']+)',\s*location:\s*LatLng\(([\d.]+),\s*([\d.]+)\)/g;
const pois = {};
let match;
while ((match = poiRegex.exec(configSrc)) !== null) {
  pois[match[1]] = { campusId: match[2], lat: parseFloat(match[3]), lng: parseFloat(match[4]) };
}

// Parse shapes
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

function detectCategory(name) {
  if (name.includes('宿舍') || name.includes('公寓')) return 'CampusCategory.dorm';
  if (name.includes('食堂') || name.includes('餐厅')) return 'CampusCategory.dining';
  if (name.includes('图文') || name.includes('图书') || name.includes('档案')) return 'CampusCategory.library';
  if (name.includes('体育') || name.includes('运动场') || name.includes('健身')) return 'CampusCategory.sports';
  if (name.includes('门') && (name.includes('号门') || name.includes('大门') || name.includes('校门'))) return 'CampusCategory.gate';
  if (name.includes('超市') || name.includes('驿站') || name.includes('门诊') || name.includes('收发')) return 'CampusCategory.service';
  return 'CampusCategory.teaching';
}

function detectImportance(name) {
  const landmarks = [
    '第一教学楼', '卓越楼', '综合楼', '图文信息中心', '先进制造大楼',
    '第二教学楼', '第三教学楼', '第四教学楼', '经管楼', '国合楼',
    '第一食堂', '第二食堂', '第五食堂', '思餐厅', '体育健身中心',
    '毛主席像广场', '大礼堂', '湛恩烈士故居'
  ];
  return landmarks.some(l => name.includes(l)) ? 2 : 1;
}

const buildingLines = [];

shapes.forEach((shape, idx) => {
  let cx = 0, cy = 0;
  for (const pt of shape.points) {
    cx += pt.x;
    cy += pt.y;
  }
  cx /= shape.points.length;
  cy /= shape.points.length;

  const rawCenter = toLatLng({ x: cx, y: cy });

  let matchedPoi = null;
  let mainName = shape.names[0] || `建筑_${idx + 1}`;
  for (const n of shape.names) {
    if (pois[n]) {
      matchedPoi = pois[n];
      mainName = n;
      break;
    }
  }

  const dLat = matchedPoi ? matchedPoi.lat - rawCenter.lat : 0;
  const dLng = matchedPoi ? matchedPoi.lng - rawCenter.lng : 0;

  const latLngs = shape.points.map(pt => {
    const raw = toLatLng(pt);
    return `LatLng(${(raw.lat + dLat).toFixed(6)}, ${(raw.lng + dLng).toFixed(6)})`;
  });

  const centerLat = matchedPoi ? matchedPoi.lat.toFixed(6) : rawCenter.lat.toFixed(6);
  const centerLng = matchedPoi ? matchedPoi.lng.toFixed(6) : rawCenter.lng.toFixed(6);

  const aliases = shape.names.filter(n => n !== mainName);
  const category = detectCategory(mainName);
  const importance = detectImportance(mainName);

  // Add sample entrances for key buildings to lay down the entrance navigation foundation!
  let entrancesStr = '<BuildingEntrance>[]';
  if (mainName === '第一教学楼') {
    entrancesStr = `<BuildingEntrance>[
      BuildingEntrance(
        id: 'bld_516_${idx + 1}_ent_main',
        name: '一教正门(南面大台阶)',
        location: LatLng(31.292700, 121.554000),
        nearbyRooms: ['101', '102', '103', '104', '105', '106', '阶梯一'],
        hasStairs: true,
      ),
      BuildingEntrance(
        id: 'bld_516_${idx + 1}_ent_west',
        name: '一教西侧无障碍门',
        location: LatLng(31.293200, 121.553400),
        nearbyRooms: ['110', '112', '115', '阶梯二'],
        bikeAllowed: true,
        hasStairs: false,
      ),
      BuildingEntrance(
        id: 'bld_516_${idx + 1}_ent_north',
        name: '一教北门(通往大礼堂)',
        location: LatLng(31.293700, 121.554100),
        nearbyRooms: ['120', '122', '125'],
      ),
    ]`;
  } else if (mainName === '卓越楼') {
    entrancesStr = `<BuildingEntrance>[
      BuildingEntrance(
        id: 'bld_516_${idx + 1}_ent_south',
        name: '卓越楼南门(主入口大厅)',
        location: LatLng(31.290100, 121.551600),
        nearbyRooms: ['101', '102', '报告厅'],
      ),
      BuildingEntrance(
        id: 'bld_516_${idx + 1}_ent_east',
        name: '卓越楼东门',
        location: LatLng(31.290600, 121.552100),
        nearbyRooms: ['108', '110', '112'],
      ),
    ]`;
  } else if (mainName === '图文信息中心') {
    entrancesStr = `<BuildingEntrance>[
      BuildingEntrance(
        id: 'bld_516_${idx + 1}_ent_main',
        name: '图文中心主入口(正门)',
        location: LatLng(31.292200, 121.551200),
        nearbyRooms: ['借阅大厅', '第一研讨室', '报告厅'],
      ),
    ]`;
  }

  buildingLines.push(`  BuildingFeature(
    id: 'bld_516_${idx + 1}',
    name: '${mainName}',
    campusId: 'jungong516',
    category: ${category},
    importance: ${importance},
    center: LatLng(${centerLat}, ${centerLng}),
    aliases: <String>[${aliases.map(a => `'${a}'`).join(', ')}],
    entrances: ${entrancesStr},
    points: <LatLng>[
      ${latLngs.join(',\n      ')},
    ],
  )`);
});

const dartCode = `import 'package:latlong2/latlong.dart';

import '../geo/campus_config.dart';
import 'models.dart';

/// 军工路516号校区（本部）专属地貌与建筑高精矢量数据集
class VectorData516 {
  VectorData516._();

  /// 516校区景观与地形地貌（校园红线、黄浦江岸线、大草坪、跑道）
  static const List<GroundFeature> grounds = <GroundFeature>[
    // 1. 军工路516号校区红线地块外轮廓 (覆盖南区与北区，沿军工路至黄浦江)
    GroundFeature(
      id: 'gnd_516_perimeter',
      name: '516校区红线范围',
      campusId: 'jungong516',
      type: GroundType.campusGround,
      center: LatLng(31.2917, 121.5532),
      points: <LatLng>[
        LatLng(31.2952, 121.5465), // 西北角 (军工路/翔殷路)
        LatLng(31.2950, 121.5540), // 北界
        LatLng(31.2935, 121.5585), // 东北角 (黄浦江畔)
        LatLng(31.2910, 121.5592), // 黄浦江滨江东段
        LatLng(31.2870, 121.5580), // 东南角 (邻近滨江)
        LatLng(31.2865, 121.5525), // 南界
        LatLng(31.2878, 121.5490), // 军工路南段
        LatLng(31.2920, 121.5475), // 军工路中段
        LatLng(31.2952, 121.5465), // 闭合
      ],
    ),

    // 2. 黄浦江岸线水系多边形（东侧临江景致）
    GroundFeature(
      id: 'gnd_516_huangpu_river',
      name: '黄浦江',
      campusId: 'jungong516',
      type: GroundType.water,
      center: LatLng(31.2910, 121.5605),
      points: <LatLng>[
        LatLng(31.2940, 121.5585),
        LatLng(31.2910, 121.5595),
        LatLng(31.2870, 121.5582),
        LatLng(31.2865, 121.5620),
        LatLng(31.2910, 121.5635),
        LatLng(31.2945, 121.5625),
        LatLng(31.2940, 121.5585),
      ],
    ),

    // 3. 毛主席像中心大草坪
    GroundFeature(
      id: 'gnd_516_great_lawn',
      name: '大草坪',
      campusId: 'jungong516',
      type: GroundType.lawn,
      center: LatLng(31.2919, 121.5536),
      points: <LatLng>[
        LatLng(31.2923, 121.5533),
        LatLng(31.2924, 121.5540),
        LatLng(31.2915, 121.5541),
        LatLng(31.2914, 121.5534),
        LatLng(31.2923, 121.5533),
      ],
    ),

    // 4. 北区田径运动场跑道
    GroundFeature(
      id: 'gnd_516_north_track',
      name: '北区田径场',
      campusId: 'jungong516',
      type: GroundType.sportsTrack,
      center: LatLng(31.2915, 121.5558),
      points: <LatLng>[
        LatLng(31.2921, 121.5552),
        LatLng(31.2922, 121.5564),
        LatLng(31.2908, 121.5565),
        LatLng(31.2907, 121.5553),
        LatLng(31.2921, 121.5552),
      ],
    ),

    // 5. 南区田径运动场跑道
    GroundFeature(
      id: 'gnd_516_south_track',
      name: '南区田径场',
      campusId: 'jungong516',
      type: GroundType.sportsTrack,
      center: LatLng(31.2878, 121.5540),
      points: <LatLng>[
        LatLng(31.2884, 121.5534),
        LatLng(31.2885, 121.5546),
        LatLng(31.2872, 121.5547),
        LatLng(31.2871, 121.5535),
        LatLng(31.2884, 121.5534),
      ],
    ),
  ];

  /// 516校区全部 87 栋建筑高精轮廓、中心与出入口
  static const List<BuildingFeature> buildings = <BuildingFeature>[
${buildingLines.join(',\n')}
  ];
}
`;

fs.writeFileSync('lib/data/vector_map/vector_data_516.dart', dartCode, 'utf8');
console.log('Successfully generated lib/data/vector_map/vector_data_516.dart!');
