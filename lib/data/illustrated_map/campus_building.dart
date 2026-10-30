import 'package:flutter/material.dart';

import '../geo/campus_config.dart';

/// 校园手绘图模式：2D 平面 vs 2.5D 立体鸟瞰
enum MapViewMode {
  flat(label: '2D 平面', icon: Icons.layers_outlined),
  isometric(label: '2.5D 鸟瞰', icon: Icons.view_in_ar_outlined);

  const MapViewMode({required this.label, required this.icon});
  final String label;
  final IconData icon;
}

/// 校园手绘/矢量建筑实体
class CampusBuilding {
  const CampusBuilding({
    required this.id,
    required this.code,
    required this.name,
    required this.category,
    required this.floors,
    required this.flatPolygon,
    required this.flatLabel,
    required this.isoPolygon,
    required this.isoLabel,
    required this.drawOrder,
    this.aliases = const <String>[],
  });

  final String id;
  final String code;
  final String name;
  final String category;
  final int floors;
  final List<Offset> flatPolygon;
  final Offset flatLabel;
  final List<Offset> isoPolygon;
  final Offset isoLabel;
  final int drawOrder;
  final List<String> aliases;

  /// 对应的全局场所大类
  CampusCategory get campusCategory {
    switch (category) {
      case '教学楼':
        return CampusCategory.teaching;
      case '宿舍':
        return CampusCategory.dorm;
      case '食堂':
        return CampusCategory.dining;
      case '图书馆':
      case '历史建筑':
        return CampusCategory.library;
      case '体育馆':
      case '运动场':
      case '球场':
        return CampusCategory.sports;
      case '校门':
        return CampusCategory.gate;
      case '生活服务':
      case '行政':
      case '天桥':
      case '园林':
      default:
        return CampusCategory.service;
    }
  }

  /// 获取当前视图模式下的多边形点序列
  List<Offset> polygonFor(MapViewMode mode) {
    return mode == MapViewMode.flat ? flatPolygon : isoPolygon;
  }

  /// 获取当前视图模式下的文字标签锚点
  Offset labelFor(MapViewMode mode) {
    return mode == MapViewMode.flat ? flatLabel : isoLabel;
  }

  /// 构建物理尺寸下的绘制 Path
  Path toPath(Size mapSize, MapViewMode mode) {
    final points = polygonFor(mode);
    final path = Path();
    if (points.isEmpty) return path;

    path.moveTo(points[0].dx * mapSize.width, points[0].dy * mapSize.height);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx * mapSize.width, points[i].dy * mapSize.height);
    }
    path.close();
    return path;
  }

  /// 点选碰撞检测
  bool hitTest(Offset localPos, Size mapSize, MapViewMode mode) {
    final points = polygonFor(mode);
    if (points.isEmpty) return false;

    // 快速 AABB 矩形过滤
    double minX = 1.0, maxX = 0.0, minY = 1.0, maxY = 0.0;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }

    final nx = localPos.dx / mapSize.width;
    final ny = localPos.dy / mapSize.height;
    if (nx < minX || nx > maxX || ny < minY || ny > maxY) {
      return false;
    }

    // 精确射线交叉法检测多边形内部
    var inside = false;
    for (int i = 0, j = points.length - 1; i < points.length; j = i++) {
      final xi = points[i].dx, yi = points[i].dy;
      final xj = points[j].dx, yj = points[j].dy;

      final intersect = ((yi > ny) != (yj > ny)) &&
          (nx < (xj - xi) * (ny - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }
}
