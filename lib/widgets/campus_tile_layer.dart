import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/campus_tiles.dart';

/// 根据视口选择瓦片和解码尺寸，避免一次把整张 4500×5350 底图解码进内存。
class CampusTileLayer extends StatefulWidget {
  const CampusTileLayer({super.key});

  static int decodeWidth(double physicalPixels) {
    if (physicalPixels <= 256) return 256;
    if (physicalPixels <= 512) return 512;
    return 1024;
  }

  static List<CampusTile> visibleTiles(LatLngBounds bounds) {
    final latPad = (bounds.north - bounds.south) * 0.15;
    final lngPad = (bounds.east - bounds.west) * 0.15;
    final padded = LatLngBounds(
      LatLng(bounds.south - latPad, bounds.west - lngPad),
      LatLng(bounds.north + latPad, bounds.east + lngPad),
    );
    return kCampusTiles
        .where((tile) => tile.bounds.isOverlapping(padded))
        .toList();
  }

  @override
  State<CampusTileLayer> createState() => _CampusTileLayerState();
}

class _CampusTileLayerState extends State<CampusTileLayer> {
  final Map<String, ImageProvider> _providers = {};

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final active = <String>{};
    final images = <OverlayImage>[];
    for (final tile in CampusTileLayer.visibleTiles(camera.visibleBounds)) {
      final pixels =
          (camera.projectAtZoom(LatLng(tile.north, tile.east)).dx -
                  camera.projectAtZoom(LatLng(tile.north, tile.west)).dx)
              .abs() *
          ratio;
      final width = CampusTileLayer.decodeWidth(pixels);
      final key = '${tile.asset}:$width';
      active.add(key);
      final provider = _providers.putIfAbsent(
        key,
        () => ResizeImage(
          AssetImage(tile.asset),
          width: width,
          allowUpscaling: false,
        ),
      );
      images.add(
        OverlayImage(
          bounds: tile.bounds,
          imageProvider: provider,
          filterQuality: FilterQuality.medium,
        ),
      );
    }
    final retired = _providers.keys
        .where((key) => !active.contains(key))
        .toList();
    for (final key in retired) {
      final provider = _providers.remove(key)!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_providers.containsKey(key)) unawaited(provider.evict());
      });
    }
    return OverlayImageLayer(overlayImages: images);
  }

  @override
  void dispose() {
    for (final provider in _providers.values) {
      unawaited(provider.evict());
    }
    _providers.clear();
    super.dispose();
  }
}
