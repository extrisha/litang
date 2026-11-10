import 'dart:math';

/// Ordered results with a fixed request budget. A failed task still lets the
/// other workers finish; callers decide how to preserve partial results.
Future<List<R>> mapWithConcurrency<T, R>(
  Iterable<T> values,
  Future<R> Function(T) task, {
  int limit = 3,
}) async {
  if (limit < 1) throw ArgumentError.value(limit, 'limit');
  final items = values.toList();
  final results = List<R?>.filled(items.length, null);
  var next = 0;
  Object? firstError;
  StackTrace? firstStack;
  Future<void> worker() async {
    while (next < items.length) {
      final index = next++;
      try {
        results[index] = await task(items[index]);
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
  }

  await Future.wait(List.generate(min(limit, items.length), (_) => worker()));
  if (firstError != null) Error.throwWithStackTrace(firstError!, firstStack!);
  return results.cast<R>();
}

class CourseBatch<T> {
  CourseBatch(this.successful, this.failed);
  final Map<String, List<T>> successful;
  final Map<String, String> failed;
  bool get complete => failed.isEmpty;
  List<T> get values => successful.values.expand((v) => v).toList();

  List<T> requireComplete() {
    if (!complete) throw StateError('部分课程未更新：${failed.values.join('、')}');
    return values;
  }

  /// A successful empty response clears that course. Only failed courses keep
  /// their old items and original fetchedAt/deadlineAt.
  List<T> merge(List<T> previous, String Function(T) courseKey) => [
    ...values,
    ...previous.where((item) => failed.containsKey(courseKey(item))),
  ];

  static Future<CourseBatch<R>> fetch<T, R>(
    List<T> items, {
    required String Function(T) key,
    required String Function(T) name,
    required Future<List<R>> Function(T) task,
    int limit = 3,
  }) async {
    final results = await mapWithConcurrency(items, (item) async {
      try {
        return (key: key(item), name: name(item), data: await task(item));
      } catch (_) {
        return (key: key(item), name: name(item), data: null);
      }
    }, limit: limit);
    return CourseBatch(
      {
        for (final r in results)
          if (r.data != null) r.key: r.data!,
      },
      {
        for (final r in results)
          if (r.data == null) r.key: r.name,
      },
    );
  }
}
