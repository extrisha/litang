import 'package:flutter/material.dart';

/// 输入数字口令的对话框。
///
/// 原先的写法在 `showDialog` 返回后立刻 `controller.dispose()`，而 dialog 的
/// 退场动画期间 `TextField` 仍然存活，会访问已释放的 controller
/// （`TextEditingController used after being disposed`）。
class SignNumberDialog extends StatefulWidget {
  const SignNumberDialog({super.key, required this.courseName});

  final String courseName;

  @override
  State<SignNumberDialog> createState() => SignNumberDialogState();
}

class SignNumberDialogState extends State<SignNumberDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.courseName} · 数字口令'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(
          hintText: '输入老师给出的签到口令',
          border: OutlineInputBorder(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('签到')),
      ],
    );
  }
}
