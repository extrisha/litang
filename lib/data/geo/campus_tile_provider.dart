import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import 'available_tiles.dart';

/// 校园混合瓦片提供器：
/// 1. 优先使用内置离线校区瓦片（assets/tiles/{z}_{x}_{y}.png），100% 离线、零延迟；
/// 2. 若超出内置瓦片范围（或深层放大到 19 级），在线时平滑调用国内极速图层，绝不白屏。
class CampusOfflineTileProvider extends TileProvider {
  CampusOfflineTileProvider({super.headers});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final key = '${coordinates.z}_${coordinates.x}_${coordinates.y}';
    if (kAvailableTileKeys.contains(key)) {
      return AssetImage('assets/tiles/$key.png');
    }

    // 在线时使用高德地图国内极速图层，确保深层缩放（z=19）和周边区域绝不卡白块
    final fallbackUrl =
        'https://webrd01.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x=${coordinates.x}&y=${coordinates.y}&z=${coordinates.z}';

    return NetworkImage(
      fallbackUrl,
      headers: <String, String>{
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        ...headers,
      },
    );
  }
}
