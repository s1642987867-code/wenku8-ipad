/// 页面：发现 / 书架 / 本地书库 / 详情 / 阅读 / 听书。
library;

import 'package:flutter/material.dart';

import '../api/wenku8_api.dart';
import '../api/novel_catalog.dart';
import '../models/models.dart';
import '../services/services.dart';
import '../ui/design_system.dart';
import '../ui/reader.dart';

// ---------------- 发现页（wenku8 全站目录 + 纪念站风格陈列书架） ----------------

class DiscoverPage extends StatefulWidget {
  final Wenku8Api api;
  final BookshelfService shelf;
  final TtsService? tts;
  final SettingsService? settingsService;
  const DiscoverPage(
      {super.key,
      required this.api,
      required this.shelf,
      this.tts,
      this.settingsService});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final _ctrl = TextEditingController();
  NovelCatalog? _catalog;
  List<CatalogEntry>? _results;
  String? _error;
  late PageController _shelfCtrl;
  int _shelfPage = 0;
  int _totalShelfPages = 1;
  String? _activeTag; // 标签筛选
  CatalogSort _sort = CatalogSort.popular;

  static const int _booksPerShelf = 9; // 每个陈列架 9 册（8 脊 + 1 立起）
  static const int _recentCount = 96;

  @override
  void initState() {
    super.initState();
    _shelfCtrl = PageController();
    _loadCatalog();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _shelfCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    try {
      final c = await NovelCatalog.load();
      if (!mounted) return;
      setState(() => _catalog = c);
      _updateShelfPages();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '目录加载失败：$e');
    }
  }

  void _updateShelfPages() {
    final c = _catalog;
    if (c == null) return;
    final prev = _shelfPage;
    if (_results != null) {
      _totalShelfPages =
          (_results!.length / _booksPerShelf).ceil().clamp(1, 1 << 30);
    } else if (_activeTag != null) {
      final n = c.countOf(tag: _activeTag);
      _totalShelfPages = (n / _booksPerShelf).ceil().clamp(1, 1 << 30);
    } else {
      _totalShelfPages = (_recentCount / _booksPerShelf).ceil();
    }
    if (_shelfPage >= _totalShelfPages) _shelfPage = _totalShelfPages - 1;
    if (_shelfPage < 0) _shelfPage = 0;
    // C1 修复：同步 PageController，避免筛选/搜索后像素偏移越界
    if (prev != _shelfPage && _shelfCtrl.hasClients) {
      _shelfCtrl.jumpToPage(_shelfPage);
    }
  }

  /// 当前陈列架第 [page] 组书目。
  List<CatalogEntry> _shelfBooks(int page) {
    final c = _catalog;
    if (c == null) return const [];
    List<CatalogEntry> pool;
    if (_results != null) {
      pool = _results!;
    } else if (_activeTag != null) {
      pool = c.listPage(tag: _activeTag, sort: _sort, pageSize: 1 << 30);
    } else {
      pool = c.recent(count: _recentCount);
    }
    final start = page * _booksPerShelf;
    if (start >= pool.length) return const [];
    return pool.sublist(start, (start + _booksPerShelf).clamp(0, pool.length));
  }

  void _doSearch() {
    final kw = _ctrl.text.trim();
    final c = _catalog;
    if (kw.isEmpty || c == null) return;
    final r = c.search(kw, limit: 200);
    setState(() {
      _results = r;
      _shelfPage = 0;
      _activeTag = null;
      _error = r.isEmpty ? '全站 ${c.length} 本中未找到「$kw」' : null;
    });
    _updateShelfPages();
  }

  void _clearSearch() {
    setState(() {
      _results = null;
      _error = null;
      _shelfPage = 0;
    });
    _updateShelfPages();
  }

  void _pickTag(String? tag) {
    setState(() {
      _activeTag = tag;
      _results = null;
      _error = null;
      _shelfPage = 0;
    });
    _updateShelfPages();
  }

  void _openDetail(CatalogEntry e) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BookDetailPage(
        api: widget.api,
        shelf: widget.shelf,
        tts: widget.tts,
        settingsService: widget.settingsService,
        book: e.toBook(),
      ),
    ));
  }

  Color _spineColor(int aid) {
    // 黑白为主的档案风：深浅灰 + 少量深色调
    final palette = const [
      Color(0xFF2F2B27), // 墨黑
      Color(0xFF4A4440), // 深炭
      Color(0xFF6E6259), // 暖灰
      Color(0xFF8C5A4A), // 砖红（点缀）
      Color(0xFF3D5247), // 墨绿（点缀）
      Color(0xFF41506B), // 藏蓝（点缀）
      Color(0xFF5A524B), // 灰褐
      Color(0xFF71655B), // 浅褐
    ];
    return palette[aid % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final c = _catalog;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildBrandHeader(),
          const SizedBox(height: 14),
          _buildSearchBar(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),
          if (_activeTag != null || _results != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  if (_activeTag != null)
                    _chip('标签：$_activeTag', () => _pickTag(null)),
                  if (_results != null)
                    _chip('搜索：${_ctrl.text} (${_results!.length})', _clearSearch),
                ],
              ),
            ),
          const SizedBox(height: 6),
          if (c == null)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Expanded(child: _buildShelfArea(c)),
        ],
      ),
    );
  }

  Widget _chip(String label, VoidCallback onRemove) => Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 12, color: CreamTokens.ink)),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRemove,
              child: const Icon(Icons.close, size: 14, color: CreamTokens.inkSoft),
            ),
          ],
        ),
      );

  /// 品牌头：方形黑标 "W8" + 轻小说文库 + 英文副题 + 右侧搜索图标。
  Widget _buildBrandHeader() => Row(
        children: [
          Container(
            width: 44,
            height: 44,
            color: Colors.black,
            alignment: Alignment.center,
            child: const Text('W8',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('轻小说文库',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                        fontFamily: 'Songti',
                        letterSpacing: 2)),
                SizedBox(height: 2),
                Text('WENKU8 / READING ARCHIVE',
                    style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 3,
                        color: CreamTokens.inkSoft)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black54),
            onPressed: () {
              // m4 修复：收起键盘并执行搜索（原 new FocusNode() 泄漏）
              FocusScope.of(context).unfocus();
              _doSearch();
            },
          ),
        ],
      );

  Widget _buildSearchBar() => Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0x1A000000)),
              ),
              child: TextField(
                controller: _ctrl,
                onSubmitted: (_) => _doSearch(),
                decoration: const InputDecoration(
                  hintText: '搜索书名 / 作者 / 标签 · 全站 3892 本',
                  border: InputBorder.none,
                  isDense: true,
                ),
                style: const TextStyle(color: CreamTokens.ink, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _doSearch,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
            ),
          ),
        ],
      );

  /// 陈列区：若干层陈列架（PageView 翻页） + 热门标签 + 翻页指示器。
  Widget _buildShelfArea(NovelCatalog c) {
    final tags = c.allTags(limit: 14);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 区块标题：01 / CATALOG —— 最近更新 / 标签名
        Row(
          children: [
            Text(_activeTag != null ? '02 / TAG' : '01 / CATALOG',
                style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 2,
                    color: CreamTokens.inkSoft,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Container(width: 40, height: 1, color: CreamTokens.glassBorder),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _results != null
                    ? '搜索结果'
                    : (_activeTag ?? '最近更新'),
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                    fontFamily: 'Songti'),
              ),
            ),
            if (_totalShelfPages > 1)
              Text('${_shelfPage + 1} / $_totalShelfPages',
                  style: const TextStyle(
                      fontSize: 11, color: CreamTokens.inkSoft)),
          ],
        ),
        const SizedBox(height: 10),
        // 陈列架翻页
        Expanded(
          child: PageView.builder(
            controller: _shelfCtrl,
            itemCount: _totalShelfPages,
            onPageChanged: (i) => setState(() => _shelfPage = i),
            itemBuilder: (context, page) {
              final books = _shelfBooks(page);
              if (books.isEmpty) {
                return const Center(
                    child: Text('没有更多了',
                        style: TextStyle(color: CreamTokens.inkSoft)));
              }
              // 每架 9 本：第 4 本立起（index 4），其余作书脊
              final upright = 4.clamp(0, books.length - 1);
              final displayBooks = [
                for (var i = 0; i < books.length; i++)
                  DisplayBook(
                    aid: '${books[i].aid}',
                    title: books[i].title,
                    author: books[i].author,
                    coverUrl: NovelCatalog.coverUrl(books[i].aid),
                    spineColor: _spineColor(books[i].aid),
                  ),
              ];
              return DisplayShelf(
                books: displayBooks,
                uprightIndex: upright,
                onBookTap: (b) {
                  final aid = int.tryParse(b.aid);
                  final e = aid == null ? null : c.byAid(aid);
                  if (e != null) _openDetail(e);
                },
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // 翻页控制
        if (_totalShelfPages > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed: _shelfPage > 0
                    ? () => _shelfCtrl.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut)
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                    '${(_shelfPage + 1).toString().padLeft(2, '0')} / ${_totalShelfPages.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                        fontSize: 12,
                        color: CreamTokens.inkSoft,
                        letterSpacing: 2)),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed: _shelfPage < _totalShelfPages - 1
                    ? () => _shelfCtrl.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut)
                    : null,
              ),
            ],
          ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            _results != null || _activeTag != null
                ? '已经到底了'
                : '全站共 ${c.length} 本 · 点书可查看详情',
            style: const TextStyle(
                fontSize: 11, color: CreamTokens.inkSoft, letterSpacing: 1),
          ),
        ),
        const SizedBox(height: 10),
        // 热门标签
        SizedBox(
          height: 30,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final (t, n) in tags)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text('$t · $n',
                        style: const TextStyle(fontSize: 11)),
                    backgroundColor: _activeTag == t
                        ? Colors.black
                        : Colors.white,
                    labelStyle: TextStyle(
                        fontSize: 11,
                        color: _activeTag == t
                            ? Colors.white
                            : CreamTokens.ink),
                    side: const BorderSide(color: Color(0x1A000000)),
                    onPressed: () => _pickTag(t),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------- 书架页 ----------------

class ShelfPage extends StatelessWidget {
  final BookshelfService shelf;
  final LocalLibraryService library;
  final Wenku8Api api;
  final TtsService? tts;
  final SettingsService? settingsService;
  const ShelfPage({
    super.key,
    required this.shelf,
    required this.library,
    required this.api,
    this.tts,
    this.settingsService,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ShelfEntry>>(
      stream: shelf.stream,
      initialData: shelf.entries,
      builder: (context, snap) {
        final entries = snap.data ?? [];
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const ArchiveHeader(title: '书架', note: '阅读进度 · 立体陈列'),
              const SizedBox(height: 16),
              Expanded(
                child: entries.isEmpty
                    ? const Center(
                        child: Text('书架空空如也，去「发现」找几本书吧',
                            style: TextStyle(color: CreamTokens.inkSoft)))
                    : SingleChildScrollView(
                        child: Column(
                          children: [
                            for (var start = 0;
                                start < entries.length;
                                start += 6)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 18),
                                child: BookshelfLayer(
                                  books: [
                                    for (var i = start;
                                        i < (start + 6).clamp(0, entries.length);
                                        i++)
                                      ShelfBook(
                                        aid: entries[i].book.aid,
                                        title: entries[i].book.title,
                                        progressNote: entries[i].lastChapterTitle,
                                      ),
                                  ],
                                  onBookTap: (b) => _open(context, b.aid),
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _open(BuildContext context, String aid) {
    final entry = shelf.get(aid);
    if (entry == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BookDetailPage(
        api: api,
        shelf: shelf,
        library: library,
        tts: tts,
        settingsService: settingsService,
        book: entry.book,
      ),
    ));
  }
}

// ---------------- 本地书库页 ----------------

class LibraryPage extends StatefulWidget {
  final LocalLibraryService library;
  final BookshelfService shelf;
  final Wenku8Api api;
  final TtsService? tts;
  final SettingsService? settingsService;
  const LibraryPage({
    super.key,
    required this.library,
    required this.shelf,
    required this.api,
    this.tts,
    this.settingsService,
  });

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  int? _size;

  @override
  void initState() {
    super.initState();
    _refreshSize();
  }

  void _refreshSize() {
    widget.library.sizeBytes().then((v) {
      if (!mounted) return;
      setState(() => _size = v);
    });
  }

  @override
  void didUpdateWidget(LibraryPage old) {
    super.didUpdateWidget(old);
    _refreshSize();
  }

  String _fmt(int? bytes) {
    if (bytes == null) return '…';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    // m5 修复：用 StreamBuilder 跟随书架变化（IndexedStack 下 State 不再销毁重建）
    return StreamBuilder<List<ShelfEntry>>(
      stream: widget.shelf.stream,
      builder: (context, snap) {
        final entries = snap.data ?? widget.shelf.entries;
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
          const ArchiveHeader(title: '本地书库', note: '离线缓存 · 常驻可读'),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text('缓存占用 ${_fmt(_size)}',
                style: const TextStyle(color: CreamTokens.inkSoft, fontSize: 12)),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                for (final e in entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ArchiveCard(
                      serial: 'L-${e.book.aid}',
                      title: e.book.title,
                      subtitle:
                          '最后阅读：${e.lastChapterTitle ?? '未开始'}',
                      tags: const ['离线'],
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BookDetailPage(
                            api: widget.api,
                            shelf: widget.shelf,
                            library: widget.library,
                            tts: widget.tts,
                            settingsService: widget.settingsService,
                            book: e.book,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
          ),
        );
      },
    );
  }
}

// ---------------- 详情页 ----------------

class BookDetailPage extends StatefulWidget {
  final Wenku8Api api;
  final BookshelfService shelf;
  final LocalLibraryService? library;
  final TtsService? tts;
  final SettingsService? settingsService;
  final Book book;
  const BookDetailPage({
    super.key,
    required this.api,
    required this.shelf,
    this.library,
    this.tts,
    this.settingsService,
    required this.book,
  });

  @override
  State<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends State<BookDetailPage> {
  Book? _detail;
  List<Volume>? _volumes;
  String? _error;
  DownloadProgress? _dlProgress;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (book, volumes) = await widget.api.bookDetail(widget.book.aid);
      if (!mounted) return;
      setState(() {
        _detail = book;
        _volumes = volumes;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _downloadAll() async {
    if (widget.library == null || _volumes == null) return;
    await widget.library!.downloadBook(_detail ?? widget.book, _volumes!,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _dlProgress = p);
        });
    if (!mounted) return;
    setState(() => _dlProgress = null);
  }

  @override
  Widget build(BuildContext context) {
    final b = _detail ?? widget.book;
    // M3 修复：封面 URL 保持入口稳定，避免 _load 后换 URL 引起闪烁/黑块
    final coverUrl = widget.book.coverUrl ?? _detail?.coverUrl;
    return Scaffold(
      backgroundColor: CreamTokens.bgBase,
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                BackButton(onPressed: () => Navigator.pop(context)),
                Expanded(
                  child: ArchiveHeader(title: b.title, note: '档案编号 A-${b.aid}'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 档案头部：封面 + 元信息（黑白档案风）
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 96,
                  height: 132,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0x22000000)),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x2E000000),
                          blurRadius: 10,
                          offset: Offset(2, 4)),
                    ],
                  ),
                  child: coverUrl != null
                      ? Image.network(
                          coverUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: const Color(0xFF2B2B2B),
                            alignment: Alignment.center,
                            child: Text(
                              b.title,
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Songti'),
                            ),
                          ),
                        )
                      : const SizedBox.expand(),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${b.author.isEmpty ? "佚名" : b.author}  ·  ${b.status ?? "未知"}',
                          style: const TextStyle(
                              fontSize: 13, color: CreamTokens.ink)),
                      if (b.pubAgent != null && b.pubAgent!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('文库：${b.pubAgent}',
                              style: const TextStyle(
                                  fontSize: 12, color: CreamTokens.inkSoft)),
                        ),
                      if (b.catalogs.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final t in b.catalogs.take(6))
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(t,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          letterSpacing: 1)),
                                ),
                            ],
                          ),
                        ),
                      if (b.intro != null && b.intro!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            b.intro!,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12,
                                color: CreamTokens.inkSoft,
                                height: 1.5),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: CreamTokens.accent),
                  onPressed: (_volumes == null ||
                          _volumes!.every((v) => v.chapters.isEmpty))
                      ? null
                      : () {
                          try {
                            _openReader(context, firstChapterOf(_volumes!));
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.toString())),
                            );
                          }
                        },
                  icon: const Icon(Icons.menu_book),
                  label: const Text('开始阅读'),
                ),
                OutlinedButton.icon(
                  onPressed: _volumes == null ? null : _downloadAll,
                  icon: const Icon(Icons.download),
                  label: Text(_dlProgress == null
                      ? '整本离线'
                      : '下载 ${(_dlProgress!.ratio * 100).toStringAsFixed(0)}%'),
                ),
                StreamBuilder<TtsState>(
                  // M3 修复：使用全局注入的 tts 实例（原来 _tts 从未赋值，恒为 null）
                  stream: widget.tts?.stateStream ?? const Stream.empty(),
                  builder: (context, s) => OutlinedButton.icon(
                    onPressed: (_volumes == null ||
                            _volumes!.every((v) => v.chapters.isEmpty))
                        ? null
                        : () {
                            try {
                              _listen(context, firstChapterOf(_volumes!));
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.toString())),
                              );
                            }
                          },
                    icon: Icon(s.data == TtsState.playing
                        ? Icons.pause_circle
                        : Icons.graphic_eq),
                    label: const Text('在线听书'),
                  ),
                ),
              ],
            ),
            if (_dlProgress != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _dlProgress!.ratio),
            ],
            const SizedBox(height: 12),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            Expanded(
              child: _volumes == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      children: [
                        for (final v in _volumes!) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(v.title,
                                style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: CreamTokens.ink,
                                    fontFamily: 'Songti')),
                          ),
                          for (final c in v.chapters)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.description_outlined,
                                  size: 18, color: CreamTokens.inkSoft),
                              title: Text(c.title,
                                  style: const TextStyle(
                                      fontSize: 14, color: CreamTokens.ink)),
                              onTap: () => _openReader(context, c),
                              trailing: FutureBuilder<bool>(
                                future: widget.library != null
                                    ? widget.library!.cache
                                        .exists(c.aid, c.cid)
                                    : Future.value(false),
                                builder: (_, s) => s.data == true
                                    ? const Icon(Icons.offline_pin,
                                        size: 16, color: CreamTokens.accent)
                                    : const SizedBox(width: 16),
                              ),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Chapter firstChapterOf(List<Volume> vols) {
    final entry = widget.shelf.get(widget.book.aid);
    if (entry?.lastCid != null) {
      for (final v in vols) {
        for (final c in v.chapters) {
          if (c.cid == entry!.lastCid) return c;
        }
      }
    }
    for (final v in vols) {
      if (v.chapters.isNotEmpty) return v.chapters.first;
    }
    throw Wenku8Exception('本书未解析出任何章节，无法阅读');
  }

  void _openReader(BuildContext context, Chapter chapter) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReaderPage(
        api: widget.api,
        shelf: widget.shelf,
        book: _detail ?? widget.book,
        chapter: chapter,
        volumes: _volumes ?? const [],
        library: widget.library,
        tts: widget.tts,
        settingsService: widget.settingsService,
      ),
    ));
  }

  void _listen(BuildContext context, Chapter chapter) {
    _openReader(context, chapter);
  }
}

// ---------------- 阅读页（含听书控制） ----------------

class ReaderPage extends StatefulWidget {
  final Wenku8Api api;
  final BookshelfService shelf;
  final Book book;
  final Chapter chapter;
  final List<Volume> volumes;
  final LocalLibraryService? library;
  final TtsService? tts;
  final SettingsService? settingsService;
  const ReaderPage({
    super.key,
    required this.api,
    required this.shelf,
    required this.book,
    required this.chapter,
    required this.volumes,
    this.library,
    this.tts,
    this.settingsService,
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  String? _content;
  String? _error;
  late Chapter _chapter = widget.chapter;
  // M4 修复：初始值取持久化设置
  late ReaderSettings _settings = _loadSettings();

  ReaderSettings _loadSettings() {
    final s = widget.settingsService;
    return s != null ? s.settings : const ReaderSettings();
  }

  void _updateSettings(ReaderSettings s) {
    setState(() => _settings = s);
    widget.settingsService?.update(s);
  }
  int _loadSeq = 0; // 章节加载竞态防护（M1）

  @override
  void initState() {
    super.initState();
    _loadChapter();
  }

  Future<void> _loadChapter() async {
    final seq = ++_loadSeq;
    final chapter = _chapter; // 快照，防快速切换串章
    setState(() {
      _content = null;
      _error = null;
    });
    // 离线优先
    if (widget.library != null) {
      final cached = await widget.library!.cache.get(chapter.aid, chapter.cid);
      if (!mounted || seq != _loadSeq) return;
      if (cached != null) {
        setState(() => _content = cached);
        // M2 修复：缓存命中也保存进度
        await widget.shelf.addOrUpdate(widget.book,
            lastCid: chapter.cid, lastChapterTitle: chapter.title);
        return;
      }
    }
    try {
      final text = await widget.api.chapterContent(chapter.aid, chapter.cid);
      if (!mounted || seq != _loadSeq) return;
      if (widget.library != null) {
        await widget.library!.cache.put(chapter.aid, chapter.cid, text);
      }
      setState(() => _content = text);
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() => _error = e.toString());
    }
    // 记录进度
    await widget.shelf.addOrUpdate(widget.book,
        lastCid: chapter.cid, lastChapterTitle: chapter.title);
  }

  void _jumpTo(Chapter c) {
    setState(() => _chapter = c);
    _loadChapter();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CreamTokens.bgBase,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: CreamTokens.ink,
        title: Text(_chapter.title,
            style: const TextStyle(
                fontSize: 16,
                color: CreamTokens.ink,
                fontWeight: FontWeight.w600)),
        actions: [
          if (widget.tts != null)
            IconButton(
              tooltip: '听书',
              onPressed: () async {
                final tts = widget.tts!;
                if (_content == null) return;
                if (tts.state == TtsState.playing) {
                  await tts.pause();
                } else {
                  await tts.playChapter(
                      _chapter.aid, _chapter.cid, _content!);
                }
                setState(() {});
              },
              icon: const Icon(Icons.graphic_eq),
            ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
          : _content == null
              ? const Center(child: CircularProgressIndicator())
              : ReaderView(
                  title: _chapter.title,
                  content: _content!,
                  settings: _settings,
                  onSettingsChanged: _updateSettings,
                  onPrevChapter: () => _step(-1),
                  onNextChapter: () => _step(1),
                ),
    );
  }

  void _step(int dir) {
    final flat = [
      for (final v in widget.volumes) ...v.chapters
    ];
    final idx = flat.indexWhere((c) => c.cid == _chapter.cid);
    final next = idx + dir;
    if (next >= 0 && next < flat.length) {
      _jumpTo(flat[next]);
    }
  }
}
