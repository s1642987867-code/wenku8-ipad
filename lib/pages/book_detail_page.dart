/// 书籍详情页：封面/简介/目录树 + 加入书架
library;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../api/linovelib_api.dart';
import '../api/web_scraper.dart';
import '../api/wenku8_api.dart';
import '../models/models.dart';
import '../services/services.dart';
import 'reader_page.dart';

class BookDetailPage extends StatefulWidget {
  final String aid;
  final Book? book;

  const BookDetailPage({super.key, required this.aid, this.book});

  @override
  State<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends State<BookDetailPage> {
  final _scraper = WebScraper();
  final _api = Wenku8Api();
  final _lino = LinovelibApi();
  Book? _book;
  List<Volume>? _volumes;
  bool _loading = true;
  String? _error;
  final _expanded = <String>{};

  @override
  void initState() {
    super.initState();
    _book = widget.book;
    _loadData();
  }

  bool get _isLino => (_book ?? widget.book)?.source == BookSource.linovelib;

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (_isLino) {
        // 哔哩轻小说源
        final nid = widget.aid.startsWith('lino_') ? widget.aid.substring(5) : widget.aid;
        final book = await _lino.bookInfo(nid);
        final vols = await _lino.toc(nid);
        _book = book;
        _volumes = vols;
        if (vols.isNotEmpty) _expanded.add(vols.first.vid);
        setState(() { _loading = false; });
        return;
      }
      // wenku8 源：优先网页爬虫获取目录（更实时）
      final (book, vols) = await _scraper.toc(widget.aid);
      _book = book;
      _volumes = vols;
      // 默认展开第一卷
      if (vols.isNotEmpty) _expanded.add(vols.first.vid);
      setState(() { _loading = false; });
    } catch (e) {
      if (_isLino) {
        setState(() { _loading = false; _error = '$e'; });
        return;
      }
      // 回退到 TXT 全本下载
      try {
        final (book, vols) = await _api.bookDetail(widget.aid);
        _book = book;
        _volumes = vols;
        if (vols.isNotEmpty) _expanded.add(vols.first.vid);
        setState(() { _loading = false; });
      } catch (e2) {
        setState(() { _loading = false; _error = '$e2'; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = _book ?? widget.book ?? Book(aid: widget.aid, title: '加载中...');
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              background: _buildHeader(book),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            SliverFillRemaining(child: Center(child: Padding(padding: EdgeInsets.all(24), child: Text('加载失败: $_error\n\nwenku8.net 可能暂时不可用。\n排行/搜索/分类需登录后访问，当前站点登录已失效。\n在线阅读（书页→目录→正文）和全本 TXT 下载仍可使用。', style: TextStyle(color: Colors.grey), textAlign: TextAlign.center))))
          else ...[
            SliverToBoxAdapter(child: _buildActions(book)),
            SliverToBoxAdapter(child: _buildIntro(book)),
            _buildTocList(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(Book book) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 模糊封面背景
        if (book.coverUrl != null)
          CachedNetworkImage(imageUrl: book.coverUrl!, fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(color: const Color(0xFF6750A4)))
        else
          Container(color: const Color(0xFF6750A4)),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: book.coverUrl ?? '',
                  width: 100, height: 140, fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(width: 100, height: 140, color: Colors.grey),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(book.title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(book.author, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    if (book.status != null)
                      Text(book.status!, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActions(Book book) {
    final inShelf = ShelfService.instance.contains(book.aid);
    final shelfEntry = ShelfService.instance.get(book.aid);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () {
                if (_volumes == null || _volumes!.isEmpty) return;
                final flatChapters = _volumes!.expand((v) => v.chapters).toList();
                int startIdx = shelfEntry?.lastChapterIdx ?? 0;
                if (startIdx >= flatChapters.length) startIdx = 0;
                final ch = flatChapters[startIdx];
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ReaderPage(
                    aid: book.aid,
                    book: book,
                    volumes: _volumes!,
                    initialChapterIdx: startIdx,
                  ),
                ));
              },
              icon: const Icon(Icons.menu_book),
              label: Text(shelfEntry?.lastChapterTitle != null ? '继续阅读' : '开始阅读'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: () async {
              if (inShelf) {
                await ShelfService.instance.remove(book.aid);
              } else {
                await ShelfService.instance.add(book);
              }
              setState(() {});
            },
            icon: Icon(inShelf ? Icons.bookmark_remove : Icons.bookmark_add),
          ),
        ],
      ),
    );
  }

  Widget _buildIntro(Book book) {
    if (book.intro == null || book.intro!.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      title: const Text('简介'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text(book.intro!, style: const TextStyle(fontSize: 14, height: 1.6)),
        ),
      ],
    );
  }

  Widget _buildTocList() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (ctx, idx) {
          final vol = _volumes![idx];
          final isExpanded = _expanded.contains(vol.vid);
          return ExpansionTile(
            title: Text(vol.title),
            initiallyExpanded: isExpanded,
            onExpansionChanged: (v) => setState(() {
              if (v) _expanded.add(vol.vid); else _expanded.remove(vol.vid);
            }),
            children: vol.chapters.asMap().entries.map((e) {
              final globalIdx = _globalChapterIndex(vol.vid, e.key);
              return ListTile(
                dense: true,
                title: Text(e.value.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ReaderPage(
                    aid: widget.aid,
                    book: _book ?? widget.book!,
                    volumes: _volumes!,
                    initialChapterIdx: globalIdx,
                  ),
                )),
              );
            }).toList(),
          );
        },
        childCount: _volumes?.length ?? 0,
      ),
    );
  }

  int _globalChapterIndex(String vid, int localIdx) {
    int count = 0;
    for (final v in _volumes!) {
      if (v.vid == vid) return count + localIdx;
      count += v.chapters.length;
    }
    return 0;
  }
}
