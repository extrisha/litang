import 'package:latlong2/latlong.dart';

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
        LatLng(31.308356, 121.536511),
        LatLng(31.308356, 121.537089),
        LatLng(31.308644, 121.537089),
        LatLng(31.308644, 121.536511),
        LatLng(31.308356, 121.536511),
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
        LatLng(31.307887, 121.537279),
        LatLng(31.307887, 121.537721),
        LatLng(31.308113, 121.537721),
        LatLng(31.308113, 121.537279),
        LatLng(31.307887, 121.537279),
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
        LatLng(31.307955, 121.535716),
        LatLng(31.307955, 121.535884),
        LatLng(31.308045, 121.535884),
        LatLng(31.308045, 121.535716),
        LatLng(31.307955, 121.535716),
      ],
    ),
  ];
}
