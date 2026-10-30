import '../geo/campus_config.dart';
import 'models.dart';
import 'vector_data_1100.dart';
import 'vector_data_516.dart';
import 'vector_data_fuxing.dart';
import 'vector_data_yingkou.dart';

/// 校园原生矢量地图数据聚合仓储
class VectorCampusRepository {
  VectorCampusRepository._();

  static final List<BuildingFeature> allBuildings = <BuildingFeature>[
    ...VectorData516.buildings,
    ...VectorData1100.buildings,
    ...VectorDataFuxing.buildings,
    ...VectorDataYingkou.buildings,
  ];

  static final List<GroundFeature> allGrounds = <GroundFeature>[
    ...VectorData516.grounds,
    ...VectorData1100.grounds,
    ...VectorDataFuxing.grounds,
    ...VectorDataYingkou.grounds,
  ];

  /// 根据校区 ID 获取该校区的所有地貌与水系多边形
  static List<GroundFeature> groundsForCampus(String campusId) {
    return allGrounds.where((g) => g.campusId == campusId).toList();
  }

  /// 根据校区 ID 与分类筛选建筑物
  static List<BuildingFeature> buildingsForCampus(
    String campusId, {
    CampusCategory category = CampusCategory.all,
  }) {
    return allBuildings.where((b) {
      if (b.campusId != campusId) return false;
      if (category != CampusCategory.all && b.category != category) return false;
      return true;
    }).toList();
  }

  /// 综合搜索（支持名称、别名、教室号模糊匹配）
  static List<BuildingFeature> search({
    required String query,
    String? campusId,
    CampusCategory category = CampusCategory.all,
  }) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return campusId != null
          ? buildingsForCampus(campusId, category: category)
          : allBuildings;
    }

    return allBuildings.where((b) {
      if (campusId != null && b.campusId != campusId) return false;
      if (category != CampusCategory.all && b.category != category) return false;

      final nameMatch = b.name.toLowerCase().contains(q);
      final aliasMatch = b.aliases.any((a) => a.toLowerCase().contains(q));
      final entranceMatch = b.entrances.any(
        (e) =>
            e.name.toLowerCase().contains(q) ||
            e.nearbyRooms.any((r) => r.toLowerCase().contains(q)),
      );

      return nameMatch || aliasMatch || entranceMatch;
    }).toList();
  }

  /// 将教室名智能解析为对应的建筑矢量实体（如 "一教106" -> 第一教学楼）
  static BuildingFeature? buildingForRoom(String room) {
    final raw = room.trim();
    if (raw.isEmpty) return null;

    // 1. 完全匹配或别名匹配
    for (final b in allBuildings) {
      if (b.name == raw || b.aliases.contains(raw)) return b;
    }

    // 2. 包含匹配
    for (final b in allBuildings) {
      if (b.name.length >= 2 && raw.contains(b.name)) return b;
      for (final a in b.aliases) {
        if (a.length >= 2 && raw.contains(a)) return b;
      }
    }

    // 3. 数字几教规则 ("一教", "二教", "三教", "四教")
    final m = RegExp(r'([一二三四五六七八九十1-9])\s*教').firstMatch(raw);
    if (m != null) {
      final key = m.group(1);
      for (final b in allBuildings) {
        if (b.name.contains(key!) || b.aliases.any((a) => a.contains(key))) {
          return b;
        }
      }
    }

    // 4. 常见简称字典
    const aliasMap = <String, String>{
      '卓越': '卓越楼',
      '图文': '图文信息中心',
      '图书': '图文信息中心',
      '综合': '综合楼',
      '经管': '经管楼',
      '国合': '国合楼',
      '中德': '国合楼',
      '先进制造': '先进制造大楼',
      '体育': '体育健身中心',
      '光电': '光电大楼',
      '材料': '材料与化学学院',
      '能动': '动力馆',
    };

    for (final entry in aliasMap.entries) {
      if (raw.contains(entry.key)) {
        for (final b in allBuildings) {
          if (b.name.contains(entry.value)) return b;
        }
      }
    }

    return null;
  }
}
