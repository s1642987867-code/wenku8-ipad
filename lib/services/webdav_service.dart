/// WebDAV 同步：将备份 ZIP 上传至 OpenList/坚果云等 WebDAV 网盘，或从中恢复
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'cache_service.dart';
import 'services.dart';

class WebDavConfig {
  final String url; // 例如 https://dav.jianguoyun.com/dav/
  final String username;
  final String password;

  const WebDavConfig({required this.url, required this.username, required this.password});

  bool get isValid => url.isNotEmpty && username.isNotEmpty && password.isNotEmpty;

  Map<String, dynamic> toJson() => {'url': url, 'username': username, 'password': password};

  factory WebDavConfig.fromJson(Map<String, dynamic> j) => WebDavConfig(
        url: j['url']?.toString() ?? '',
        username: j['username']?.toString() ?? '',
        password: j['password']?.toString() ?? '',
      );
}

class WebDavService {
  static final WebDavService instance = WebDavService._();
  WebDavService._();

  WebDavConfig? _config;
  WebDavConfig? get config => _config;
  bool get isConnected => _config?.isValid ?? false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('webdav_config');
    if (json != null) {
      _config = WebDavConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
    }
  }

  Future<void> save(WebDavConfig config) async {
    _config = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('webdav_config', jsonEncode(config.toJson()));
  }

  Map<String, String> get _headers {
    final c = _config!;
    final auth = base64Encode(utf8.encode('${c.username}:${c.password}'));
    return {'Authorization': 'Basic $auth'};
  }

  Uri _fileUri(String fileName) {
    var base = _config!.url;
    if (!base.endsWith('/')) base += '/';
    return Uri.parse('$base$fileName');
  }

  /// 测试连接（PROPFIND 根目录）
  Future<bool> testConnection() async {
    if (!isConnected) return false;
    try {
      final resp = await http.Request('PROPFIND', Uri.parse(_config!.url))
        ..headers.addAll({..._headers, 'Depth': '0'});
      final streamed = await resp.send().timeout(const Duration(seconds: 15));
      return streamed.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// 上传备份到 WebDAV
  Future<bool> uploadBackup() async {
    if (!isConnected) throw Exception('未配置 WebDAV');
    final data = await _collectBackupBytes();
    final fileName = 'wenku8_backup_latest.zip';
    final resp = await http.put(_fileUri(fileName), headers: _headers, body: data)
        .timeout(const Duration(seconds: 60));
    return resp.statusCode >= 200 && resp.statusCode < 300;
  }

  /// 从 WebDAV 下载并恢复
  Future<int> downloadAndRestore() async {
    if (!isConnected) throw Exception('未配置 WebDAV');
    final fileName = 'wenku8_backup_latest.zip';
    final resp = await http.get(_fileUri(fileName), headers: _headers)
        .timeout(const Duration(seconds: 60));
    if (resp.statusCode != 200) throw Exception('下载失败 HTTP ${resp.statusCode}');
    // 保存临时文件后走 BackupService 导入
    final tmp = File('${Directory.systemTemp.path}/webdav_restore.zip');
    await tmp.writeAsBytes(resp.bodyBytes);
    return await BackupService.instance.importFromFile(tmp.path);
  }

  Future<Uint8List> _collectBackupBytes() async {
    // 复用 BackupService 的导出逻辑：直接序列化
    final data = jsonEncode({
      'version': 3,
      'exportedAt': DateTime.now().toIso8601String(),
      'shelf': ShelfService.instance.list.map((e) => e.toJson()).toList(),
      'bookmarks': BookmarkService.instance.all.map((b) => b.toJson()).toList(),
      'settings': SettingsService.instance.current.toJson(),
      'history': HistoryService.instance.list,
      'localBooks': [], // 本地书体量大，WebDAV 同步只同步元数据不传内容
    });
    // 打成 zip（单文件，无需 archive 压缩，直接 JSON 也可以；保持 zip 兼容导入）
    final archive = Archive()
      ..addFile(ArchiveFile('backup.json', utf8.encode(data).length, Uint8List.fromList(utf8.encode(data))));
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }
}
