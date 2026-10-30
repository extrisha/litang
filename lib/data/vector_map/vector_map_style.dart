import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../geo/campus_config.dart';

/// 矢量地图专属莫兰迪配色与视觉样式系统
class VectorMapStyle {
  VectorMapStyle._();

  // 背景地貌
  static const Color mapBackground = Color(0xFFF2F4F8); // 视口外默认中性浅灰底
  static const Color campusGroundFill = Color(0xFFF9FAF8); // 校园红线内暖白地坪
  static const Color campusGroundStroke = Color(0xFFE2E4DE); // 校园外围边界轮廓

  static const Color waterFill = Color(0xFFD6EAF8); // 黄浦江/内河水系
  static const Color waterStroke = Color(0xFFBCE0FD);

  static const Color lawnFill = Color(0xFFEAF5EB); // 绿地草坪大草坪
  static const Color lawnStroke = Color(0xFFD4E9D6);

  static const Color sportsTrackFill = Color(0xFFFCEAE8); // 田径跑道赤土红
  static const Color sportsTrackStroke = Color(0xFFF3C8C4);

  // 建筑多边形颜色 (按建筑类别区分)
  static Color buildingFill(CampusCategory category) {
    switch (category) {
      case CampusCategory.teaching:
        return const Color(0xFFFFF2EF); // 教学楼：温润上理薄樱红底
      case CampusCategory.dorm:
        return const Color(0xFFF4F6FD); // 宿舍：淡青黛蓝
      case CampusCategory.dining:
        return const Color(0xFFFFF8EC); // 食堂：暖杏暖黄
      case CampusCategory.library:
        return const Color(0xFFEFF9F8); // 图书馆/实验楼：浅湖青
      case CampusCategory.sports:
        return const Color(0xFFF8F5FF); // 体育场馆：薰衣草浅紫
      case CampusCategory.service:
        return const Color(0xFFFBFBFB); // 生活服务/驿站
      case CampusCategory.gate:
        return const Color(0xFFFFF1F0);
      case CampusCategory.all:
        return const Color(0xFFF7F8FA);
    }
  }

  static Color buildingStroke(CampusCategory category) {
    switch (category) {
      case CampusCategory.teaching:
        return const Color(0xFFE8C7C2);
      case CampusCategory.dorm:
        return const Color(0xFFCAD4EB);
      case CampusCategory.dining:
        return const Color(0xFFEDD6B1);
      case CampusCategory.library:
        return const Color(0xFFBEE4DF);
      case CampusCategory.sports:
        return const Color(0xFFDAC7F8);
      default:
        return const Color(0xFFD5D9E0);
    }
  }

  // 选中态高亮
  static const Color selectedBuildingFill = Color(0xFFFFECEB);
  static const Color selectedBuildingStroke = AppColors.usstRed;
  static const double selectedStrokeWidth = 2.4;

  // 默认描边宽度
  static const double defaultStrokeWidth = 0.9;
}
