import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../data/auth/sport_campus_auth.dart';

/// 首次绑定高校体育账号（校园跑次数）。
///
/// 账号体系和教务那套完全无关：这里是**手机号 + 密码**，
/// 也就是「高校体育」App 里的登录账号，不是学号、不走统一身份认证。
class SportCampusLoginPage extends StatefulWidget {
  const SportCampusLoginPage({super.key});

  @override
  State<SportCampusLoginPage> createState() => _SportCampusLoginPageState();
}

class _SportCampusLoginPageState extends State<SportCampusLoginPage> {
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _busy = false;
  String? _error;
  bool _remember = true;

  @override
  void dispose() {
    _mobileController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    final mobile = _mobileController.text.trim();
    final password = _passwordController.text;
    if (mobile.isEmpty || password.isEmpty) {
      setState(() => _error = '请填写手机号和密码');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final ok = await SportCampusAuth.instance.signIn(
      mobile: mobile,
      password: password,
      remember: _remember,
    );
    if (!mounted) {
      return;
    }
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = SportCampusAuth.instance.error ?? '登录失败，请稍后重试';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('绑定高校体育')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        children: <Widget>[
          const Icon(Icons.directions_run, size: 56, color: AppColors.usstRed),
          const SizedBox(height: 12),
          const Text(
            '用高校体育账号登录',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            '校园跑记在「高校体育」App 里，账号是注册时用的手机号，和学号无关',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _mobileController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '手机号',
              prefixIcon: Icon(Icons.phone_iphone),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _passwordController,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: '密码',
              prefixIcon: Icon(Icons.lock_outline),
              border: OutlineInputBorder(),
            ),
          ),
          SwitchListTile(
            value: _remember,
            onChanged: (value) => setState(() => _remember = value),
            contentPadding: EdgeInsets.zero,
            title: const Text('记住账号', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              '手机号和密码用系统级加密（Keystore/Keychain）保存在本机，仅用于自动刷新次数',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.usstRed, fontSize: 13),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(backgroundColor: AppColors.usstRed),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('绑定并查询'),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '非官方项目。这里只读取「目标次数 / 已跑次数」，不会替你跑步、'
            '不会提交任何记录。密码加密保存在系统密钥库，不上传服务器、不写日志；'
            '不勾选「记住账号」时只在本次使用期间保留。',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
