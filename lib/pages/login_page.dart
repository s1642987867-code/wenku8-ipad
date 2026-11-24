/// 登录页：wenku8.net 网页登录（当前站点登录已失效，保留 UI）
library;

import 'package:flutter/material.dart';

import '../api/wenku8_api.dart';
import '../services/services.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  String? _message;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _usernameCtrl.text = AuthService.instance.username ?? '';
  }

  Future<void> _login() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _message = '请输入用户名和密码');
      return;
    }

    setState(() { _loading = true; _message = null; });

    final api = Wenku8Api();
    final ok = await api.login(username, password);

    if (ok) {
      await AuthService.instance.setLoggedIn(username, password);
      setState(() { _loading = false; _success = true; _message = '登录成功'; });
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) Navigator.pop(context);
    } else {
      setState(() {
        _loading = false;
        _message = '登录失败。当前 wenku8.net 站点登录功能已失效（站点显示"本站正式关闭"）。\n\n'
            '已记录您的账号信息，待站点恢复后可重新登录。\n'
            '登录接口: POST /login.php?do=submit\n'
            '表单字段: username/password/action=login/usecookie=315360000';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.account_circle, size: 72, color: Color(0xFF6750A4)),
            const SizedBox(height: 24),
            TextField(
              controller: _usernameCtrl,
              decoration: const InputDecoration(
                labelText: '用户名',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordCtrl,
              decoration: const InputDecoration(
                labelText: '密码',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
              onSubmitted: (_) => _login(),
            ),
            const SizedBox(height: 24),
            if (_loading)
              const CircularProgressIndicator()
            else
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(onPressed: _login, child: const Text('登录')),
              ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _success ? Colors.green.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_message!, style: TextStyle(fontSize: 13, color: _success ? Colors.green.shade700 : Colors.orange.shade700)),
              ),
            ],
            const SizedBox(height: 24),
            const Text(
              '当前 wenku8.net 登录功能已失效\n'
              '发现/搜索使用本地 4328 本目录快照\n'
              '在线阅读和全本下载不受影响',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
