/// 设置页：登录、阅读偏好、数据源、关于
library;

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../models/models.dart';
import '../services/cache_service.dart';
import '../services/local_import.dart';
import '../services/services.dart';
import '../services/webdav_service.dart';
import 'login_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  void _showWebDavSheet() {
    final urlCtl = TextEditingController(text: WebDavService.instance.config?.url ?? '');
    final userCtl = TextEditingController(text: WebDavService.instance.config?.username ?? '');
    final passCtl = TextEditingController(text: WebDavService.instance.config?.password ?? '');
    String _msg = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 20,
              bottom: 20 + MediaQuery.of(sheetCtx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('WebDAV 同步', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(controller: urlCtl, decoration: const InputDecoration(
                  labelText: '服务器地址', hintText: 'https://dav.jianguoyun.com/dav/')),
                TextField(controller: userCtl, decoration: const InputDecoration(labelText: '账号')),
                TextField(controller: passCtl, obscureText: true, decoration: const InputDecoration(labelText: '密码/应用密码')),
                const SizedBox(height: 12),
                if (_msg.isNotEmpty) Text(_msg, style: TextStyle(color: Colors.orange, fontSize: 12)),
                const SizedBox(height: 12),
                Wrap(spacing: 12, children: [
                  FilledButton.tonal(
                    onPressed: () async {
                      setSheet(() => _msg = '测试中...');
                      await WebDavService.instance.save(WebDavConfig(
                        url: urlCtl.text.trim(), username: userCtl.text.trim(), password: passCtl.text.trim()));
                      final ok = await WebDavService.instance.testConnection();
                      setSheet(() => _msg = ok ? '✓ 连接成功' : '✗ 连接失败（检查地址/账号/网络）');
                    },
                    child: const Text('保存并测试'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      setSheet(() => _msg = '上传中...');
                      try {
                        final ok = await WebDavService.instance.uploadBackup();
                        setSheet(() => _msg = ok ? '✓ 备份已上传' : '上传失败');
                      } catch (e) {
                        setSheet(() => _msg = '上传失败: $e');
                      }
                    },
                    child: const Text('上传备份'),
                  ),
                  FilledButton.tonal(
                    onPressed: () async {
                      setSheet(() => _msg = '恢复中...');
                      try {
                        final n = await WebDavService.instance.downloadAndRestore();
                        setSheet(() => _msg = '✓ 已恢复 $n 本书籍');
                      } catch (e) {
                        setSheet(() => _msg = '恢复失败: $e');
                      }
                    },
                    child: const Text('从网盘恢复'),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
            title: Text('轻小说文库 · 在线阅读'),
            subtitle: Text('wenku8.net 网页爬虫，无需登录'),
            trailing: Icon(Icons.check_circle, color: Colors.green, size: 20),
          ),
          const ListTile(
            leading: Icon(Icons.download),
            title: Text('轻小说文库 · 全本 TXT'),
            subtitle: Text('dl.wenku8.com，无需登录'),
            trailing: Icon(Icons.check_circle, color: Colors.green, size: 20),
          ),
          const ListTile(
            leading: Icon(Icons.public),
            title: Text('哔哩轻小说 · 在线阅读'),
            subtitle: Text('linovelib.com 排行/书页/正文，无需登录'),
            trailing: Icon(Icons.check_circle, color: Colors.green, size: 20),
          ),
          const ListTile(
            leading: Icon(Icons.search),
            title: Text('轻小说文库 · 在线排行/搜索'),
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
          // 数据与缓存
          const _SectionHeader('数据与缓存'),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('阅读历史'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryPage())),
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services),
            title: const Text('章节缓存管理'),
            onTap: () async {
              final (count, bytes) = await ChapterCacheService.instance.stats();
              if (!mounted) return;
              final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
                title: const Text('章节缓存'),
                content: Text('已缓存 $count 个章节，占用 ${(bytes / 1024 / 1024).toStringAsFixed(1)} MB'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                  TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('清空')),
                ],
              ));
              if (ok == true) {
                await ChapterCacheService.instance.clear();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('缓存已清空')));
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.backup),
            title: const Text('导出备份'),
            subtitle: const Text('书架/进度/书签/设置/历史 → ZIP'),
            onTap: () async {
              try {
                final path = await BackupService.instance.exportToFile();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(path.isEmpty ? '已取消' : '已导出到 $path')));
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败: $e')));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('导入备份'),
            subtitle: const Text('从 ZIP 备份恢复'),
            onTap: () async {
              final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
              final path = result?.files.single.path;
              if (path == null) return;
              try {
                final n = await BackupService.instance.importFromFile(path);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已恢复 $n 本书籍')));
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败: $e')));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.cloud_sync),
            title: const Text('WebDAV 网盘同步'),
            subtitle: Text(WebDavService.instance.isConnected
                ? '已配置：${WebDavService.instance.config!.url}'
                : 'OpenList/坚果云等，上传/恢复备份'),
            trailing: Icon(WebDavService.instance.isConnected ? Icons.check_circle : Icons.chevron_right,
                color: WebDavService.instance.isConnected ? Colors.green : Colors.grey, size: 20),
            onTap: () => _showWebDavSheet(),
          ),
          const Divider(),
          // 关于
          const _SectionHeader('关于'),
          const ListTile(
            leading: Icon(Icons.info),
            title: Text('轻小说文库 iPad'),
            subtitle: Text('版本 2.3.0'),
          ),
          const ListTile(
            leading: Icon(Icons.code),
            title: Text('数据来源'),
            subtitle: Text('wenku8.net / linovelib.com / dl.wenku8.com'),
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

/// 阅读历史页
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final items = HistoryService.instance.list;
    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读历史'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: '清空历史',
            onPressed: () async {
              await HistoryService.instance.clear();
              // 刷新页面
              (context as Element).markNeedsBuild();
            },
          ),
        ],
      ),
      body: items.isEmpty
          ? const Center(child: Text('暂无阅读历史', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (ctx, i) {
                final h = items[i];
                final at = DateTime.fromMillisecondsSinceEpoch(h['at'] as int? ?? 0);
                return ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(h['title']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${h['chapterTitle']?.toString() ?? ''} · ${at.month}/${at.day} ${at.hour}:${at.minute.toString().padLeft(2, '0')}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12),
                  ),
                );
              },
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
