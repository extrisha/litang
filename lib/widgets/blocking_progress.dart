import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';

/// 当前是否已有一个遮罩在显示。
///
/// 连点很容易触发两次「打开网页端」之类的操作，叠出两个 `barrierDismissible: false`
/// 的遮罩；之后两次 `pop` 会把路由栈弹错——最坏情况下把页面本身弹掉。
bool _progressVisible = false;

/// 在「不可取消的遮罩」下执行一段异步任务，无论成功、失败还是抛异常，
/// 都保证遮罩被关掉。
///
/// 之前两个页面都是「先 showDialog 再 await」，没有 finally：一旦任务抛异常，
/// 这个不可取消的遮罩就永久留在屏幕上，页面点不动也退不出去。
Future<T> runWithBlockingProgress<T>(
  BuildContext context,
  String message,
  Future<T> Function() task,
) async {
  // 没有 context 可用时就不弹遮罩，直接跑任务
  if (!context.mounted) return task();

  // 已经有一个遮罩：绝不再叠一个
  if (_progressVisible) return task();

  _progressVisible = true;
  try {
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.usstRed,
                  ),
                  const SizedBox(width: 16),
                  Text(message, style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // 等一帧，确保遮罩已经压到路由栈上
    await Future<void>.delayed(Duration.zero);
    return await task();
  } finally {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    _progressVisible = false;
  }
}
