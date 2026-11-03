import 'package:flutter/foundation.dart';

import 'campus_places.dart';

/// 跨页面请求地图定位到某个地点。
///
/// 只携带地点名与它在官方示意图上的归一化锚点，
/// 具体落在哪个可搜索实体由地图页解析。
class MapFocus {
  MapFocus._();

  static final ValueNotifier<CampusPlace?> target = ValueNotifier<CampusPlace?>(
    null,
  );

  static void focus(CampusPlace place) {
    target.value = place;
  }

  static void consume() {
    target.value = null;
  }
}
