import 'coordinate_utils.dart';

/// 一座教学楼的雷达签到基准点（GCJ-02）。
///
/// 数值与别名全部照抄 USST 参考实现 `usst-jwgl-client` 的
/// `CoordinateUtils.kt`（`legacy-22-v1`），不要自行「校准」：
/// 服务端就是拿这些点做范围比对。
class CampusBuilding {
  const CampusBuilding({
    required this.id,
    required this.name,
    required this.campus,
    required this.latitude,
    required this.longitude,
    this.aliases = const <String>[],
  });

  final String id;
  final String name;
  final String campus;

  /// GCJ-02 纬度。
  final double latitude;

  /// GCJ-02 经度。
  final double longitude;

  final List<String> aliases;

  @override
  String toString() => '$name ($campus)';
}

/// 上海理工大学各教学楼/场馆的雷达签到基准点（GCJ-02）。
const List<CampusBuilding> kUsstBuildings = <CampusBuilding>[
  // 本部北校区（军工路 516 号北区）
  CampusBuilding(
    id: 'b_516_1j_e',
    name: '一教东',
    campus: '本部北校区',
    latitude: 31.291731,
    longitude: 121.556084,
    aliases: <String>['一教东', '一教东区', '第一教学楼东', '一教中', '第一教学楼中'],
  ),
  CampusBuilding(
    id: 'b_516_1j_w',
    name: '一教西',
    campus: '本部北校区',
    latitude: 31.291376,
    longitude: 121.555443,
    aliases: <String>['一教西', '一教西区', '第一教学楼西'],
  ),
  CampusBuilding(
    id: 'b_516_3j_e',
    name: '三教',
    campus: '本部北校区',
    latitude: 31.294850,
    longitude: 121.555663,
    aliases: <String>[
      '三教',
      '第三教学楼',
      '3教',
      '三教东',
      '三教西',
      '三教东区',
      '三教西区',
      '第三教学楼东',
      '第三教学楼西',
    ],
  ),
  CampusBuilding(
    id: 'b_516_zh_a',
    name: '综合楼A区',
    campus: '本部北校区',
    latitude: 31.290008,
    longitude: 121.552855,
    aliases: <String>[
      '综合楼A区',
      '综合楼A',
      '综A',
      '综楼A',
      '综合A',
      '教学综合楼A区',
      '教学综合楼A',
    ],
  ),
  CampusBuilding(
    id: 'b_516_zh_b',
    name: '综合楼B区',
    campus: '本部北校区',
    latitude: 31.290425,
    longitude: 121.553512,
    aliases: <String>[
      '综合楼B区',
      '综合楼B',
      '综B',
      '综楼B',
      '综合B',
      '教学综合楼B区',
      '教学综合楼B',
    ],
  ),
  CampusBuilding(
    id: 'b_516_zh_c',
    name: '综合楼C区',
    campus: '本部北校区',
    latitude: 31.289549,
    longitude: 121.553327,
    aliases: <String>[
      '综合楼C区',
      '综合楼C',
      '综C',
      '综楼C',
      '综合C',
      '教学综合楼C区',
      '教学综合楼C',
    ],
  ),
  CampusBuilding(
    id: 'b_516_zh_d',
    name: '综合楼D区',
    campus: '本部北校区',
    latitude: 31.289939,
    longitude: 121.553901,
    aliases: <String>[
      '综合楼D区',
      '综合楼D',
      '综D',
      '综楼D',
      '综合D',
      '教学综合楼D区',
      '教学综合楼D',
    ],
  ),
  CampusBuilding(
    id: 'b_516_ggsy',
    name: '公共实验楼',
    campus: '本部北校区',
    latitude: 31.290732,
    longitude: 121.554982,
    aliases: <String>['公共实验楼', '公实楼', '实验楼'],
  ),
  CampusBuilding(
    id: 'b_516_jsz',
    name: '计算中心',
    campus: '本部北校区',
    latitude: 31.295343,
    longitude: 121.554926,
    aliases: <String>['计算中心', '计算机中心', '机房'],
  ),
  CampusBuilding(
    id: 'b_516_gys',
    name: '光仪所',
    campus: '本部北校区',
    latitude: 31.293320,
    longitude: 121.553673,
    aliases: <String>['光仪所', '上海光学仪器研究所', '光仪所辅房'],
  ),
  CampusBuilding(
    id: 'b_516_580_ty',
    name: '580体育活动中心',
    campus: '本部北校区',
    latitude: 31.292575,
    longitude: 121.552187,
    aliases: <String>['580体育活动中心', '580体育馆', '580操场', '体育活动中心', '体育馆', '风雨操场'],
  ),
  CampusBuilding(
    id: 'b_516_xty',
    name: '新体育健身中心',
    campus: '本部北校区',
    latitude: 31.291248,
    longitude: 121.557887,
    aliases: <String>['新体育健身中心', '健身中心', '新体育中心', '体育健身中心'],
  ),
  CampusBuilding(
    id: 'b_516_bxty',
    name: '北校田径场',
    campus: '本部北校区',
    latitude: 31.291041,
    longitude: 121.556672,
    aliases: <String>['北校田径场', '北田径场', '北区操场', '北操', '北操场'],
  ),

  // 本部南校区（军工路 516 号南区）
  CampusBuilding(
    id: 'b_516_zy',
    name: '卓越楼',
    campus: '本部南校区',
    latitude: 31.288889,
    longitude: 121.554837,
    aliases: <String>['卓越楼', '卓越', '卓越工程大楼'],
  ),
  CampusBuilding(
    id: 'b_516_gh',
    name: '国合楼',
    campus: '本部南校区',
    latitude: 31.287511,
    longitude: 121.556312,
    aliases: <String>['国合楼', '国合', '国际交流合作楼'],
  ),
  CampusBuilding(
    id: 'b_516_4j_w',
    name: '四教',
    campus: '本部南校区',
    latitude: 31.286636,
    longitude: 121.557302,
    aliases: <String>[
      '四教',
      '第四教学楼',
      '4教',
      '四教东',
      '四教西',
      '四教东区',
      '四教西区',
      '第四教学楼东',
      '第四教学楼西',
    ],
  ),

  // 军工路 1100 号校区（合并点位，尚未分楼校准）
  CampusBuilding(
    id: 'b_1100_bx',
    name: '博学楼',
    campus: '军工路1100号',
    latitude: 31.299551,
    longitude: 121.547103,
    aliases: <String>['博学楼', '博学'],
  ),
  CampusBuilding(
    id: 'b_1100_dl',
    name: '达理楼·勤学楼·乐学楼',
    campus: '军工路1100号',
    latitude: 31.299427,
    longitude: 121.546237,
    aliases: <String>[
      '达理楼',
      '达理',
      '勤学楼',
      '勤学',
      '乐学楼',
      '乐学',
      '1100号图书馆',
      '1100图',
      '1100图书馆',
    ],
  ),
  CampusBuilding(
    id: 'b_1100_hd',
    name: '格物楼·1100学生活动中心',
    campus: '军工路1100号',
    latitude: 31.299917,
    longitude: 121.546015,
    aliases: <String>['格物楼', '格物', '1100学生活动中心', '学生活动中心', '1100学活', '学活'],
  ),
  CampusBuilding(
    id: 'b_1100_jt',
    name: '1100申阶梯·体育活动中心',
    campus: '军工路1100号',
    latitude: 31.300101,
    longitude: 121.547137,
    aliases: <String>[
      '1100申阶梯',
      '申阶梯',
      '阶梯教室',
      '1100体育活动中心',
      '1100乒操馆',
      '乒操馆',
      '1100体育馆',
      '体育活动中心',
      '体育馆',
    ],
  ),

  // 外校区教学楼
  CampusBuilding(
    id: 'b_fx_jxl',
    name: '复兴路教学楼',
    campus: '复兴路校区',
    latitude: 31.211925,
    longitude: 121.460448,
    aliases: <String>['复兴路教学楼', '复兴路', '复兴校区', '复兴教学楼'],
  ),
  CampusBuilding(
    id: 'b_yk_jxl',
    name: '营口路教学楼',
    campus: '营口路校区',
    latitude: 31.289567,
    longitude: 121.534146,
    aliases: <String>['营口路教学楼', '营口路', '营口校区', '营口教学楼'],
  ),
];

CampusBuilding? _byId(String id) {
  for (final building in kUsstBuildings) {
    if (building.id == id) {
      return building;
    }
  }
  return null;
}

/// 按教室名/课程名模糊匹配教学楼，规则照抄参考实现 `findMatchingBuilding`。
CampusBuilding? findMatchingBuilding(String? placeOrRoom) {
  if (placeOrRoom == null) {
    return null;
  }
  final lower = placeOrRoom.trim().toLowerCase();
  if (lower.isEmpty) {
    return null;
  }

  // 1. 全名按长度降序优先匹配（避免短名提前拦截长名，
  //    如「580体育活动中心」与「1100体育活动中心」）。
  final byName = List<CampusBuilding>.of(kUsstBuildings)
    ..sort((a, b) => b.name.length.compareTo(a.name.length));
  for (final building in byName) {
    if (lower.contains(building.name.toLowerCase())) {
      return building;
    }
  }

  // 2. 别名匹配（按别名长度倒序，优先命中具体别名）。
  final aliases = <(String, CampusBuilding)>[
    for (final building in kUsstBuildings)
      for (final alias in building.aliases) (alias, building),
  ]..sort((a, b) => b.$1.length.compareTo(a.$1.length));
  for (final (alias, building) in aliases) {
    if (lower.contains(alias.toLowerCase())) {
      return building;
    }
  }

  // 3. 专属单体与组合楼宇智能规则分流。
  final roomOffset = _extractRoomOffset(lower);

  if (lower.contains('一教') ||
      lower.contains('第一教学楼') ||
      lower.contains('1教')) {
    if (lower.contains('西')) {
      return _byId('b_516_1j_w');
    }
    if (lower.contains('东')) {
      return _byId('b_516_1j_e');
    }
    if (roomOffset != null) {
      // 101~125 在一教东，126 以上在一教西；一教西缺失时回退一教东。
      return roomOffset <= 25
          ? _byId('b_516_1j_e')
          : (_byId('b_516_1j_w') ?? _byId('b_516_1j_e'));
    }
    return _byId('b_516_1j_e');
  }

  if (lower.contains('三教') ||
      lower.contains('第三教学楼') ||
      lower.contains('3教')) {
    return _byId('b_516_3j_e');
  }

  if (lower.contains('四教') ||
      lower.contains('第四教学楼') ||
      lower.contains('4教')) {
    return _byId('b_516_4j_w');
  }

  if (lower.contains('达理') || lower.contains('勤学') || lower.contains('乐学')) {
    return _byId('b_1100_dl');
  }
  if (lower.contains('格物') ||
      lower.contains('学活') ||
      (lower.contains('1100') && lower.contains('活动'))) {
    return _byId('b_1100_hd');
  }
  if (lower.contains('申阶梯') ||
      lower.contains('阶梯') ||
      (lower.contains('1100') &&
          (lower.contains('体') || lower.contains('操')))) {
    return _byId('b_1100_jt');
  }
  if (lower.contains('博学')) {
    return _byId('b_1100_bx');
  }

  if (lower.contains('综合楼') ||
      lower.contains('教学综合楼') ||
      lower.contains('综楼')) {
    if (lower.contains('a')) {
      return _byId('b_516_zh_a');
    }
    if (lower.contains('b')) {
      return _byId('b_516_zh_b');
    }
    if (lower.contains('c')) {
      return _byId('b_516_zh_c');
    }
    if (lower.contains('d')) {
      return _byId('b_516_zh_d');
    }
    return _byId('b_516_zh_a');
  }

  if (lower.contains('复兴')) {
    return _byId('b_fx_jxl');
  }
  if (lower.contains('营口')) {
    return _byId('b_yk_jxl');
  }

  return null;
}

int? _extractRoomOffset(String input) {
  final matches = RegExp(r'(\d{3,4})').allMatches(input).toList();
  if (matches.isEmpty) {
    return null;
  }
  final last = int.tryParse(matches.last.group(1)!);
  return last == null ? null : last % 100;
}

/// 按 GCJ-02 坐标找最近的基准点，同时返回距离（米）。
(CampusBuilding building, double distanceMeters) findNearestBuilding(
  double latitude,
  double longitude,
) {
  var minDistance = double.maxFinite;
  var nearest = kUsstBuildings.first;
  for (final building in kUsstBuildings) {
    final distance = CoordinateUtils.distanceMeters(
      latitude,
      longitude,
      building.latitude,
      building.longitude,
    );
    if (distance < minDistance) {
      minDistance = distance;
      nearest = building;
    }
  }
  return (nearest, minDistance);
}

/// 按系统 WGS-84 原始坐标纠偏后找最近基准点。
(CampusBuilding building, double distanceMeters) findNearestBuildingFromWgs84(
  double latitude,
  double longitude,
) {
  final (gcjLat, gcjLng) = CoordinateUtils.wgs84ToGcj02(latitude, longitude);
  return findNearestBuilding(gcjLat, gcjLng);
}
