import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../campus_places.dart';
import '../place_search.dart';

/// 校园场所分类
enum CampusCategory {
  all(label: '全部', icon: Icons.explore_outlined),
  teaching(label: '教学楼', icon: Icons.school_outlined),
  dining(label: '食堂', icon: Icons.restaurant_outlined),
  dorm(label: '宿舍公寓', icon: Icons.hotel_outlined),
  library(label: '图书自习', icon: Icons.menu_book_outlined),
  sports(label: '运动场馆', icon: Icons.sports_basketball_outlined),
  service(label: '生活服务', icon: Icons.local_convenience_store_outlined),
  gate(label: '校门', icon: Icons.door_front_door_outlined);

  const CampusCategory({required this.label, required this.icon});
  final String label;
  final IconData icon;
}

/// 校区配置
class Campus {
  const Campus({
    required this.id,
    required this.name,
    required this.shortName,
    required this.center,
    required this.bounds,
    this.defaultZoom = 16.5,
    this.minZoom = 14.5,
    this.maxZoom = 18.5,
  });

  final String id;
  final String name;
  final String shortName;
  final LatLng center;
  final LatLngBounds bounds;
  final double defaultZoom;
  final double minZoom;
  final double maxZoom;
}

/// 校园地点兴趣点（POI）
class CampusPoi {
  const CampusPoi({
    required this.name,
    required this.campusId,
    required this.location,
    required this.category,
    this.subtitle,
    this.aliases = const <String>[],
  });

  final String name;
  final String campusId;
  final LatLng location;
  final CampusCategory category;
  final String? subtitle;
  final List<String> aliases;

  CampusPlace toCampusPlace() {
    return CampusPlace(name: name, anchor: Offset.zero);
  }
}

/// 全校校区常量定义
class CampusData {
  CampusData._();

  static final Campus jungong = Campus(
    id: 'jungong',
    name: '军工路校区 (516号 / 1100号)',
    shortName: '军工路校区',
    center: const LatLng(31.2917, 121.5532),
    bounds: LatLngBounds(
      const LatLng(31.2780, 121.5450),
      const LatLng(31.3000, 121.5640),
    ),
    defaultZoom: 16.6,
  );

  static final Campus fuxing = Campus(
    id: 'fuxing',
    name: '复兴路校区 (中英国际学院 SBC)',
    shortName: '复兴路校区',
    center: const LatLng(31.2138, 121.4586),
    bounds: LatLngBounds(
      const LatLng(31.2110, 121.4545),
      const LatLng(31.2170, 121.4635),
    ),
    defaultZoom: 17.0,
  );

  static final Campus yingkou = Campus(
    id: 'yingkou',
    name: '营口路校区',
    shortName: '营口路校区',
    center: const LatLng(31.3082, 121.5367),
    bounds: LatLngBounds(
      const LatLng(31.3050, 121.5330),
      const LatLng(31.3120, 121.5415),
    ),
    defaultZoom: 17.0,
  );

  static final List<Campus> allCampuses = <Campus>[jungong, fuxing, yingkou];

  /// 常用地点 POI 表（军工路、复兴路、营口路）
  static final List<CampusPoi> pois = <CampusPoi>[
    // ================= 军工路 516 号 / 1100 号：教学楼 =================
    const CampusPoi(
      name: '第一教学楼',
      campusId: 'jungong',
      location: LatLng(31.2932, 121.5540),
      category: CampusCategory.teaching,
      subtitle: '一教 · 机械/能动/环建等大课教室',
      aliases: ['一教', '第一教学楼'],
    ),
    const CampusPoi(
      name: '第三教学楼',
      campusId: 'jungong',
      location: LatLng(31.2913, 121.5532),
      category: CampusCategory.teaching,
      subtitle: '三教 · 核心公共基础课教学楼',
      aliases: ['三教', '第三教学楼'],
    ),
    const CampusPoi(
      name: '第四教学楼（逸兴楼）',
      campusId: 'jungong',
      location: LatLng(31.2882, 121.5524),
      category: CampusCategory.teaching,
      subtitle: '四教 · 逸兴楼',
      aliases: ['四教', '第四教学楼', '逸兴楼'],
    ),
    const CampusPoi(
      name: '卓越楼',
      campusId: 'jungong',
      location: LatLng(31.2905, 121.5516),
      category: CampusCategory.teaching,
      subtitle: '卓越工程大楼 · 健康学院/出版学院',
      aliases: ['卓越工程大楼', '卓越楼'],
    ),
    const CampusPoi(
      name: '综合楼',
      campusId: 'jungong',
      location: LatLng(31.2900, 121.5502),
      category: CampusCategory.teaching,
      subtitle: '综合楼 A/B/C/D 区',
      aliases: ['综合A', '综合B', '综合C', '综合D', '综合楼A区', '综合楼B区', '综合楼C区', '综合楼D区'],
    ),
    const CampusPoi(
      name: '图文信息中心',
      campusId: 'jungong',
      location: LatLng(31.2925, 121.5512),
      category: CampusCategory.library,
      subtitle: '图书馆 · 档案馆 · 计算中心',
      aliases: ['图书馆', '图文', '档案馆', '计算中心', '图档'],
    ),
    const CampusPoi(
      name: '国合楼（中德国际学院）',
      campusId: 'jungong',
      location: LatLng(31.2885, 121.5515),
      category: CampusCategory.teaching,
      subtitle: '中德国际学院教学实验大楼',
      aliases: ['国合楼', '中德', '中德学院'],
    ),
    const CampusPoi(
      name: '系统楼（公共实验中心）',
      campusId: 'jungong',
      location: LatLng(31.2902, 121.5525),
      category: CampusCategory.teaching,
      subtitle: '公共实验中心 · 光电实验中心',
      aliases: ['公共实验楼', '公共实验中心', '系统楼'],
    ),
    const CampusPoi(
      name: '先进制造大楼',
      campusId: 'jungong',
      location: LatLng(31.2936, 121.5475),
      category: CampusCategory.teaching,
      subtitle: '先进制造技术工程研究中心',
      aliases: ['先进制造'],
    ),
    const CampusPoi(
      name: '工程实训中心',
      campusId: 'jungong',
      location: LatLng(31.2915, 121.5495),
      category: CampusCategory.teaching,
      subtitle: '机械金工金训与实训基地',
      aliases: ['实训中心', '金工实习'],
    ),
    const CampusPoi(
      name: '经管楼',
      campusId: 'jungong',
      location: LatLng(31.2875, 121.5535),
      category: CampusCategory.teaching,
      subtitle: '管理学院 · 马克思主义学院',
      aliases: ['管院', '管理学院', '经管楼南楼', '经管楼北楼'],
    ),

    // ================= 军工路 516 号 / 1100 号：食堂餐饮 =================
    const CampusPoi(
      name: '第一食堂',
      campusId: 'jungong',
      location: LatLng(31.2890, 121.5552),
      category: CampusCategory.dining,
      subtitle: '一食 · 邻近北区宿舍群',
      aliases: ['一食', '第一食堂'],
    ),
    const CampusPoi(
      name: '第二食堂',
      campusId: 'jungong',
      location: LatLng(31.2918, 121.5530),
      category: CampusCategory.dining,
      subtitle: '二食 · 核心教工与学生餐厅',
      aliases: ['二食', '第二食堂'],
    ),
    const CampusPoi(
      name: '第五食堂',
      campusId: 'jungong',
      location: LatLng(31.2875, 121.5570),
      category: CampusCategory.dining,
      subtitle: '五食 · 南区主要学生餐厅',
      aliases: ['五食', '第五食堂'],
    ),
    const CampusPoi(
      name: '思餐厅',
      campusId: 'jungong',
      location: LatLng(31.2895, 121.5535),
      category: CampusCategory.dining,
      subtitle: '特色小吃与风味快餐',
      aliases: ['思餐厅'],
    ),

    // ================= 军工路 516 号 / 1100 号：宿舍公寓 =================
    const CampusPoi(
      name: '第一学生公寓',
      campusId: 'jungong',
      location: LatLng(31.2898, 121.5542),
      category: CampusCategory.dorm,
      subtitle: '一公（南楼/北楼）',
      aliases: ['一公', '第一公寓'],
    ),
    const CampusPoi(
      name: '第二学生公寓',
      campusId: 'jungong',
      location: LatLng(31.2905, 121.5545),
      category: CampusCategory.dorm,
      subtitle: '二公（一/二/三号楼）',
      aliases: ['二公', '第二公寓', '二公一', '二公二', '二公三'],
    ),
    const CampusPoi(
      name: '第三学生公寓',
      campusId: 'jungong',
      location: LatLng(31.2912, 121.5548),
      category: CampusCategory.dorm,
      subtitle: '三公（一/二/三号楼）',
      aliases: ['三公', '第三公寓', '三公一'],
    ),
    const CampusPoi(
      name: '第四学生公寓',
      campusId: 'jungong',
      location: LatLng(31.2925, 121.5552),
      category: CampusCategory.dorm,
      subtitle: '四公（一/二/三/四号楼）',
      aliases: ['四公', '第四公寓'],
    ),
    const CampusPoi(
      name: '第五学生公寓',
      campusId: 'jungong',
      location: LatLng(31.2900, 121.5555),
      category: CampusCategory.dorm,
      subtitle: '五公（一/二/三/四号楼）',
      aliases: ['五公', '第五公寓'],
    ),
    const CampusPoi(
      name: '第六学生公寓',
      campusId: 'jungong',
      location: LatLng(31.2890, 121.5558),
      category: CampusCategory.dorm,
      subtitle: '六公（一/二/三号楼）',
      aliases: ['六公', '第六公寓'],
    ),
    const CampusPoi(
      name: '第七学生公寓',
      campusId: 'jungong',
      location: LatLng(31.2938, 121.5480),
      category: CampusCategory.dorm,
      subtitle: '七公',
      aliases: ['七公', '第七公寓'],
    ),

    // ================= 军工路：生活服务/超市/场馆/校门 =================
    const CampusPoi(
      name: '菜鸟驿站',
      campusId: 'jungong',
      location: LatLng(31.2908, 121.5508),
      category: CampusCategory.service,
      subtitle: '校园快递收发综合中心',
      aliases: ['菜鸟', '快递点', '快递站', '取快递'],
    ),
    const CampusPoi(
      name: '上海教育超市',
      campusId: 'jungong',
      location: LatLng(31.2912, 121.5528),
      category: CampusCategory.service,
      subtitle: '教超 · 校园便利店',
      aliases: ['教超', '教育超市', '超市'],
    ),
    const CampusPoi(
      name: '校门诊部',
      campusId: 'jungong',
      location: LatLng(31.2925, 121.5508),
      category: CampusCategory.service,
      subtitle: '校医院 · 保健科与医保挂号',
      aliases: ['校医院', '门诊部', '医院'],
    ),
    const CampusPoi(
      name: '思晏堂',
      campusId: 'jungong',
      location: LatLng(31.2920, 121.5545),
      category: CampusCategory.library,
      subtitle: '百年历史保护建筑 · 沪江大学标志',
      aliases: ['思晏堂'],
    ),
    const CampusPoi(
      name: '大礼堂',
      campusId: 'jungong',
      location: LatLng(31.2922, 121.5540),
      category: CampusCategory.sports,
      subtitle: '大礼堂 · 学术交流与大型晚会',
      aliases: ['大礼堂'],
    ),
    const CampusPoi(
      name: '毛主席像广场',
      campusId: 'jungong',
      location: LatLng(31.2918, 121.5538),
      category: CampusCategory.service,
      subtitle: '校园核心景观标志地',
      aliases: ['毛主席像', '大草坪'],
    ),
    const CampusPoi(
      name: '北区运动场',
      campusId: 'jungong',
      location: LatLng(31.2915, 121.5558),
      category: CampusCategory.sports,
      subtitle: '北操 · 标准田径场与足球场',
      aliases: ['北操', '北操场', '操场'],
    ),
    const CampusPoi(
      name: '南区运动场',
      campusId: 'jungong',
      location: LatLng(31.2878, 121.5540),
      category: CampusCategory.sports,
      subtitle: '南操 · 田径跑道与球场',
      aliases: ['南操', '南操场'],
    ),
    const CampusPoi(
      name: '体育健身中心',
      campusId: 'jungong',
      location: LatLng(31.2885, 121.5550),
      category: CampusCategory.sports,
      subtitle: '室内羽毛球/乒乓球/健身馆',
      aliases: ['体育馆', '健身中心'],
    ),
    const CampusPoi(
      name: '军工路516号主门',
      campusId: 'jungong',
      location: LatLng(31.2928, 121.5492),
      category: CampusCategory.gate,
      subtitle: '军工路本部正大门',
      aliases: ['正门', '主校门', '516门', '大门'],
    ),
    const CampusPoi(
      name: '海安路门（北门）',
      campusId: 'jungong',
      location: LatLng(31.2975, 121.5548),
      category: CampusCategory.gate,
      subtitle: '军工路校区北侧校门',
      aliases: ['北门', '海安路门'],
    ),

    // ================= 军工路 1100 号（基础教学园区） =================
    const CampusPoi(
      name: '1100号教学中心',
      campusId: 'jungong',
      location: LatLng(31.2828, 121.5575),
      category: CampusCategory.teaching,
      subtitle: '基础教学园区核心大楼',
      aliases: ['基础部教学楼', '南校教学楼', '1100号教学楼'],
    ),
    const CampusPoi(
      name: '基础部第四食堂',
      campusId: 'jungong',
      location: LatLng(31.2835, 121.5582),
      category: CampusCategory.dining,
      subtitle: '1100号基础教学园区主要食堂',
      aliases: ['四食', '第四食堂', '基础部食堂'],
    ),
    const CampusPoi(
      name: '军工路1100号大门',
      campusId: 'jungong',
      location: LatLng(31.2830, 121.5565),
      category: CampusCategory.gate,
      subtitle: '基础教学园区主入口',
      aliases: ['1100门', '1100号门', '南校门'],
    ),

    // ================= 复兴路校区 (SBC) =================
    const CampusPoi(
      name: '中英国际学院主楼',
      campusId: 'fuxing',
      location: LatLng(31.2140, 121.4588),
      category: CampusCategory.teaching,
      subtitle: '复兴路校区核心教学与行政大楼',
      aliases: ['SBC教学楼', '复兴楼', '中英学院'],
    ),
    const CampusPoi(
      name: '复兴路图书馆',
      campusId: 'fuxing',
      location: LatLng(31.2135, 121.4582),
      category: CampusCategory.library,
      subtitle: '复兴路校区专业图书分馆',
      aliases: ['复兴图书馆'],
    ),
    const CampusPoi(
      name: '复兴路校门（复兴中路1195号）',
      campusId: 'fuxing',
      location: LatLng(31.2145, 121.4590),
      category: CampusCategory.gate,
      subtitle: '复兴中路主入口（近陕西南路）',
      aliases: ['复兴路大门', 'SBC大门'],
    ),

    // ================= 营口路校区 =================
    const CampusPoi(
      name: '营口路教学综合楼',
      campusId: 'yingkou',
      location: LatLng(31.3085, 121.5368),
      category: CampusCategory.teaching,
      subtitle: '营口路校区主要教学与办公场所',
      aliases: ['营口路教学楼'],
    ),
    const CampusPoi(
      name: '营口路大门（营口路788号）',
      campusId: 'yingkou',
      location: LatLng(31.3080, 121.5358),
      category: CampusCategory.gate,
      subtitle: '营口路校区正门',
      aliases: ['营口路门', '营口路大门'],
    ),
  ];

  /// 根据教室字符串（如「三教106」）智能匹配 POI
  static CampusPoi? poiForRoom(String room) {
    final raw = room.trim();
    if (raw.isEmpty) return null;

    // 先走原有的别名系统
    final place = placeForRoom(raw);
    if (place != null) {
      for (final poi in pois) {
        if (poi.name == place.name || poi.aliases.contains(place.name)) {
          return poi;
        }
      }
    }

    // 模糊比对别名
    for (final poi in pois) {
      if (raw.contains(poi.name)) return poi;
      for (final a in poi.aliases) {
        if (raw.contains(a)) return poi;
      }
    }
    return null;
  }

  /// 搜索 POI，支持校区过滤与分类过滤
  static List<CampusPoi> search({
    required String query,
    String? campusId,
    CampusCategory? category,
  }) {
    final raw = query.trim();
    var list = pois;
    if (campusId != null && campusId.isNotEmpty) {
      list = list.where((p) => p.campusId == campusId).toList();
    }
    if (category != null && category != CampusCategory.all) {
      list = list.where((p) => p.category == category).toList();
    }

    if (raw.isEmpty) return list;

    final nQuery = normalizePlaceText(raw);
    final results = <({CampusPoi poi, int score})>[];

    for (final poi in list) {
      int? bestScore;
      for (final name in [poi.name, ...poi.aliases]) {
        final s = scorePlaceName(name, nQuery);
        if (s != null && (bestScore == null || s > bestScore)) {
          bestScore = s;
        }
      }
      if (bestScore != null) {
        results.add((poi: poi, score: bestScore));
      }
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results.map((e) => e.poi).toList();
  }

  /// 根据地理坐标定位距离最近的校区
  static Campus nearestCampus(LatLng location) {
    const distance = Distance();
    Campus best = jungong;
    double minMeters = double.infinity;
    for (final c in allCampuses) {
      final m = distance.as(LengthUnit.Meter, location, c.center);
      if (m < minMeters) {
        minMeters = m;
        best = c;
      }
    }
    return best;
  }
}
