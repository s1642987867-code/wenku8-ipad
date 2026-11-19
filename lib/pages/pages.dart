/// 页面：发现 / 书架 / 本地书库 / 详情 / 阅读 / 听书。
library;

import 'package:flutter/material.dart';

import '../api/wenku8_api.dart';
import '../models/models.dart';
import '../services/services.dart';
import '../ui/design_system.dart';
import '../ui/reader.dart';

// ---------------- 发现页 ----------------

class DiscoverPage extends StatefulWidget {
  final Wenku8Api api;
  final BookshelfService shelf;
  const DiscoverPage({super.key, required this.api, required this.shelf});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final _ctrl = TextEditingController();
  List<Book>? _results;
  bool _loading = false;
  String? _error;

  Future<void> _doSearch() async {
    final kw = _ctrl.text.trim();
    if (kw.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    await Future.delayed(const Duration(milliseconds: 200));
    try {
      final r = widget.api.searchFeatured(kw);
      setState(() {
        _results = r;
        if (r.isEmpty) _error = '本地精选中未找到「$kw」，试试书名关键词（如：Re:、刀剑、狼与）';
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const ArchiveHeader(title: '发现', note: '轻小说文库 · 检索档案'),
          const SizedBox(height: 16),
          CreamGlass(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.search, color: CreamTokens.inkSoft),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    onSubmitted: (_) => _doSearch(),
                    decoration: const InputDecoration(
                      hintText: '书名 / 作者…',
                      border: InputBorder.none,
                    ),
                    style: const TextStyle(color: CreamTokens.ink),
                  ),
                ),
                TextButton(onPressed: _doSearch, child: const Text('检索')),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.redAccent)),
            ),
          Expanded(
            child: _results == null
                ? ListView(
                    children: [
                      const SizedBox(height: 8),
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('精选档案',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: CreamTokens.ink,
                                fontFamily: 'Songti')),
                      ),
                      for (final b in widget.api
                          .searchFeatured('')) // 全部精选
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ArchiveCard(
                            serial: 'A-${b.aid}',
                            title: b.title,
                            subtitle: b.author,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => BookDetailPage(
                                  api: widget.api,
                                  shelf: widget.shelf,
                                  book: b,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  )
                : ListView.separated(
                    itemCount: _results!.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final b = _results![i];
                      return ArchiveCard(
                        serial: 'A-${b.aid}',
                        title: b.title,
                        subtitle: '${b.author} · ${b.status ?? ''} ${b.intro ?? ''}',
                        tags: b.catalogs.take(3).toList(),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => BookDetailPage(
                              api: widget.api,
                              shelf: widget.shelf,
                              book: b,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------- 书架页 ----------------

class ShelfPage extends StatelessWidget {
  final BookshelfService shelf;
  final LocalLibraryService library;
  final Wenku8Api api;
  const ShelfPage({
    super.key,
    required this.shelf,
    required this.library,
    required this.api,
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
  const LibraryPage({
    super.key,
    required this.library,
    required this.shelf,
    required this.api,
  });

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  int? _size;

  @override
  void initState() {
    super.initState();
    widget.library.sizeBytes().then((v) => setState(() => _size = v));
  }

  String _fmt(int? bytes) {
    if (bytes == null) return '…';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.shelf.entries;
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
  }
}

// ---------------- 详情页 ----------------

class BookDetailPage extends StatefulWidget {
  final Wenku8Api api;
  final BookshelfService shelf;
  final LocalLibraryService? library;
  final Book book;
  const BookDetailPage({
    super.key,
    required this.api,
    required this.shelf,
    this.library,
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
  TtsService? _tts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (book, volumes) = await widget.api.bookDetail(widget.book.aid);
      setState(() {
        _detail = book;
        _volumes = volumes;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _downloadAll() async {
    if (widget.library == null || _volumes == null) return;
    await widget.library!.downloadBook(_detail ?? widget.book, _volumes!,
        onProgress: (p) => setState(() => _dlProgress = p));
    setState(() => _dlProgress = null);
  }

  @override
  Widget build(BuildContext context) {
    final b = _detail ?? widget.book;
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
            Wrap(
              spacing: 10,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: CreamTokens.accent),
                  onPressed: _volumes == null
                      ? null
                      : () => _openReader(context, firstChapterOf(_volumes!)),
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
                  stream: _tts?.stateStream ?? const Stream.empty(),
                  builder: (context, s) => OutlinedButton.icon(
                    onPressed: _volumes == null
                        ? null
                        : () => _listen(context, firstChapterOf(_volumes!)),
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
    return vols.first.chapters.first;
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
        tts: _tts,
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
  const ReaderPage({
    super.key,
    required this.api,
    required this.shelf,
    required this.book,
    required this.chapter,
    required this.volumes,
    this.library,
    this.tts,
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  String? _content;
  String? _error;
  late Chapter _chapter = widget.chapter;
  late ReaderSettings _settings = const ReaderSettings();

  @override
  void initState() {
    super.initState();
    _loadChapter();
  }

  Future<void> _loadChapter() async {
    setState(() {
      _content = null;
      _error = null;
    });
    // 离线优先
    if (widget.library != null) {
      final cached = await widget.library!.cache.get(_chapter.aid, _chapter.cid);
      if (cached != null) {
        setState(() => _content = cached);
        return;
      }
    }
    try {
      final text = await widget.api.chapterContent(_chapter.aid, _chapter.cid);
      if (widget.library != null) {
        await widget.library!.cache.put(_chapter.aid, _chapter.cid, text);
      }
      setState(() => _content = text);
    } catch (e) {
      setState(() => _error = e.toString());
    }
    // 记录进度
    await widget.shelf.addOrUpdate(widget.book,
        lastCid: _chapter.cid, lastChapterTitle: _chapter.title);
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
                  onSettingsChanged: (s) => setState(() => _settings = s),
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
