import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/auth/cas_client.dart';
import '../data/auth/jwgl_auth.dart';

/// 教务系统登录页（统一身份认证 CAS）。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _captchaController = TextEditingController();

  /// 多次输错密码后 CAS 会要求验证码；这里存着图片和本次提交要用的 token
  CasCaptchaRequired? _captcha;

  /// 整个登录流程复用同一个 client：验证码是跟会话绑定的，换 client 就失效
  CasClient? _client;

  bool _busy = false;
  String? _error;
  bool _remember = true;

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    _captchaController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    final username = _idController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = '请填写学号和密码');
      return;
    }
    final captcha = _captcha;
    final code = _captchaController.text.trim();
    if (captcha != null && code.isEmpty) {
      setState(() => _error = '请输入验证码');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final client = _client ??= CasClient();
    try {
      if (captcha == null) {
        await client.login(username, password);
      } else {
        await client.loginWithCaptcha(
          username: username,
          password: password,
          challenge: captcha,
          code: code,
        );
      }
      await JwglAuth.instance.adopt(
        client,
        username,
        password,
        remember: _remember,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on CasCaptchaRequired catch (error) {
      // 需要验证码：把图片换成本次响应里的，让用户直接填
      if (mounted) {
        setState(() {
          _captcha = error;
          _error = error.displayMessage;
          _captchaController.clear();
        });
      }
    } on CasLoginException catch (error) {
      if (mounted) {
        setState(() {
          // 验证码走不通（比如 token 过期）就退回普通登录，下一次重新拿会话，
          // 免得卡在同一个失效的 challenge 上反复失败
          _captcha = null;
          _captchaController.clear();
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '网络异常，请稍后重试');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('登录教务系统')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        children: <Widget>[
          const Icon(Icons.school_outlined, size: 56, color: AppColors.usstRed),
          const SizedBox(height: 12),
          const Text(
            '使用统一身份认证登录',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            '和学校统一身份认证同一套学号密码',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _idController,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '学号',
              prefixIcon: Icon(Icons.badge_outlined),
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
          if (_captcha != null) ...<Widget>[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    '密码错误次数过多，需要输入验证码',
                    style: TextStyle(fontSize: 12, color: Color(0xFF9A6A1F)),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      // 验证码图片是跟这次会话绑定的，直接用内存里的字节渲染
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.memory(
                          _captcha!.image,
                          width: 108,
                          height: 40,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _captchaController,
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          decoration: const InputDecoration(
                            labelText: '验证码',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    '看不清可以点「登录」换一张；验证码和本次登录会话绑定，不要重启 App',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
          SwitchListTile(
            value: _remember,
            onChanged: (value) => setState(() => _remember = value),
            contentPadding: EdgeInsets.zero,
            title: const Text('记住登录', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              '学号密码用系统级加密（Keystore/Keychain）保存在本机，仅用于自动登录',
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
                  : const Text('登录'),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '非官方项目。账号密码只在本机使用：未勾选记住登录时只保存登录状态；'
            '勾选后密码会加密保存在系统密钥库（Android Keystore / iOS Keychain），'
            '不会上传到任何服务器，也不会写入日志。登录后仅读取你本人的课表、成绩等信息。',
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
