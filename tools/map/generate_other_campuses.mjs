import fs from 'fs';

function rect(lat, lng, wMeters, hMeters) {
  const dLat = (hMeters / 2) / 111000;
  const dLng = (wMeters / 2) / 95000;
  return [
    `LatLng(${(lat - dLat).toFixed(6)}, ${(lng - dLng).toFixed(6)})`,
    `LatLng(${(lat - dLat).toFixed(6)}, ${(lng + dLng).toFixed(6)})`,
    `LatLng(${(lat + dLat).toFixed(6)}, ${(lng + dLng).toFixed(6)})`,
    `LatLng(${(lat + dLat).toFixed(6)}, ${(lng - dLng).toFixed(6)})`,
    `LatLng(${(lat - dLat).toFixed(6)}, ${(lng - dLng).toFixed(6)})`,
  ];
}

// 1100 Campus
const code1100 = `import 'package:latlong2/latlong.dart';

import '../geo/campus_config.dart';
import 'models.dart';

/// 军工路1100号校区（南校区 / 基础教学园区）矢量数据集
class VectorData1100 {
  VectorData1100._();

  static const List<GroundFeature> grounds = <GroundFeature>[
    // 校园地块范围
    GroundFeature(
      id: 'gnd_1100_perimeter',
      name: '1100号校区红线范围',
      campusId: 'jungong1100',
      type: GroundType.campusGround,
      center: LatLng(31.2825, 121.5580),
      points: <LatLng>[
        LatLng(31.2845, 121.5558),
        LatLng(31.2846, 121.5605),
        LatLng(31.2805, 121.5608),
        LatLng(31.2804, 121.5562),
        LatLng(31.2845, 121.5558),
      ],
    ),
    // 操场
    GroundFeature(
      id: 'gnd_1100_track',
      name: '1100号田径场',
      campusId: 'jungong1100',
      type: GroundType.sportsTrack,
      center: LatLng(31.2822, 121.5595),
      points: <LatLng>[
        LatLng(31.2828, 121.5590),
        LatLng(31.2828, 121.5602),
        LatLng(31.2816, 121.5602),
        LatLng(31.2816, 121.5590),
        LatLng(31.2828, 121.5590),
      ],
    ),
  ];

  static const List<BuildingFeature> buildings = <BuildingFeature>[
    BuildingFeature(
      id: 'bld_1100_1',
      name: '1100号第一教学楼',
      campusId: 'jungong1100',
      category: CampusCategory.teaching,
      importance: 2,
      center: LatLng(31.2828, 121.5575),
      aliases: <String>['南区一教', '基础教学楼'],
      entrances: <BuildingEntrance>[
        BuildingEntrance(
          id: 'bld_1100_1_ent_main',
          name: '1100号一教主入口',
          location: LatLng(31.2826, 121.5575),
          nearbyRooms: ['101', '102', '103'],
        ),
      ],
      points: <LatLng>[
        ${rect(31.2828, 121.5575, 55, 30).join(',\n        ')},
      ],
    ),
    BuildingFeature(
      id: 'bld_1100_2',
      name: '1100号教学中心',
      campusId: 'jungong1100',
      category: CampusCategory.teaching,
      importance: 2,
      center: LatLng(31.2820, 121.5582),
      aliases: <String>['教学中心大楼'],
      points: <LatLng>[
        ${rect(31.2820, 121.5582, 60, 35).join(',\n        ')},
      ],
    ),
    BuildingFeature(
      id: 'bld_1100_3',
      name: '基础部第四食堂',
      campusId: 'jungong1100',
      category: CampusCategory.dining,
      importance: 2,
      center: LatLng(31.2835, 121.5582),
      aliases: <String>['南区食堂', '第四食堂'],
      points: <LatLng>[
        ${rect(31.2835, 121.5582, 45, 28).join(',\n        ')},
      ],
    ),
    BuildingFeature(
      id: 'bld_1100_4',
      name: '1100号学生公寓',
      campusId: 'jungong1100',
      category: CampusCategory.dorm,
      importance: 1,
      center: LatLng(31.2815, 121.5570),
      aliases: <String>['南区宿舍'],
      points: <LatLng>[
        ${rect(31.2815, 121.5570, 70, 26).join(',\n        ')},
      ],
    ),
    BuildingFeature(
      id: 'bld_1100_gate',
      name: '军工路1100号大门',
      campusId: 'jungong1100',
      category: CampusCategory.gate,
      importance: 2,
      center: LatLng(31.2830, 121.5565),
      aliases: <String>['1100号正门'],
      points: <LatLng>[
        ${rect(31.2830, 121.5565, 18, 12).join(',\n        ')},
      ],
    ),
  ];
}
`;

// Fuxing Campus
const codeFuxing = `import 'package:latlong2/latlong.dart';

import '../geo/campus_config.dart';
import 'models.dart';

/// 复兴路校区（中英国际学院 SBC）矢量数据集
class VectorDataFuxing {
  VectorDataFuxing._();

  static const List<GroundFeature> grounds = <GroundFeature>[
    GroundFeature(
      id: 'gnd_fuxing_perimeter',
      name: '复兴路校区红线范围',
      campusId: 'fuxing',
      type: GroundType.campusGround,
      center: LatLng(31.2138, 121.4586),
      points: <LatLng>[
        LatLng(31.2152, 121.4575),
        LatLng(31.2152, 121.4605),
        LatLng(31.2124, 121.4604),
        LatLng(31.2125, 121.4574),
        LatLng(31.2152, 121.4575),
      ],
    ),
  ];

  static const List<BuildingFeature> buildings = <BuildingFeature>[
    BuildingFeature(
      id: 'bld_fx_1',
      name: '中英国际学院主楼',
      campusId: 'fuxing',
      category: CampusCategory.teaching,
      importance: 2,
      center: LatLng(31.2140, 121.4588),
      aliases: <String>['SBC主楼', '行政楼'],
      points: <LatLng>[
        ${rect(31.2140, 121.4588, 50, 30).join(',\n        ')},
      ],
    ),
    BuildingFeature(
      id: 'bld_fx_2',
      name: '复兴路教学主楼',
      campusId: 'fuxing',
      category: CampusCategory.teaching,
      importance: 2,
      center: LatLng(31.2136, 121.4595),
      aliases: <String>['复兴路一教'],
      points: <LatLng>[
        ${rect(31.2136, 121.4595, 45, 26).join(',\n        ')},
      ],
    ),
    BuildingFeature(
      id: 'bld_fx_3',
      name: '复兴路图书馆',
      campusId: 'fuxing',
      category: CampusCategory.library,
      importance: 2,
      center: LatLng(31.2135, 121.4582),
      aliases: <String>['SBC图书馆'],
      points: <LatLng>[
        ${rect(31.2135, 121.4582, 36, 24).join(',\n        ')},
      ],
    ),
    BuildingFeature(
      id: 'bld_fx_4',
      name: '复兴路餐厅与学生活动中心',
      campusId: 'fuxing',
      category: CampusCategory.dining,
      importance: 1,
      center: LatLng(31.2130, 121.4590),
      aliases: <String>['复兴路食堂'],
      points: <LatLng>[
        ${rect(31.2130, 121.4590, 40, 22).join(',\n        ')},
      ],
    ),
    BuildingFeature(
      id: 'bld_fx_gate',
      name: '复兴路校门（复兴中路1195号）',
      campusId: 'fuxing',
      category: CampusCategory.gate,
      importance: 2,
      center: LatLng(31.2145, 121.4590),
      aliases: <String>['复兴中路大门'],
      points: <LatLng>[
        ${rect(31.2145, 121.4590, 16, 10).join(',\n        ')},
      ],
    ),
  ];
}
`;

// Yingkou Campus
const codeYingkou = `import 'package:latlong2/latlong.dart';

import '../geo/campus_config.dart';
import 'models.dart';

/// 营口路校区矢量数据集
class VectorDataYingkou {
  VectorDataYingkou._();

  static const List<GroundFeature> grounds = <GroundFeature>[
    GroundFeature(
      id: 'gnd_yk_perimeter',
      name: '营口路校区红线范围',
      campusId: 'yingkou',
      type: GroundType.campusGround,
      center: LatLng(31.3082, 121.5367),
      points: <LatLng>[
        LatLng(31.3095, 121.5350),
        LatLng(31.3096, 121.5385),
        LatLng(31.3070, 121.5384),
        LatLng(31.3070, 121.5350),
        LatLng(31.3095, 121.5350),
      ],
    ),
  ];

  static const List<BuildingFeature> buildings = <BuildingFeature>[
    BuildingFeature(
      id: 'bld_yk_1',
      name: '营口路教学综合楼',
      campusId: 'yingkou',
      category: CampusCategory.teaching,
      importance: 2,
      center: LatLng(31.3085, 121.5368),
      aliases: <String>['营口路主楼'],
      points: <LatLng>[
        ${rect(31.3085, 121.5368, 55, 32).join(',\n        ')},
      ],
    ),
    BuildingFeature(
      id: 'bld_yk_2',
      name: '营口路学生活动中心',
      campusId: 'yingkou',
      category: CampusCategory.service,
      importance: 1,
      center: LatLng(31.3080, 121.5375),
      aliases: <String>['活动中心'],
      points: <LatLng>[
        ${rect(31.3080, 121.5375, 42, 25).join(',\n        ')},
      ],
    ),
    BuildingFeature(
      id: 'bld_yk_gate',
      name: '营口路大门（营口路788号）',
      campusId: 'yingkou',
      category: CampusCategory.gate,
      importance: 2,
      center: LatLng(31.3080, 121.5358),
      aliases: <String>['营口路正门'],
      points: <LatLng>[
        ${rect(31.3080, 121.5358, 16, 10).join(',\n        ')},
      ],
    ),
  ];
}
`;

fs.writeFileSync('lib/data/vector_map/vector_data_1100.dart', code1100, 'utf8');
fs.writeFileSync('lib/data/vector_map/vector_data_fuxing.dart', codeFuxing, 'utf8');
fs.writeFileSync('lib/data/vector_map/vector_data_yingkou.dart', codeYingkou, 'utf8');
console.log('Successfully generated other campus vector data files!');
