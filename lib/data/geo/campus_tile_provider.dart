import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import 'available_tiles.dart';

/// 校园混合瓦片提供器：
/// 1. 优先秒开内置离线校区瓦片（assets/tiles/{z}_{x}_{y}.png），零网络、零延迟、离线可用；
/// 2. 若超出内置范围且网络可用，平滑回退至在线瓦片镜像。
class CampusOfflineTileProvider extends TileProvider {
  CampusOfflineTileProvider({super.headers});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final key = '${coordinates.z}_${coordinates.x}_${coordinates.y}';
    if (kAvailableTileKeys.contains(key)) {
      return AssetImage('assets/tiles/$key.png');
    }

    // 允许在线兜底加载周边地图
    final fallbackUrl = options.fallbackUrl != null
        ? getTileFallbackUrl(coordinates, options)!
        : 'https://tile.openstreetmap.de/${coordinates.z}/${coordinates.x}/${coordinates.y}.png';

    return NetworkImage(
      fallbackUrl,
      headers: <String, String>{
        'User-Agent': 'USST-App-CampusMap/1.0',
        ...headers,
      },
    );
  }
}
