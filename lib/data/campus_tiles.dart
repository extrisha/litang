// 0.4.0 官方示意图拆成的 30 块 1024px 瓦片，以及它们在地图上的经纬度范围。
// 由 tools/map/georef_campus_map.py 生成，勿手改。
// 轴对齐变换保证相邻瓦片严格共边（脚本内有断言自检）。

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class CampusTile {
  const CampusTile({
    required this.asset,
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final String asset;
  final double south;
  final double west;
  final double north;
  final double east;

  LatLngBounds get bounds =>
      LatLngBounds(LatLng(south, west), LatLng(north, east));
}

const List<CampusTile> kCampusTiles = <CampusTile>[
  CampusTile(
    asset: 'assets/map/base_r0_c0.webp',
    south: 31.2982170,
    west: 121.5454077,
    north: 31.3005421,
    east: 121.5479299,
  ),
  CampusTile(
    asset: 'assets/map/base_r0_c1.webp',
    south: 31.2982170,
    west: 121.5479299,
    north: 31.3005421,
    east: 121.5504521,
  ),
  CampusTile(
    asset: 'assets/map/base_r0_c2.webp',
    south: 31.2982170,
    west: 121.5504521,
    north: 31.3005421,
    east: 121.5529744,
  ),
  CampusTile(
    asset: 'assets/map/base_r0_c3.webp',
    south: 31.2982170,
    west: 121.5529744,
    north: 31.3005421,
    east: 121.5554966,
  ),
  CampusTile(
    asset: 'assets/map/base_r0_c4.webp',
    south: 31.2982170,
    west: 121.5554966,
    north: 31.3005421,
    east: 121.5564917,
  ),
  CampusTile(
    asset: 'assets/map/base_r1_c0.webp',
    south: 31.2958918,
    west: 121.5454077,
    north: 31.2982170,
    east: 121.5479299,
  ),
  CampusTile(
    asset: 'assets/map/base_r1_c1.webp',
    south: 31.2958918,
    west: 121.5479299,
    north: 31.2982170,
    east: 121.5504521,
  ),
  CampusTile(
    asset: 'assets/map/base_r1_c2.webp',
    south: 31.2958918,
    west: 121.5504521,
    north: 31.2982170,
    east: 121.5529744,
  ),
  CampusTile(
    asset: 'assets/map/base_r1_c3.webp',
    south: 31.2958918,
    west: 121.5529744,
    north: 31.2982170,
    east: 121.5554966,
  ),
  CampusTile(
    asset: 'assets/map/base_r1_c4.webp',
    south: 31.2958918,
    west: 121.5554966,
    north: 31.2982170,
    east: 121.5564917,
  ),
  CampusTile(
    asset: 'assets/map/base_r2_c0.webp',
    south: 31.2935667,
    west: 121.5454077,
    north: 31.2958918,
    east: 121.5479299,
  ),
  CampusTile(
    asset: 'assets/map/base_r2_c1.webp',
    south: 31.2935667,
    west: 121.5479299,
    north: 31.2958918,
    east: 121.5504521,
  ),
  CampusTile(
    asset: 'assets/map/base_r2_c2.webp',
    south: 31.2935667,
    west: 121.5504521,
    north: 31.2958918,
    east: 121.5529744,
  ),
  CampusTile(
    asset: 'assets/map/base_r2_c3.webp',
    south: 31.2935667,
    west: 121.5529744,
    north: 31.2958918,
    east: 121.5554966,
  ),
  CampusTile(
    asset: 'assets/map/base_r2_c4.webp',
    south: 31.2935667,
    west: 121.5554966,
    north: 31.2958918,
    east: 121.5564917,
  ),
  CampusTile(
    asset: 'assets/map/base_r3_c0.webp',
    south: 31.2912416,
    west: 121.5454077,
    north: 31.2935667,
    east: 121.5479299,
  ),
  CampusTile(
    asset: 'assets/map/base_r3_c1.webp',
    south: 31.2912416,
    west: 121.5479299,
    north: 31.2935667,
    east: 121.5504521,
  ),
  CampusTile(
    asset: 'assets/map/base_r3_c2.webp',
    south: 31.2912416,
    west: 121.5504521,
    north: 31.2935667,
    east: 121.5529744,
  ),
  CampusTile(
    asset: 'assets/map/base_r3_c3.webp',
    south: 31.2912416,
    west: 121.5529744,
    north: 31.2935667,
    east: 121.5554966,
  ),
  CampusTile(
    asset: 'assets/map/base_r3_c4.webp',
    south: 31.2912416,
    west: 121.5554966,
    north: 31.2935667,
    east: 121.5564917,
  ),
  CampusTile(
    asset: 'assets/map/base_r4_c0.webp',
    south: 31.2889164,
    west: 121.5454077,
    north: 31.2912416,
    east: 121.5479299,
  ),
  CampusTile(
    asset: 'assets/map/base_r4_c1.webp',
    south: 31.2889164,
    west: 121.5479299,
    north: 31.2912416,
    east: 121.5504521,
  ),
  CampusTile(
    asset: 'assets/map/base_r4_c2.webp',
    south: 31.2889164,
    west: 121.5504521,
    north: 31.2912416,
    east: 121.5529744,
  ),
  CampusTile(
    asset: 'assets/map/base_r4_c3.webp',
    south: 31.2889164,
    west: 121.5529744,
    north: 31.2912416,
    east: 121.5554966,
  ),
  CampusTile(
    asset: 'assets/map/base_r4_c4.webp',
    south: 31.2889164,
    west: 121.5554966,
    north: 31.2912416,
    east: 121.5564917,
  ),
  CampusTile(
    asset: 'assets/map/base_r5_c0.webp',
    south: 31.2883942,
    west: 121.5454077,
    north: 31.2889164,
    east: 121.5479299,
  ),
  CampusTile(
    asset: 'assets/map/base_r5_c1.webp',
    south: 31.2883942,
    west: 121.5479299,
    north: 31.2889164,
    east: 121.5504521,
  ),
  CampusTile(
    asset: 'assets/map/base_r5_c2.webp',
    south: 31.2883942,
    west: 121.5504521,
    north: 31.2889164,
    east: 121.5529744,
  ),
  CampusTile(
    asset: 'assets/map/base_r5_c3.webp',
    south: 31.2883942,
    west: 121.5529744,
    north: 31.2889164,
    east: 121.5554966,
  ),
  CampusTile(
    asset: 'assets/map/base_r5_c4.webp',
    south: 31.2883942,
    west: 121.5554966,
    north: 31.2889164,
    east: 121.5564917,
  ),
];
