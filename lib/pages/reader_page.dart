/// 阅读器：纵向滚动 + 字号/行距/背景/夜间模式 + 章节导航
library;

import 'package:flutter/material.dart';

import '../api/linovelib_api.dart';
import '../api/web_scraper.dart';
import '../api/wenku8_api.dart';
import '../models/models.dart';
import '../services/services.dart';

class ReaderPage extends StatefulWidget {
  final String aid;
  final Book book;
  final List<Volume> volumes;
  final int initialChapterIdx;

  const ReaderPage({
    super.key,
    required this.aid,
    required this.book,
    required this.volumes,
    this.initialChapterIdx = 0,
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final _scraper = WebScraper();
  final _api = Wenku8Api();
  final _lino = LinovelibApi();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late int _chapterIdx;
  String? _content;
  bool _loading = true;
  String? _error;
  final _scrollController = ScrollController();

  static const _bgColors = [
    Color(0xFFF5F0E8), // 米色（护眼）
    Color(0xFFE8F5E9), // 绿色（护眼）
    Color(0xFFFAFAFA), // 白色
    Color(0xFFF5F5DC), // 米黄
    Color(0xFF1A1A1A), // 深色（夜间）
  ];

  static const _textColors = [
    Color(0xFF333333), // 深灰
    Color(0xFF2E4E2E), // 深绿
    Color(0xFF333333), // 深灰
    Color(0xFF5B4636), // 棕色
    Color(0xFFB0B0B0), // 浅灰（夜间）
  ];

  List<Chapter> get _flatChapters =>
      widget.volumes.expand((v) => v.chapters).toList();

  Chapter get _currentChapter => _flatChapters[_chapterIdx];

  @override
  void initState() {
    super.initState();
    _chapterIdx = widget.initialChapterIdx;
    _loadChapter();
  }

  Future<void> _loadChapter() async {
    setState(() { _loading = true; _error = null; });
    try {
      final ch = _currentChapter;
      String content;
      if (widget.book.source == BookSource.linovelib) {
        // 哔哩轻小说源
        content = await _lino.chapter(widget.aid.substring(5), ch.cid);
      } else if (ch.cid.startsWith('w')) {
        // wenku8 网页章节
        content = await _scraper.chapter(widget.aid, ch.cid);
      } else {
        // TXT 全本章节
        content = await _api.chapterContent(widget.aid, ch.cid);
      }
      _content = content;
      _loading = false;
      _scrollController.jumpTo(0);
      setState(() {});
      // 更新阅读进度
      ShelfService.instance.updateProgress(
        widget.aid,
        ch.cid,
        ch.title,
        _chapterIdx,
        0,
      );
    } catch (e) {
      setState(() { _loading = false; _error = '$e'; });
    }
  }

  void _prevChapter() {
    if (_chapterIdx > 0) {
      _chapterIdx--;
      _loadChapter();
    }
  }

  void _nextChapter() {
    if (_chapterIdx < _flatChapters.length - 1) {
      _chapterIdx++;
      _loadChapter();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance.current;
    final bgColor = settings.nightMode
        ? _bgColors[4]
        : _bgColors[settings.backgroundColorIndex.clamp(0, _bgColors.length - 2)];
    final textColor = settings.nightMode
        ? _textColors[4]
        : _textColors[settings.backgroundColorIndex.clamp(0, _textColors.length - 2)];

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        foregroundColor: textColor,
        title: Text(_currentChapter.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16)),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(icon: const Icon(Icons.toc), onPressed: () => _scaffoldKey.currentState?.openEndDrawer()),
          IconButton(icon: const Icon(Icons.settings), onPressed: _showSettingsSheet),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('加载失败: $_error', style: TextStyle(color: Colors.grey), textAlign: TextAlign.center)))
              : GestureDetector(
                  onHorizontalDragEnd: (details) {
                    if (details.primaryVelocity != null) {
                      if (details.primaryVelocity! < -200) _nextChapter();
                      else if (details.primaryVelocity! > 200) _prevChapter();
                    }
                  },
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 章节标题
                        Center(child: Text(_currentChapter.title, style: TextStyle(fontSize: settings.fontSize + 4, fontWeight: FontWeight.bold, color: textColor, height: 1.5))),
                        const SizedBox(height: 24),
                        // 正文段落
                        ...(_content ?? '').split('\n').where((l) => l.trim().isNotEmpty).map((line) => Padding(
                          padding: EdgeInsets.only(bottom: settings.paragraphSpacing),
                          child: Text(
                            '　　$line',
                            style: TextStyle(
                              fontSize: settings.fontSize,
                              height: settings.lineHeight,
                              color: textColor,
                              fontFamily: settings.fontFamily == 'system' ? null : settings.fontFamily,
                            ),
                            textAlign: settings.justifyText ? TextAlign.justify : TextAlign.left,
                          ),
                        )),
                        const SizedBox(height: 48),
                        // 章节导航
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (_chapterIdx > 0)
                              TextButton(onPressed: _prevChapter, child: Text('上一章', style: TextStyle(color: textColor)))
                            else const SizedBox(),
                            Text('${_chapterIdx + 1}/${_flatChapters.length}', style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 12)),
                            if (_chapterIdx < _flatChapters.length - 1)
                              TextButton(onPressed: _nextChapter, child: Text('下一章', style: TextStyle(color: textColor)))
                            else const SizedBox(),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
      // 底部章节导航栏
      bottomNavigationBar: _loading ? null : BottomAppBar(
        color: bgColor,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(icon: Icon(Icons.chevron_left, color: textColor), onPressed: _chapterIdx > 0 ? _prevChapter : null),
            TextButton(onPressed: () => _scaffoldKey.currentState?.openEndDrawer(), child: Text('目录', style: TextStyle(color: textColor))),
            IconButton(icon: Icon(Icons.chevron_right, color: textColor), onPressed: _chapterIdx < _flatChapters.length - 1 ? _nextChapter : null),
            IconButton(icon: Icon(Icons.tune, color: textColor), onPressed: _showSettingsSheet),
          ],
        ),
      ),
      endDrawer: Drawer(
        backgroundColor: bgColor,
        child: _buildTocDrawer(textColor),
      ),
    );
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => const ReaderSettingsPanel(),
    );
  }

  Widget _buildTocDrawer(Color textColor) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: widget.volumes.length,
      itemBuilder: (ctx, vi) {
        final vol = widget.volumes[vi];
        return ExpansionTile(
          title: Text(vol.title, style: TextStyle(color: textColor, fontSize: 14)),
          initiallyExpanded: vi == 0,
          children: vol.chapters.asMap().entries.map((e) {
            final globalIdx = _globalChapterIndex(vi, e.key);
            final isCurrent = globalIdx == _chapterIdx;
            return ListTile(
              dense: true,
              selected: isCurrent,
              title: Text(
                e.value.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: isCurrent ? Theme.of(context).colorScheme.primary : textColor),
              ),
              onTap: () {
                _chapterIdx = globalIdx;
                Navigator.pop(context);
                _loadChapter();
              },
            );
          }).toList(),
        );
      },
    );
  }

  int _globalChapterIndex(int volIdx, int chIdx) {
    int count = 0;
    for (var i = 0; i < volIdx; i++) {
      count += widget.volumes[i].chapters.length;
    }
    return count + chIdx;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

/// 阅读设置面板（底部弹出）
class ReaderSettingsPanel extends StatefulWidget {
  const ReaderSettingsPanel({super.key});
  @override
  State<ReaderSettingsPanel> createState() => _ReaderSettingsPanelState();
}

class _ReaderSettingsPanelState extends State<ReaderSettingsPanel> {
  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance.current;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('阅读设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          // 字号
          Row(children: [
            const Text('字号'),
            Expanded(child: Slider(
              value: settings.fontSize, min: 12, max: 32, divisions: 20,
              label: settings.fontSize.round().toString(),
              onChanged: (v) => setState(() => SettingsService.instance.update(settings.copyWith(fontSize: v))),
            )),
            Text('${settings.fontSize.round()}', style: const TextStyle(fontSize: 12)),
          ]),
          // 行距
          Row(children: [
            const Text('行距'),
            Expanded(child: Slider(
              value: settings.lineHeight, min: 1.2, max: 3.0, divisions: 18,
              label: settings.lineHeight.toStringAsFixed(1),
              onChanged: (v) => setState(() => SettingsService.instance.update(settings.copyWith(lineHeight: v))),
            )),
            Text(settings.lineHeight.toStringAsFixed(1), style: const TextStyle(fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          // 背景色选择
          const Text('背景'),
          const SizedBox(height: 8),
          Row(
            children: List.generate(4, (i) {
              final colors = [Color(0xFFF5F0E8), Color(0xFFE8F5E9), Color(0xFFFAFAFA), Color(0xFFF5F5DC)];
              return GestureDetector(
                onTap: () => setState(() => SettingsService.instance.update(settings.copyWith(backgroundColorIndex: i))),
                child: Container(
                  width: 36, height: 36,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: colors[i],
                    shape: BoxShape.circle,
                    border: Border.all(color: settings.backgroundColorIndex == i ? Theme.of(context).colorScheme.primary : Colors.grey, width: 2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          // 夜间模式
          SwitchListTile(
            title: const Text('夜间模式'),
            value: settings.nightMode,
            onChanged: (v) => setState(() => SettingsService.instance.update(settings.copyWith(nightMode: v))),
          ),
        ],
      ),
    );
  }
}
