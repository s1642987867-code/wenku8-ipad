/// WebDAV 备份/恢复：书架 + 阅读进度 + 设置 → 单个 JSON 文件。
/// 用 package:http 实现 PUT/GET（PROPFIND 仅测连通性），无额外依赖。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

class WebDavConfig {
  final String url; // 如 https://dav.example.com/dav/
  final String user;
  final String password;
  const WebDavConfig({required this.url, required this.user, required this.password});

  bool get isValid =>
      url.startsWith('http://') || url.startsWith('https://');

  Map<String, dynamic> toJson() => {'url': url, 'user': user, 'password': password};
  factory WebDavConfig.fromJson(Map<String, dynamic> j) => WebDavConfig(
        url: j['url'] as String? ?? '',
        user: j['user'] as String? ?? '',
        password: j['password'] as String? ?? '',
      );
}

class WebDavException implements Exception {
  final String message;
  WebDavException(this.message);
  @override
  String toString() => message;
}

/// 备份数据结构。
class BackupPayload {
  final List<ShelfEntry> entries;
  final ReaderSettings? settings;
  final Map<String, dynamic> extra;
  BackupPayload({required this.entries, this.settings, this.extra = const {}});

  Map<String, dynamic> toJson() => {
        'version': 2,
        'exportedAt': DateTime.now().toIso8601String(),
        'entries': entries.map((e) => e.toJson()).toList(),
        if (settings != null) 'readerSettings': settings!.toJson(),
        ...extra,
      };

  factory BackupPayload.fromJson(Map<String, dynamic> j) => BackupPayload(
        entries: (j['entries'] as List? ?? const [])
            .map((e) => ShelfEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        settings: j['readerSettings'] != null
            ? ReaderSettings.fromJson(
                j['readerSettings'] as Map<String, dynamic>)
            : null,
        extra: {
          for (final k in j.keys)
            if (k != 'entries' && k != 'readerSettings' && k != 'version' && k != 'exportedAt')
              k: j[k],
        },
      );
}

class WebDavService {
  static const _cfgKey = 'webdav_config_v1';
  static const _remotePath = '/wenku8-backup.json';
  final http.Client _client = http.Client();

  WebDavConfig? _config;
  WebDavConfig? get config => _config;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_cfgKey);
    if (raw != null) {
      try {
        _config = WebDavConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        _config = null;
      }
    }
  }

  Future<void> saveConfig(WebDavConfig cfg) async {
    _config = cfg;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_cfgKey, jsonEncode(cfg.toJson()));
  }

  Future<void> clearConfig() async {
    _config = null;
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_cfgKey);
  }

  String get _fileUrl {
    final cfg = _config!;
    final base = cfg.url.endsWith('/') ? cfg.url : '${cfg.url}/';
    return '$base${_remotePath.substring(1)}';
  }

  Map<String, String> get _authHeaders {
    final cfg = _config!;
    final token = base64Encode(utf8.encode('${cfg.user}:${cfg.password}'));
    return {'Authorization': 'Basic $token'};
  }

  /// 测试连通性（GET 备份文件；404 也算连通成功）。
  Future<(bool, String)> testConnection() async {
    final cfg = _config;
    if (cfg == null || !cfg.isValid) return (false, 'WebDAV 配置无效');
    try {
      final r = await _client
          .get(Uri.parse(_fileUrl), headers: _authHeaders)
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 200 || r.statusCode == 404) {
        return (true, r.statusCode == 200 ? '连接正常（已有备份）' : '连接正常（暂无备份）');
      }
      if (r.statusCode == 401) return (false, '账号或密码错误（401）');
      return (false, '服务器返回 ${r.statusCode}');
    } catch (e) {
      return (false, '连接失败：$e');
    }
  }

  /// 上传备份（覆盖远端）。
  Future<void> upload(BackupPayload payload) async {
    final cfg = _config;
    if (cfg == null || !cfg.isValid) throw WebDavException('WebDAV 未配置');
    final body = jsonEncode(payload.toJson());
    final r = await _client
        .put(Uri.parse(_fileUrl),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: utf8.encode(body))
        .timeout(const Duration(seconds: 60));
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw WebDavException('上传失败（HTTP ${r.statusCode}）');
    }
  }

  /// 下载备份；远端无备份返回 null。
  Future<BackupPayload?> download() async {
    final cfg = _config;
    if (cfg == null || !cfg.isValid) throw WebDavException('WebDAV 未配置');
    final r = await _client
        .get(Uri.parse(_fileUrl), headers: _authHeaders)
        .timeout(const Duration(seconds: 60));
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) {
      throw WebDavException('下载失败（HTTP ${r.statusCode}）');
    }
    try {
      return BackupPayload.fromJson(
          jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
    } catch (e) {
      throw WebDavException('备份数据损坏：$e');
    }
  }

  void dispose() => _client.close();
}
