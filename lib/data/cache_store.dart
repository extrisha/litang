import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// 一份缓存记录：数据 + 写入时间。
class CacheEntry {
  const CacheEntry({required this.data, required this.savedAt});

  final Object? data;
  final DateTime savedAt;

  Duration get age => DateTime.now().difference(savedAt);

  bool isFresh(Duration ttl) => age < ttl;

  bool isStale(Duration ttl) => !isFresh(ttl);
}

/// 统一的本地缓存。
///
/// 一个 key 对应一份 JSON，外面包一层 `{savedAt, data}`，
/// 这样调用方既能直接拿数据，也能判断"过期多久了"，做缓存优先 + 后台刷新。
///
/// 两种后端：
///   - 默认落到 `<应用目录>/cache/<key>.json`（课程名、列表这类非敏感数据）；
///   - `secure: true` 走 flutter_secure_storage（课表这类个人数据，Keystore 加密）。
///
/// 兼容旧缓存：以前的格式是"整个 JSON 就是数据、没有时间戳"，读取时会当成
/// `savedAt = 1970`（能用但一定算过期），下次写入自动升级成新格式。
class CacheStore {
  CacheStore._();

  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  /// 进程内一级缓存，避免反复读磁盘 / Keystore。
  static final Map<String, CacheEntry> _memory = <String, CacheEntry>{};

  /// 单测里替换目录用。
  @visibleForTesting
  static Future<Directory> Function()? directoryOverride;

  static Future<Directory> _dir() async {
    final override = directoryOverride;
    final base = override != null
        ? await override()
        : await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<File> _file(String key) async {
    final dir = await _dir();
    final safe = key.replaceAll(RegExp(r'[^0-9A-Za-z_.-]'), '_');
    return File('${dir.path}/$safe.json');
  }

  static String _memoryKey(String key, bool secure) =>
      '${secure ? 's' : 'f'}:$key';

  /// 读缓存。没有则返回 null。
  static Future<CacheEntry?> read(String key, {bool secure = false}) async {
    final cached = _memory[_memoryKey(key, secure)];
    if (cached != null) return cached;
    try {
      final raw = secure ? await _secure.read(key: key) : await _readFile(key);
      if (raw == null || raw.isEmpty) return null;
      final entry = decode(raw);
      if (entry != null) {
        _memory[_memoryKey(key, secure)] = entry;
      }
      return entry;
    } catch (_) {
      return null;
    }
  }

  /// 读原始字符串，不做 JSON 解析。
  ///
  /// 大对象（例如几 MB 的通知 feed）解析很吃 CPU，调用方可以拿原始字符串
  /// 丢进 `compute()` 到后台 isolate 解析，避免卡住 UI 线程。
  static Future<String?> readRaw(String key, {bool secure = false}) async {
    try {
      return secure ? await _secure.read(key: key) : await _readFile(key);
    } catch (_) {
      return null;
    }
  }

  /// 写缓存。[data] 必须能 jsonEncode。
  static Future<void> write(
    String key,
    Object data, {
    bool secure = false,
  }) async {
    final now = DateTime.now();
    _memory[_memoryKey(key, secure)] = CacheEntry(data: data, savedAt: now);
    try {
      final raw = encode(data, now);
      if (secure) {
        await _secure.write(key: key, value: raw);
      } else {
        final file = await _file(key);
        await file.writeAsString(raw, flush: true);
      }
    } catch (_) {
      // 缓存失败不影响功能
    }
  }

  static Future<void> remove(String key, {bool secure = false}) async {
    _memory.remove(_memoryKey(key, secure));
    try {
      if (secure) {
        await _secure.delete(key: key);
      } else {
        final file = await _file(key);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (_) {
      // 忽略
    }
  }

  /// 只清内存（测试用）。
  @visibleForTesting
  static void clearMemory() => _memory.clear();

  static Future<String?> _readFile(String key) async {
    final file = await _file(key);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  /// 序列化成 `{savedAt, data}`。
  @visibleForTesting
  static String encode(Object data, DateTime savedAt) => jsonEncode(
    <String, dynamic>{'savedAt': savedAt.toIso8601String(), 'data': data},
  );

  /// 解析缓存内容，兼容"没有时间戳"的旧格式。
  ///
  /// 公开是因为调用方可能把「读原始字符串 + 解析」分两步，
  /// 中间那步丢给 `compute()` 到后台 isolate 执行。
  static CacheEntry? decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> &&
          decoded.containsKey('data') &&
          decoded['savedAt'] is String) {
        final savedAt = DateTime.tryParse(decoded['savedAt'] as String);
        if (savedAt != null) {
          return CacheEntry(data: decoded['data'], savedAt: savedAt);
        }
      }
      // 旧格式：整个 JSON 就是数据，时间当作很久以前
      return CacheEntry(
        data: decoded,
        savedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
    } catch (_) {
      return null;
    }
  }
}
