/// 设置页：本地导入 / WebDAV 备份 / 性能 / 听书 / 关于。
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api/wenku8_api.dart';
import '../models/models.dart';
import '../services/importer.dart';
import '../services/services.dart';
import '../services/webdav.dart';
import '../ui/design_system.dart';

class SettingsPage extends StatefulWidget {
  final BookshelfService shelf;
  final LocalLibraryService library;
  final Wenku8Api api;
  final TtsService? tts;
  final SettingsService? settingsService;
  final AppPrefsService prefsService;
  final WebDavService webdav;
  const SettingsPage({
    super.key,
    required this.shelf,
    required this.library,
    required this.api,
    required this.prefsService,
    required this.webdav,
    this.tts,
    this.settingsService,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _importing = false;
  String? _importMsg;
  final _davUrlCtrl = TextEditingController();
  final _davUserCtrl = TextEditingController();
  final _davPassCtrl = TextEditingController();
  String? _davMsg;
  bool _davBusy = false;

  @override
  void initState() {
    super.initState();
    _loadDav();
  }

  @override
  void dispose() {
    _davUrlCtrl.dispose();
    _davUserCtrl.dispose();
    _davPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDav() async {
    await widget.webdav.load();
    final cfg = widget.webdav.config;
    if (!mounted || cfg == null) return;
    setState(() {
      _davUrlCtrl.text = cfg.url;
      _davUserCtrl.text = cfg.user;
      _davPassCtrl.text = cfg.password;
    });
  }

  // ---------------- 本地导入 ----------------

  Future<void> _pickAndImport() async {
    setState(() {
      _importing = true;
      _importMsg = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub', 'txt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _importing = false);
        return;
      }
      final f = result.files.first;
      if (f.bytes == null || f.name.isEmpty) {
        setState(() {
          _importing = false;
          _importMsg = '读取文件失败';
        });
        return;
      }
      // M2 修复：超大文件保护（iOS 内存限制）
      if (f.size > 120 * 1024 * 1024) {
        setState(() {
          _importing = false;
          _importMsg = '文件过大（${(f.size / 1024 / 1024).toStringAsFixed(0)} MB），请拆分后导入（上限 120 MB）';
        });
        return;
      }
      final r = await LocalImporter.importFile(f.name, f.bytes!);
      // 章节正文写缓存（阅读时离线可读）
      for (final e in r.chapterText.entries) {
        await widget.library.cache.put(r.book.aid, e.key, e.value);
      }
      await widget.shelf.addOrUpdate(r.book,
          lastChapterTitle: null);
      if (!mounted) return;
      setState(() {
        _importing = false;
        _importMsg = '已导入《${r.book.title}》：${r.volumes.fold<int>(0, (s, v) => s + v.chapters.length)} 章';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _importMsg = '导入失败：$e';
      });
    }
  }

  // ---------------- WebDAV ----------------

  Future<void> _saveDavConfig() async {
    final cfg = WebDavConfig(
      url: _davUrlCtrl.text.trim(),
      user: _davUserCtrl.text.trim(),
      password: _davPassCtrl.text,
    );
    if (!cfg.isValid) {
      setState(() => _davMsg = 'URL 必须以 http(s):// 开头');
      return;
    }
    setState(() => _davBusy = true);
    await widget.webdav.saveConfig(cfg);
    final (ok, msg) = await widget.webdav.testConnection();
    if (!mounted) return;
    setState(() {
      _davBusy = false;
      _davMsg = msg;
    });
  }

  Future<void> _davBackup() async {
    setState(() {
      _davBusy = true;
      _davMsg = null;
    });
    try {
      final payload = BackupPayload(
        entries: widget.shelf.entries,
        settings: widget.settingsService?.settings,
      );
      await widget.webdav.upload(payload);
      if (!mounted) return;
      setState(() {
        _davBusy = false;
        _davMsg = '备份成功（${widget.shelf.entries.length} 本，含进度与设置）';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _davBusy = false;
        _davMsg = '备份失败：$e';
      });
    }
  }

  Future<void> _davRestore() async {
    setState(() {
      _davBusy = true;
      _davMsg = null;
    });
    try {
      final payload = await widget.webdav.download();
      if (payload == null) {
        if (!mounted) return;
        setState(() {
          _davBusy = false;
          _davMsg = '远端暂无备份';
        });
        return;
      }
      // 合并恢复：远端条目按 lastReadAt 新者保留
      var restored = 0;
      var skippedLocal = 0;
      for (final e in payload.entries) {
        // M3 修复：本地导入书（aid 前缀 L）正文不在备份中，恢复后无法阅读
        if (e.book.aid.startsWith('L')) {
          skippedLocal++;
          continue;
        }
        final local = widget.shelf.get(e.book.aid);
        if (local == null || e.lastReadAt > local.lastReadAt) {
          await widget.shelf.addOrUpdate(e.book,
              lastCid: e.lastCid,
              lastChapterTitle: e.lastChapterTitle,
              lastPosition: e.lastPosition);
          restored++;
        }
      }
      if (payload.settings != null && widget.settingsService != null) {
        await widget.settingsService!.update(payload.settings!);
      }
      if (!mounted) return;
      setState(() {
        _davBusy = false;
        _davMsg = restored == 0 && skippedLocal > 0
            ? '远端备份只有本地导入书（正文不随备份），未恢复'
            : '恢复完成：合并 $restored 本（本地较新的保留）'
                '${skippedLocal > 0 ? "，跳过 $skippedLocal 本本地导入书" : ""}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _davBusy = false;
        _davMsg = '恢复失败：$e';
      });
    }
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    final prefs = widget.prefsService.prefs;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: ListView(
        children: [
          const ArchiveHeader(title: '设置', note: '导入 · 同步 · 性能 · 听书'),
          const SizedBox(height: 16),

          // ------ 本地导入 ------
          _section('本地书库导入',
              '支持 EPUB / TXT（自动分章，可读可听）', [
            if (_importing)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Row(children: [
                  SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('导入中…', style: TextStyle(fontSize: 12)),
                ]),
              )
            else
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.black),
                onPressed: _pickAndImport,
                icon: const Icon(Icons.upload_file),
                label: const Text('选择文件导入'),
              ),
            if (_importMsg != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_importMsg!,
                    style: TextStyle(
                        fontSize: 12,
                        color: _importMsg!.startsWith('导入失败')
                            ? Colors.redAccent
                            : CreamTokens.inkSoft)),
              ),
          ]),

          // ------ WebDAV ------
          _section('WebDAV 备份与同步', '书架 + 进度 + 阅读设置，一键备份/恢复', [
            TextField(
              controller: _davUrlCtrl,
              decoration: const InputDecoration(
                  labelText: '服务器 URL（如 https://dav.example.com/dav/）',
                  isDense: true,
                  border: OutlineInputBorder()),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _davUserCtrl,
                  decoration: const InputDecoration(
                      labelText: '账号',
                      isDense: true,
                      border: OutlineInputBorder()),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _davPassCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: '密码',
                      isDense: true,
                      border: OutlineInputBorder()),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _davBusy ? null : _saveDavConfig,
                  icon: const Icon(Icons.wifi_tethering, size: 16),
                  label: const Text('保存并测试'),
                ),
                OutlinedButton.icon(
                  onPressed: _davBusy ? null : _davBackup,
                  icon: const Icon(Icons.cloud_upload, size: 16),
                  label: const Text('备份到云端'),
                ),
                OutlinedButton.icon(
                  onPressed: _davBusy ? null : _davRestore,
                  icon: const Icon(Icons.cloud_download, size: 16),
                  label: const Text('从云端恢复'),
                ),
              ],
            ),
            if (_davBusy)
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            if (_davMsg != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_davMsg!,
                    style: const TextStyle(
                        fontSize: 12, color: CreamTokens.inkSoft)),
              ),
          ]),

          // ------ 性能 ------
          _section('性能', '低性能设备自动关闭全部特效', [
            SwitchListTile(
              dense: true,
              title: const Text('低性能设备模式',
                  style: TextStyle(fontSize: 14)),
              subtitle: const Text('关闭玻璃折射、模糊与动效',
                  style: TextStyle(fontSize: 11)),
              value: prefs.lowPerfMode,
              onChanged: (v) => _savePrefs(prefs.copyWith(
                  lowPerfMode: v,
                  glassEnabled: v ? false : prefs.glassEnabled,
                  blurEnabled: v ? false : prefs.blurEnabled,
                  animationsEnabled: v ? false : prefs.animationsEnabled)),
            ),
            if (!prefs.lowPerfMode) ...[
              SwitchListTile(
                dense: true,
                title: const Text('玻璃折射', style: TextStyle(fontSize: 14)),
                value: prefs.glassEnabled,
                onChanged: (v) =>
                    _savePrefs(prefs.copyWith(glassEnabled: v)),
              ),
              SwitchListTile(
                dense: true,
                title: const Text('背景模糊', style: TextStyle(fontSize: 14)),
                value: prefs.blurEnabled,
                onChanged: (v) =>
                    _savePrefs(prefs.copyWith(blurEnabled: v)),
              ),
              SwitchListTile(
                dense: true,
                title: const Text('页面动效', style: TextStyle(fontSize: 14)),
                value: prefs.animationsEnabled,
                onChanged: (v) =>
                    _savePrefs(prefs.copyWith(animationsEnabled: v)),
              ),
            ],
          ]),

          // ------ 听书 ------
          if (widget.tts != null)
            _section('在线听书', '语速 0.5~2.0、音调 0.5~2.0', [
              StatefulBuilder(builder: (context, setLocal) {
                double rate = _ttsRate;
                double pitch = _ttsPitch;
                return Column(
                  children: [
                    Row(children: [
                      const Text('语速', style: TextStyle(fontSize: 13)),
                      Expanded(
                        child: Slider(
                          value: rate,
                          min: 0.5,
                          max: 2.0,
                          divisions: 15,
                          label: rate.toStringAsFixed(1),
                          onChanged: (v) {
                            setLocal(() => rate = v);
                            _setTtsRate(v);
                          },
                        ),
                      ),
                      Text(rate.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 12)),
                    ]),
                    Row(children: [
                      const Text('音调', style: TextStyle(fontSize: 13)),
                      Expanded(
                        child: Slider(
                          value: pitch,
                          min: 0.5,
                          max: 2.0,
                          divisions: 15,
                          label: pitch.toStringAsFixed(1),
                          onChanged: (v) {
                            setLocal(() => pitch = v);
                            _setTtsPitch(v);
                          },
                        ),
                      ),
                      Text(pitch.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 12)),
                    ]),
                  ],
                );
              }),
            ]),

          // ------ 关于 ------
          _section('关于', null, [
            const Text('轻小说文库 iPad 阅读器 · v1.1',
                style: TextStyle(fontSize: 12, color: CreamTokens.inkSoft)),
            const SizedBox(height: 4),
            const Text(
                '数据来源：wenku8 全本 TXT 通道 + 全站目录快照（3892 本）· '
                '封面 jsdelivr CDN · 本地导入 EPUB/TXT · WebDAV 同步',
                style: TextStyle(fontSize: 11, color: CreamTokens.inkSoft)),
          ]),
        ],
      ),
    );
  }

  double _ttsRate = 0.5;
  double _ttsPitch = 1.0;

  Future<void> _setTtsRate(double v) async {
    _ttsRate = v;
    await widget.tts?.setRate(v);
  }

  Future<void> _setTtsPitch(double v) async {
    _ttsPitch = v;
    await widget.tts?.setPitch(v);
  }

  Future<void> _savePrefs(AppPrefs p) async {
    await widget.prefsService.update(p);
    if (mounted) setState(() {});
  }

  Widget _section(String title, String? note, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: CreamGlass(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Songti',
                      color: CreamTokens.ink)),
              if (note != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 8),
                  child: Text(note,
                      style: const TextStyle(
                          fontSize: 11, color: CreamTokens.inkSoft)),
                )
              else
                const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      );
}
