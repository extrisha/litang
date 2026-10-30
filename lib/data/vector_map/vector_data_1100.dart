import 'package:latlong2/latlong.dart';

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
        LatLng(31.282665, 121.557211),
        LatLng(31.282665, 121.557789),
        LatLng(31.282935, 121.557789),
        LatLng(31.282935, 121.557211),
        LatLng(31.282665, 121.557211),
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
        LatLng(31.281842, 121.557884),
        LatLng(31.281842, 121.558516),
        LatLng(31.282158, 121.558516),
        LatLng(31.282158, 121.557884),
        LatLng(31.281842, 121.557884),
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
        LatLng(31.283374, 121.557963),
        LatLng(31.283374, 121.558437),
        LatLng(31.283626, 121.558437),
        LatLng(31.283626, 121.557963),
        LatLng(31.283374, 121.557963),
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
        LatLng(31.281383, 121.556632),
        LatLng(31.281383, 121.557368),
        LatLng(31.281617, 121.557368),
        LatLng(31.281617, 121.556632),
        LatLng(31.281383, 121.556632),
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
        LatLng(31.282946, 121.556405),
        LatLng(31.282946, 121.556595),
        LatLng(31.283054, 121.556595),
        LatLng(31.283054, 121.556405),
        LatLng(31.282946, 121.556405),
      ],
    ),
  ];
}
