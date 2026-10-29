import 'package:flutter/foundation.dart';

import 'campus_places.dart';
import 'geo/campus_config.dart';

/// 跨页面请求地图定位到某个地点。
class MapFocus {
  MapFocus._();

  static final ValueNotifier<CampusPlace?> target = ValueNotifier<CampusPlace?>(
    null,
  );

  static final ValueNotifier<CampusPoi?> targetPoi = ValueNotifier<CampusPoi?>(
    null,
  );

  static void focus(CampusPlace place) {
    target.value = place;
    targetPoi.value = CampusData.poiForRoom(place.name) ??
        CampusData.search(query: place.name).firstOrNull;
  }

  static void focusPoi(CampusPoi poi) {
    targetPoi.value = poi;
    target.value = poi.toCampusPlace();
  }

  static void consume() {
    target.value = null;
    targetPoi.value = null;
  }
}
