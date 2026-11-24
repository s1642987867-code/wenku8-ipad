/// 设置页：登录、阅读偏好、数据源、关于
library;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/services.dart';
import 'login_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          // 登录状态
          ListTile(
            leading: Icon(auth.isLoggedIn ? Icons.account_circle : Icons.person_outline, size: 40),
            title: Text(auth.isLoggedIn ? auth.username ?? '已登录' : '未登录'),
            subtitle: Text(auth.isLoggedIn
                ? '当前 wenku8.net 登录已失效，在线排行/搜索/分类不可用'
                : '点击登录（当前站点登录已失效）'),
            trailing: auth.isLoggedIn
                ? TextButton(onPressed: () async { await auth.logout(); setState(() {}); }, child: const Text('退出'))
                : TextButton(onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
                    setState(() {});
                  }, child: const Text('登录')),
          ),
          const Divider(),
          // 阅读设置
          const _SectionHeader('阅读'),
          ListTile(
            leading: const Icon(Icons.text_fields),
            title: const Text('默认字号'),
            trailing: StreamBuilder(
              stream: SettingsService.instance.settings,
              builder: (_, snap) => Text('${(snap.data?.fontSize ?? 18).round()}', style: const TextStyle(color: Colors.grey)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dark_mode),
            title: const Text('夜间模式'),
            trailing: StreamBuilder(
              stream: SettingsService.instance.settings,
              builder: (_, snap) => Switch(
                value: snap.data?.nightMode ?? false,
                onChanged: (v) => SettingsService.instance.update((snap.data ?? const ReaderSettings()).copyWith(nightMode: v)),
              ),
            ),
          ),
          const Divider(),
          // 数据源
          const _SectionHeader('数据源'),
          const ListTile(
            leading: Icon(Icons.cloud_download),
            title: Text('在线阅读（网页爬虫）'),
            subtitle: Text('书页 → 目录 → 正文，无需登录'),
            trailing: Icon(Icons.check_circle, color: Colors.green, size: 20),
          ),
          const ListTile(
            leading: Icon(Icons.download),
            title: Text('全本 TXT 下载'),
            subtitle: Text('dl.wenku8.com，无需登录'),
            trailing: Icon(Icons.check_circle, color: Colors.green, size: 20),
          ),
          const ListTile(
            leading: Icon(Icons.search),
            title: Text('在线排行/搜索/分类'),
            subtitle: Text('需登录，当前站点登录已失效'),
            trailing: Icon(Icons.cancel, color: Colors.red, size: 20),
          ),
          const ListTile(
            leading: Icon(Icons.storage),
            title: Text('本地目录快照'),
            subtitle: Text('4328 本，用于发现页和搜索'),
            trailing: Icon(Icons.check_circle, color: Colors.green, size: 20),
          ),
          const Divider(),
          // 关于
          const _SectionHeader('关于'),
          const ListTile(
            leading: Icon(Icons.info),
            title: Text('轻小说文库 iPad'),
            subtitle: Text('版本 2.0.0'),
          ),
          const ListTile(
            leading: Icon(Icons.code),
            title: Text('数据来源'),
            subtitle: Text('wenku8.net / dl.wenku8.com / img.wenku8.com'),
          ),
          const ListTile(
            leading: Icon(Icons.warning),
            title: Text('免责声明'),
            subtitle: Text('本应用仅供学习交流使用，所有小说版权归原作者所有'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(title, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 14, fontWeight: FontWeight.bold)),
    );
  }
}
