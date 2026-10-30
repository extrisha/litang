import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../campus_places.dart';
import '../geo/campus_config.dart';

/// 建筑物或景观的几何多边形实体
class VectorFeature {
  const VectorFeature({
    required this.id,
    required this.name,
    required this.campusId,
    required this.points,
    required this.center,
  });

  final String id;
  final String name;
  final String campusId;
  final List<LatLng> points;
  final LatLng center;
}

/// 建筑出入口模型（为就近教室导航、无障碍坡道、单车停靠准备）
class BuildingEntrance {
  const BuildingEntrance({
    required this.id,
    required this.name,
    required this.location,
    this.nearbyRooms = const <String>[],
    this.bikeAllowed = true,
    this.hasStairs = false,
  });

  final String id;
  final String name; // 例如 "一教正门(南)", "卓越楼西侧坡道入口"
  final LatLng location;
  final List<String> nearbyRooms; // 靠近该门进入的教室或教室前缀
  final bool bikeAllowed; // 是否允许推车/骑行
  final bool hasStairs; // 是否有台阶 (用于无障碍导航)
}

/// 建筑物矢量特征（包含轮廓多边形、中心点、分类、别名与出入口列表）
class BuildingFeature extends VectorFeature {
  const BuildingFeature({
    required super.id,
    required super.name,
    required super.campusId,
    required super.points,
    required super.center,
    required this.category,
    this.aliases = const <String>[],
    this.entrances = const <BuildingEntrance>[],
    this.subtitle,
    this.importance = 1, // 1: 常规, 2: 核心地标(低缩放层级可见)
  });

  final CampusCategory category;
  final List<String> aliases;
  final List<BuildingEntrance> entrances;
  final String? subtitle;
  final int importance;

  CampusPoi toPoi() {
    return CampusPoi(
      name: name,
      campusId: campusId,
      location: center,
      category: category,
      subtitle: subtitle,
      aliases: aliases,
    );
  }

  CampusPlace toPlace() {
    return CampusPlace(name: name, anchor: Offset.zero);
  }
}

/// 地形地貌类型（校园围墙轮廓、水系、草坪绿化、跑道运动场等）
enum GroundType {
  campusGround, // 校园红线范围
  water,        // 黄浦江或校园内河
  lawn,         // 绿地草坪
  sportsTrack,  // 跑道体育场
}

/// 地貌景观实体
class GroundFeature extends VectorFeature {
  const GroundFeature({
    required super.id,
    required super.name,
    required super.campusId,
    required super.points,
    required super.center,
    required this.type,
  });

  final GroundType type;
}

/// 校园主干道与步行路段（为老生加权寻路、林荫道、无障碍导航铺路）
class RoadFeature {
  const RoadFeature({
    required this.id,
    required this.name,
    required this.campusId,
    required this.points,
    this.bikeAllowed = true,
    this.hasShade = false,
    this.isMainRoad = false,
  });

  final String id;
  final String name;
  final String campusId;
  final List<LatLng> points;
  final bool bikeAllowed;
  final bool hasShade;
  final bool isMainRoad;
}
