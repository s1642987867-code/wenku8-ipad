/// 阅读器：三种翻页模式（滚动/横翻/竖排）、分区点按、音量键翻页、
/// 书签、章内查找、页边距/缩进/段距排版，全部实时生效
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/linovelib_api.dart';
import '../api/web_scraper.dart';
import '../api/wenku8_api.dart';
import '../models/models.dart';
import '../services/cache_service.dart';
import '../services/services.dart';
import '../services/tts_service.dart';

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
  final _focusNode = FocusNode(debugLabel: 'reader-keyboard');

  // 翻页（横翻/竖排模式）
  final _pageController = PageController();
  int _currentPage = 0;
  List<List<String>> _pages = []; // 每页的段落列表

  // 章内查找
  String _searchQuery = '';
  List<int> _searchHits = []; // 命中的段落索引

  static const _bgColors = [
    Color(0xFFF5F0E8), // 米色（护眼）
    Color(0xFFE8F5E9), // 绿色（护眼）
    Color(0xFFFAFAFA), // 白色
    Color(0xFFF5F5DC), // 米黄
    Color(0xFF1A1A1A), // 深色（夜间）
  ];

  static const _textColors = [
    Color(0xFF333333),
    Color(0xFF2E4E2E),
    Color(0xFF333333),
    Color(0xFF5B4636),
    Color(0xFFB0B0B0),
  ];

  List<Chapter> get _flatChapters =>
      widget.volumes.expand((v) => v.chapters).toList();

  Chapter get _currentChapter => _flatChapters[_chapterIdx];

  List<String> get _paragraphs {
    final text = _content ?? '';
    return text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _chapterIdx = widget.initialChapterIdx;
    _loadChapter();
  }

  Future<void> _loadChapter() async {
    setState(() { _loading = true; _error = null; _searchQuery = ''; _searchHits = []; });
    try {
      final ch = _currentChapter;
      String content;
      if (ch.localContent != null) {
        // 本地导入章节（TXT/EPUB）
        content = ch.localContent!;
      } else {
        // 优先读缓存
        final cached = await ChapterCacheService.instance.get(widget.aid, ch.cid);
        if (cached != null) {
          content = cached;
        } else if (widget.book.source == BookSource.linovelib) {
          content = await _lino.chapter(widget.aid.substring(5), ch.cid);
          await ChapterCacheService.instance.put(widget.aid, ch.cid, content);
        } else if (ch.cid.startsWith('w')) {
          content = await _scraper.chapter(widget.aid, ch.cid);
          await ChapterCacheService.instance.put(widget.aid, ch.cid, content);
        } else {
          content = await _api.chapterContent(widget.aid, ch.cid);
          await ChapterCacheService.instance.put(widget.aid, ch.cid, content);
        }
      }
      _content = content;
      _loading = false;
      _currentPage = 0;
      _paginate();
      setState(() {});
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      ShelfService.instance.updateProgress(
        widget.aid, ch.cid, ch.title, _chapterIdx, 0,
      );
      // 记录阅读历史
      HistoryService.instance.record(widget.aid, widget.book.title, ch.cid, ch.title);
    } catch (e) {
      setState(() { _loading = false; _error = '$e'; });
    }
  }

  /// 整本缓存（后台下载全书章节）
  Future<void> _cacheWholeBook() async {
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      Future<String> Function(String) fetch;
      if (widget.book.source == BookSource.linovelib) {
        fetch = (cid) => _lino.chapter(widget.aid.substring(5), cid);
      } else {
        fetch = (cid) => _scraper.chapter(widget.aid, cid);
      }
      final n = await ChapterCacheService.instance.cacheWholeBook(widget.aid, widget.volumes, fetch);
      if (mounted) Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text('已缓存 $n 个章节')));
    } catch (e) {
      if (mounted) Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text('缓存失败: $e')));
    }
  }

  /// 简单分页：按段落均分到页（竖排/横翻模式）
  void _paginate() {
    final settings = SettingsService.instance.current;
    final paras = _paragraphs;
    // 粗略估算：每页容 (可用高度 / 行高) 行，每段约 (字符数*字号/页宽) 行
    if (paras.isEmpty) { _pages = [[]]; return; }
    // 简化分页：每页固定段数（大屏约 10-14 段，按字号动态调整）
    final perPage = (settings.fontSize <= 16) ? 14 : (settings.fontSize <= 20 ? 11 : 8);
    _pages = [];
    for (var i = 0; i < paras.length; i += perPage) {
      _pages.add(paras.sublist(i, (i + perPage).clamp(0, paras.length)));
    }
    if (_pages.isEmpty) _pages = [paras];
  }

  void _prevChapter() {
    if (_chapterIdx > 0) { _chapterIdx--; _loadChapter(); }
  }

  void _nextChapter() {
    if (_chapterIdx < _flatChapters.length - 1) { _chapterIdx++; _loadChapter(); }
  }

  // ============ 分区点按 / 音量键 ============
  void _tapZone(Offset localPosition, Size size) {
    final settings = SettingsService.instance.current;
    if (settings.pageMode == 'scroll') {
      // 滚动模式：点中间呼出工具栏（用抽屉替代）
      final dx = localPosition.dx / size.width;
      final dy = localPosition.dy / size.height;
      if (dy < 0.2 && dx < 0.3) {
        _prevChapter();
      } else if (dy < 0.2 && dx > 0.7) {
        _nextChapter();
      } else if (dy > 0.8) {
        _showSettingsSheet();
      }
      return;
    }
    // 翻页模式：左1/3上一页，右1/3下一页，中间呼出设置
    final dx = localPosition.dx / size.width;
    if (dx < 0.33) {
      settings.pageMode == 'vertical' ? _pageDown() : _pageUp();
    } else if (dx > 0.67) {
      settings.pageMode == 'vertical' ? _pageUp() : _pageDown();
    } else {
      _showSettingsSheet();
    }
  }

  void _pageUp() {
    if (_currentPage > 0) {
      setState(() => _currentPage--);
    } else {
      _prevChapter();
    }
  }

  void _pageDown() {
    if (_currentPage < _pages.length - 1) {
      setState(() => _currentPage++);
    } else {
      _nextChapter();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.audioVolumeUp) { _pageUp(); return KeyEventResult.handled; }
      if (event.logicalKey == LogicalKeyboardKey.audioVolumeDown) { _pageDown(); return KeyEventResult.handled; }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) { _pageUp(); return KeyEventResult.handled; }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) { _pageDown(); return KeyEventResult.handled; }
    }
    return KeyEventResult.ignored;
  }

  // ============ 章内查找 ============
  void _doSearch(String query) {
    if (query.isEmpty) { setState(() { _searchQuery = ''; _searchHits = []; }); return; }
    final hits = <int>[];
    final paras = _paragraphs;
    for (var i = 0; i < paras.length; i++) {
      if (paras[i].contains(query)) hits.add(i);
    }
    setState(() { _searchQuery = query; _searchHits = hits; });
    if (hits.isNotEmpty && SettingsService.instance.current.pageMode == 'scroll') {
      // 滚动模式：跳到第一个命中段
      _scrollToParagraph(hits.first);
    }
  }

  void _scrollToParagraph(int paraIdx) {
    // 近似滚动：按每段平均高度估算
    final settings = SettingsService.instance.current;
    final paraH = settings.fontSize * settings.lineHeight + settings.paragraphSpacing;
    final approx = (paraIdx + 3) * paraH; // +3 是标题偏移
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        approx.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _showSearchSheet() {
    final textColor = _effectiveTextColor();
    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: 16 + MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: '章内查找...',
                suffixIcon: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(sheetCtx)),
              ),
              onSubmitted: (v) {
                Navigator.pop(sheetCtx);
                _doSearch(v.trim());
              },
            ),
            const SizedBox(height: 8),
            Text('支持在当前章节内按内容定位', style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.6))),
          ],
        ),
      ),
    );
  }

  // ============ 书签 ============
  void _addBookmark() {
    final paras = _paragraphs;
    final snippet = paras.isNotEmpty ? paras.first.substring(0, paras.first.length.clamp(0, 30)) : '';
    final bm = Bookmark(
      id: '${widget.aid}_${_currentChapter.cid}_${DateTime.now().millisecondsSinceEpoch}',
      aid: widget.aid,
      cid: _currentChapter.cid,
      chapterTitle: _currentChapter.title,
      paragraphIdx: _currentParagraphIndex(),
      snippet: snippet,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    BookmarkService.instance.add(bm);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('书签已添加：${_currentChapter.title}'), duration: const Duration(seconds: 1)));
  }

  int _currentParagraphIndex() {
    if (_scrollController.hasClients && _scrollController.position.maxScrollExtent > 0) {
      final settings = SettingsService.instance.current;
      final paraH = settings.fontSize * settings.lineHeight + settings.paragraphSpacing;
      return (_scrollController.offset / paraH).floor().clamp(0, _paragraphs.length - 1);
    }
    return 0;
  }

  void _showBookmarks() {
    final bookmarks = BookmarkService.instance.forBook(widget.aid).toList();
    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('书签', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            if (bookmarks.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('暂无书签', style: TextStyle(color: Colors.grey)))),
            ...bookmarks.map((b) => ListTile(
              leading: const Icon(Icons.bookmark),
              title: Text(b.chapterTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(b.snippet, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
              trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () { BookmarkService.instance.remove(b.id); Navigator.pop(sheetCtx); }),
              onTap: () {
                Navigator.pop(sheetCtx);
                // 定位到书签章节
                final target = _flatChapters.indexWhere((c) => c.cid == b.cid);
                if (target >= 0 && target != _chapterIdx) { _chapterIdx = target; _loadChapter(); }
              },
            )),
          ],
        ),
      ),
    );
  }

  Color _effectiveTextColor() {
    final settings = SettingsService.instance.current;
    return settings.nightMode
        ? _textColors[4]
        : _textColors[settings.backgroundColorIndex.clamp(0, _textColors.length - 2)];
  }

  Color _effectiveBgColor() {
    final settings = SettingsService.instance.current;
    return settings.nightMode
        ? _bgColors[4]
        : _bgColors[settings.backgroundColorIndex.clamp(0, _bgColors.length - 2)];
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance.current;
    final bgColor = _effectiveBgColor();
    final textColor = _effectiveTextColor();
    final indentStr = '　' * settings.indent;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: bgColor,
          foregroundColor: textColor,
          title: Text(_currentChapter.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16)),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
          actions: [
            IconButton(icon: const Icon(Icons.search), onPressed: _showSearchSheet, tooltip: '章内查找'),
            IconButton(icon: const Icon(Icons.headphones_outlined), onPressed: _showTtsSheet, tooltip: '听书'),
            IconButton(icon: const Icon(Icons.download_outlined), onPressed: _cacheWholeBook, tooltip: '缓存全本'),
            IconButton(icon: const Icon(Icons.bookmark_add_outlined), onPressed: _addBookmark, tooltip: '添加书签'),
            IconButton(icon: const Icon(Icons.bookmarks_outlined), onPressed: _showBookmarks, tooltip: '书签列表'),
            IconButton(icon: const Icon(Icons.toc), onPressed: () => _scaffoldKey.currentState?.openEndDrawer()),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('加载失败: $_error', style: TextStyle(color: Colors.grey), textAlign: TextAlign.center)))
                : _buildBody(settings, textColor, indentStr),
        bottomNavigationBar: _loading ? null : _buildBottomBar(settings, textColor),
        endDrawer: Drawer(
          backgroundColor: bgColor,
          child: _buildTocDrawer(textColor),
        ),
      ),
    );
  }

  Widget _buildBody(ReaderSettings settings, Color textColor, String indentStr) {
    if (settings.pageMode == 'scroll') {
      return _buildScrollBody(settings, textColor, indentStr);
    }
    return _buildPageBody(settings, textColor, indentStr);
  }

  // ============ 滚动模式 ============
  Widget _buildScrollBody(ReaderSettings settings, Color textColor, String indentStr) {
    final paras = _paragraphs;
    return GestureDetector(
      onTapUp: (d) => _tapZone(d.localPosition, context.size ?? Size.zero),
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: EdgeInsets.symmetric(horizontal: settings.marginH, vertical: settings.marginV),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Text(_currentChapter.title, style: TextStyle(fontSize: settings.fontSize + 4, fontWeight: FontWeight.bold, color: textColor, height: 1.5))),
            const SizedBox(height: 24),
            ...paras.asMap().entries.map((e) {
              final isHit = _searchHits.contains(e.key);
              return Padding(
                padding: EdgeInsets.only(bottom: settings.paragraphSpacing),
                child: Container(
                  decoration: isHit ? BoxDecoration(color: Colors.yellow.withOpacity(0.25), borderRadius: BorderRadius.circular(4)) : null,
                  padding: isHit ? const EdgeInsets.symmetric(horizontal: 4) : EdgeInsets.zero,
                  child: Text(
                    '$indentStr${e.value}',
                    style: TextStyle(
                      fontSize: settings.fontSize,
                      height: settings.lineHeight,
                      color: textColor,
                      fontFamily: settings.fontFamily == 'system' ? null : settings.fontFamily,
                    ),
                    textAlign: settings.justifyText ? TextAlign.justify : TextAlign.left,
                  ),
                ),
              );
            }),
            const SizedBox(height: 48),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_chapterIdx > 0)
                  TextButton(onPressed: _prevChapter, child: Text('上一章', style: TextStyle(color: textColor)))
                else const SizedBox(),
                if (settings.showProgress)
                  Text('${((_chapterIdx + 1) / _flatChapters.length * 100).toStringAsFixed(1)}%', style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 12))
                else
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
    );
  }

  // ============ 翻页模式（横排 PageView；竖排暂用同布局+反向操作） ============
  Widget _buildPageBody(ReaderSettings settings, Color textColor, String indentStr) {
    return GestureDetector(
      onTapUp: (d) => _tapZone(d.localPosition, context.size ?? Size.zero),
      child: PageView.builder(
        controller: _pageController,
        reverse: settings.pageMode == 'vertical',
        itemCount: _pages.length,
        onPageChanged: (i) => setState(() => _currentPage = i),
        itemBuilder: (ctx, i) {
          final anim = settings.pageAnim;
          Widget page = Padding(
            padding: EdgeInsets.symmetric(horizontal: settings.marginH, vertical: settings.marginV),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Text(_currentChapter.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: settings.fontSize + 2, fontWeight: FontWeight.bold, color: textColor))),
                const SizedBox(height: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _pages[i].map((p) => Padding(
                      padding: EdgeInsets.only(bottom: settings.paragraphSpacing),
                      child: Text(
                        '$indentStr$p',
                        style: TextStyle(
                          fontSize: settings.fontSize,
                          height: settings.lineHeight,
                          color: textColor,
                          fontFamily: settings.fontFamily == 'system' ? null : settings.fontFamily,
                        ),
                        textAlign: settings.justifyText ? TextAlign.justify : TextAlign.left,
                      ),
                    )).toList(),
                  ),
                ),
                Text('${i + 1}/${_pages.length}', style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.4))),
              ],
            ),
          );
          // cover 动画：在 PageView 中通过 viewportFraction 不易实现，直接返回 page
          // （PageView 默认即 slide 动画；none 用 physics 关闭不了 here，保持 slide 即可）
          return page;
        },
      ),
    );
  }

  Widget _buildBottomBar(ReaderSettings settings, Color textColor) {
    return BottomAppBar(
      color: _effectiveBgColor(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(icon: Icon(Icons.chevron_left, color: textColor), onPressed: _chapterIdx > 0 ? _prevChapter : null),
          TextButton(onPressed: () => _scaffoldKey.currentState?.openEndDrawer(), child: Text('目录', style: TextStyle(color: textColor))),
          IconButton(icon: Icon(Icons.bookmarks_outlined, color: textColor), onPressed: _showBookmarks),
          IconButton(icon: Icon(Icons.tune, color: textColor), onPressed: _showSettingsSheet),
          IconButton(icon: Icon(Icons.chevron_right, color: textColor), onPressed: _chapterIdx < _flatChapters.length - 1 ? _nextChapter : null),
        ],
      ),
    );
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ReaderSettingsPanel(),
    );
  }

  // ============ 听书 ============
  bool _ttsPlaying = false;
  double _ttsRate = 1.0;
  DateTime? _ttsStopAt; // 睡眠定时

  Future<void> _showTtsSheet() async {
    final available = await TtsService.instance.isAvailable();
    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('当前设备不支持 TTS 听书')));
      }
      return;
    }
    await showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('在线听书', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filled(
                      iconSize: 40,
                      onPressed: () {
                        if (_ttsPlaying) {
                          TtsService.instance.pause();
                          setSheet(() => _ttsPlaying = false);
                        } else {
                          // 从当前段落开始朗读
                          final paras = _paragraphs;
                          final start = SettingsService.instance.current.pageMode == 'scroll'
                              ? _currentParagraphIndex()
                              : 0;
                          _speakFrom(paras, start);
                          setSheet(() => _ttsPlaying = true);
                        }
                      },
                      icon: Icon(_ttsPlaying ? Icons.pause : Icons.play_arrow),
                    ),
                    const SizedBox(width: 24),
                    IconButton.filledTonal(
                      iconSize: 32,
                      onPressed: () {
                        TtsService.instance.stop();
                        setSheet(() => _ttsPlaying = false);
                      },
                      icon: const Icon(Icons.stop),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(children: [
                  const Text('语速'),
                  Expanded(child: Slider(
                    value: _ttsRate, min: 0.5, max: 3.0, divisions: 10,
                    label: '${_ttsRate.toStringAsFixed(1)}x',
                    onChanged: (v) {
                      TtsService.instance.rate = v;
                      setSheet(() => _ttsRate = v);
                    },
                  )),
                  Text('${_ttsRate.toStringAsFixed(1)}x'),
                ]),
                const SizedBox(height: 8),
                // 睡眠定时
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  const Text('睡眠定时', style: TextStyle(fontSize: 13)),
                  ...[10, 30, 60].map((m) => ActionChip(
                    label: Text('$m分钟'),
                    onPressed: () {
                      _ttsStopAt = DateTime.now().add(Duration(minutes: m));
                      setSheet(() {});
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('将在 $m 分钟后停止朗读'), duration: const Duration(seconds: 1)));
                    },
                  )),
                ]),
                if (_ttsStopAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('定时停止：${_ttsStopAt!.hour}:${_ttsStopAt!.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _speakFrom(List<String> paras, int startIdx) async {
    await TtsService.instance.setAwaitCompletion(true);
    for (var i = startIdx; i < paras.length; i++) {
      if (_ttsStopAt != null && DateTime.now().isAfter(_ttsStopAt!)) {
        await TtsService.instance.stop();
        break;
      }
      if (!_ttsPlaying) break;
      await TtsService.instance.speak(paras[i]);
    }
    _ttsPlaying = false;
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
    _pageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}

/// 阅读设置面板（底部弹出，含翻页模式/动画/页边距/缩进/段距等）
class ReaderSettingsPanel extends StatefulWidget {
  const ReaderSettingsPanel({super.key});
  @override
  State<ReaderSettingsPanel> createState() => _ReaderSettingsPanelState();
}

class _ReaderSettingsPanelState extends State<ReaderSettingsPanel> {
  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance.current;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('阅读设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              // 翻页模式
              const Text('翻页模式', style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'scroll', label: Text('滚动'), icon: Icon(Icons.swap_vert, size: 16)),
                  ButtonSegment(value: 'horizontal', label: Text('横翻'), icon: Icon(Icons.swap_horiz, size: 16)),
                  ButtonSegment(value: 'vertical', label: Text('竖排'), icon: Icon(Icons.menu_book, size: 16)),
                ],
                selected: {settings.pageMode},
                onSelectionChanged: (s) => setState(() => SettingsService.instance.update(settings.copyWith(pageMode: s.first))),
              ),
              const SizedBox(height: 12),
              // 翻页动画
              if (settings.pageMode != 'scroll') ...[
                const Text('翻页动画', style: TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'slide', label: Text('平移')),
                    ButtonSegment(value: 'cover', label: Text('覆盖')),
                    ButtonSegment(value: 'none', label: Text('无')),
                  ],
                  selected: {settings.pageAnim},
                  onSelectionChanged: (s) => setState(() => SettingsService.instance.update(settings.copyWith(pageAnim: s.first))),
                ),
                const SizedBox(height: 12),
              ],
              // 字号
              Row(children: [
                const Text('字号', style: TextStyle(fontSize: 13)),
                Expanded(child: Slider(
                  value: settings.fontSize, min: 12, max: 32, divisions: 20,
                  label: settings.fontSize.round().toString(),
                  onChanged: (v) => setState(() => SettingsService.instance.update(settings.copyWith(fontSize: v))),
                )),
                Text('${settings.fontSize.round()}', style: const TextStyle(fontSize: 12)),
              ]),
              // 行距
              Row(children: [
                const Text('行距', style: TextStyle(fontSize: 13)),
                Expanded(child: Slider(
                  value: settings.lineHeight, min: 1.2, max: 3.0, divisions: 18,
                  label: settings.lineHeight.toStringAsFixed(1),
                  onChanged: (v) => setState(() => SettingsService.instance.update(settings.copyWith(lineHeight: v))),
                )),
                Text(settings.lineHeight.toStringAsFixed(1), style: const TextStyle(fontSize: 12)),
              ]),
              // 段距
              Row(children: [
                const Text('段距', style: TextStyle(fontSize: 13)),
                Expanded(child: Slider(
                  value: settings.paragraphSpacing, min: 0, max: 24, divisions: 12,
                  label: settings.paragraphSpacing.round().toString(),
                  onChanged: (v) => setState(() => SettingsService.instance.update(settings.copyWith(paragraphSpacing: v))),
                )),
                Text('${settings.paragraphSpacing.round()}', style: const TextStyle(fontSize: 12)),
              ]),
              // 页边距
              Row(children: [
                const Text('边距', style: TextStyle(fontSize: 13)),
                Expanded(child: Slider(
                  value: settings.marginH, min: 8, max: 56, divisions: 12,
                  label: settings.marginH.round().toString(),
                  onChanged: (v) => setState(() => SettingsService.instance.update(settings.copyWith(marginH: v, marginV: v))),
                )),
                Text('${settings.marginH.round()}', style: const TextStyle(fontSize: 12)),
              ]),
              // 缩进
              Row(children: [
                const Text('缩进', style: TextStyle(fontSize: 13)),
                Expanded(child: Slider(
                  value: settings.indent.toDouble(), min: 0, max: 4, divisions: 4,
                  label: '${settings.indent}字',
                  onChanged: (v) => setState(() => SettingsService.instance.update(settings.copyWith(indent: v.round()))),
                )),
                Text('${settings.indent}字', style: const TextStyle(fontSize: 12)),
              ]),
              const SizedBox(height: 8),
              // 对齐
              SwitchListTile(
                dense: true,
                title: const Text('两端对齐', style: TextStyle(fontSize: 14)),
                value: settings.justifyText,
                onChanged: (v) => setState(() => SettingsService.instance.update(settings.copyWith(justifyText: v))),
              ),
              SwitchListTile(
                dense: true,
                title: const Text('显示进度百分比', style: TextStyle(fontSize: 14)),
                value: settings.showProgress,
                onChanged: (v) => setState(() => SettingsService.instance.update(settings.copyWith(showProgress: v))),
              ),
              SwitchListTile(
                dense: true,
                title: const Text('夜间模式', style: TextStyle(fontSize: 14)),
                value: settings.nightMode,
                onChanged: (v) => setState(() => SettingsService.instance.update(settings.copyWith(nightMode: v))),
              ),
              const SizedBox(height: 8),
              // 背景色
              const Text('背景', style: TextStyle(fontSize: 13, color: Colors.grey)),
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
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
