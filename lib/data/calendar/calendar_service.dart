import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../http/api_client.dart';

import 'academic_calendar.dart';

/// 学年/学期配置。与版本更新分离，失败时用本地缓存或内置 asset。
class CalendarService {
  CalendarService._();

  static final CalendarService instance = CalendarService._();

  /// 独立校历仓库；没有这个仓库时直接用内置 asset。
  static const String _githubBase =
      'https://raw.githubusercontent.com/extrisha/lit-Calendar/main';
  static const String _giteeBase =
      'https://gitee.com/extrisha/lit-Calendar/raw/main';

  final ValueNotifier<AcademicCalendar?> notifier =
      ValueNotifier<AcademicCalendar?>(null);

  AcademicCalendar? get calendar => notifier.value;

  AcademicTerm? get currentTerm => calendar?.currentTerm;

  int? get currentWeek => calendar?.currentWeek;

  String get termLabel => currentTerm?.label ?? '';

  String get termId => currentTerm?.id ?? '';

  static String fallbackTermId([DateTime? date]) {
    return AcademicCalendar.fallbackTermId(date ?? DateTime.now());
  }

  Future<void> load({bool refreshRemote = true}) async {
    final cached = await _readCache();
    final asset = cached ?? await _readAsset();
    notifier.value = asset;
    if (refreshRemote) unawaited(_refreshRemote());
  }

  Future<AcademicCalendar?> _readAsset() async {
    try {
      final raw = await rootBundle.loadString('assets/calendar.config');
      return AcademicCalendar.fromYaml(raw);
    } catch (_) {
      return null;
    }
  }

  Future<File?> _cacheFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/calendar.config');
    } catch (_) {
      return null;
    }
  }

  Future<AcademicCalendar?> _readCache() async {
    try {
      final file = await _cacheFile();
      if (file == null || !await file.exists()) return null;
      return AcademicCalendar.fromYaml(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<void> _refreshRemote() async {
    final year = _academicYearForNow();
    final fileName = '$year.config';
    for (final url in <String>[
      '$_githubBase/$fileName',
      '$_giteeBase/$fileName?download=1',
    ]) {
      try {
        final response = await ApiClient.dio.get<String>(
          url,
          options: Options(
            headers: <String, String>{'User-Agent': 'Litang-Calendar'},
            responseType: ResponseType.plain,
            receiveTimeout: const Duration(seconds: 12),
          ),
        );
        if ((response.statusCode ?? 0) != 200 || response.data == null) {
          continue;
        }
        final calendar = AcademicCalendar.fromYaml(response.data!);
        if (calendar == null) continue;
        notifier.value = calendar;
        await _saveCache(response.data!);
        return;
      } catch (_) {
        // 换下一个源
      }
    }
  }

  Future<void> _saveCache(String raw) async {
    try {
      final file = await _cacheFile();
      await file?.writeAsString(raw, flush: true);
    } catch (_) {
      // 缓存失败不影响使用
    }
  }

  /// 8 月及以后算新学年，例如 2026-10 取 2026-2027。
  static String _academicYearForNow() {
    final now = DateTime.now();
    final start = now.month >= 8 ? now.year : now.year - 1;
    return '$start-${start + 1}';
  }
}
