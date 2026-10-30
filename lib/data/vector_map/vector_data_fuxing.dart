import 'package:latlong2/latlong.dart';

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
        LatLng(31.213865, 121.458537),
        LatLng(31.213865, 121.459063),
        LatLng(31.214135, 121.459063),
        LatLng(31.214135, 121.458537),
        LatLng(31.213865, 121.458537),
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
        LatLng(31.213483, 121.459263),
        LatLng(31.213483, 121.459737),
        LatLng(31.213717, 121.459737),
        LatLng(31.213717, 121.459263),
        LatLng(31.213483, 121.459263),
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
        LatLng(31.213392, 121.458011),
        LatLng(31.213392, 121.458389),
        LatLng(31.213608, 121.458389),
        LatLng(31.213608, 121.458011),
        LatLng(31.213392, 121.458011),
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
        LatLng(31.212901, 121.458789),
        LatLng(31.212901, 121.459211),
        LatLng(31.213099, 121.459211),
        LatLng(31.213099, 121.458789),
        LatLng(31.212901, 121.458789),
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
        LatLng(31.214455, 121.458916),
        LatLng(31.214455, 121.459084),
        LatLng(31.214545, 121.459084),
        LatLng(31.214545, 121.458916),
        LatLng(31.214455, 121.458916),
      ],
    ),
  ];
}
