/// 书架页：三种视图（轮播/网格/列表）、自定义分类、来源与分类叠加筛选
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/local_import.dart';
import '../services/services.dart';
import 'book_detail_page.dart';
import 'reader_page.dart';

class ShelfPage extends StatefulWidget {
  const ShelfPage({super.key});
  @override
  State<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends State<ShelfPage> {
  String _view = 'grid'; // carousel / grid / list
  String? _categoryFilter; // 自定义分类筛选
  String? _sourceFilter; // wenku8 / linovelib / local / null=全部
  final _carouselController = PageController(viewportFraction: 0.55);
  int _currentCarousel = 0;

  // ============ 自定义分类管理 ============
  static const _catsKey = 'shelf_categories';
  Map<String, List<String>> _categories = {}; // 分类名 -> aid 列表

  Future<void> _loadCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_catsKey);
    if (json != null) {
      final Map<dynamic, dynamic> raw = jsonDecode(json);
      _categories = raw.map((k, v) => MapEntry(k.toString(), (v as List).map((e) => e.toString()).toList()));
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _saveCategories() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_catsKey, jsonEncode(_categories));
  }

  Future<void> _manageCategories() async {
    final entries = _allEntries();
    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(padding: EdgeInsets.all(16), child: Text('分类管理', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
              // 现有分类
              ..._categories.keys.map((cat) => ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text('$cat (${_categories[cat]!.length})'),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () {
                  setState(() { _categories.remove(cat); });
                  setSheet(() {});
                  _saveCategories();
                }),
                onTap: () { Navigator.pop(sheetCtx); setState(() => _categoryFilter = cat); },
              )),
              // 新建分类
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('新建分类'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _createCategory(entries);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createCategory(List<ShelfEntry> entries) async {
    final nameCtl = TextEditingController();
    final selected = <String>{};
    await showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setDlg) => AlertDialog(
          title: const Text('新建分类'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtl, decoration: const InputDecoration(hintText: '分类名称')),
                const SizedBox(height: 12),
                SizedBox(
                  height: 300,
                  child: ListView(
                    children: entries.map((e) => CheckboxListTile(
                      dense: true,
                      title: Text(e.book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      value: selected.contains(e.book.aid),
                      onChanged: (v) => setDlg(() => v! ? selected.add(e.book.aid) : selected.remove(e.book.aid)),
                    )).toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('取消')),
            TextButton(
              onPressed: () {
                final name = nameCtl.text.trim();
                if (name.isNotEmpty && selected.isNotEmpty) {
                  setState(() { _categories[name] = selected.toList(); });
                  _saveCategories();
                }
                Navigator.pop(dlgCtx);
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _assignToCategory(String aid, String title) async {
    final cats = _categories.keys.toList();
    final sel = await showDialog<String>(context: context, builder: (dlgCtx) => SimpleDialog(
      title: Text('将「$title」移入分类'),
      children: [
        ...cats.map((c) => SimpleDialogOption(
          onPressed: () {
            setState(() {
              _categories[c]!.add(aid);
            });
            _saveCategories();
            Navigator.pop(dlgCtx, c);
          },
          child: Text(c),
        )),
        if (cats.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('无可用分类，请先在右上角「分类管理」新建')),
      ],
    ));
    if (sel != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已移入「$sel」')));
    }
  }

  // ============ 数据整合 ============
  List<ShelfEntry> _allEntries() {
    final entries = ShelfService.instance.list.toList();
    // 本地书包装为 ShelfEntry
    for (final lb in LocalLibraryService.instance.books) {
      if (!entries.any((e) => e.book.aid == lb.id)) {
        entries.add(ShelfEntry(book: lb.toBook(), lastReadAt: 0));
      }
    }
    return entries;
  }

  List<ShelfEntry> _filtered() {
    var list = _allEntries();
    if (_categoryFilter != null) {
      final aids = _categories[_categoryFilter] ?? [];
      list = list.where((e) => aids.contains(e.book.aid)).toList();
    }
    if (_sourceFilter != null) {
      list = list.where((e) {
        final isLocal = e.book.aid.startsWith('local_');
        if (_sourceFilter == 'local') return isLocal;
        return e.book.source.name == _sourceFilter && !isLocal;
      }).toList();
    }return list;
  }

  // ============ 导入 ============
  Future<void> _importLocal() async {
    final files = await LocalLibraryService.instance.pickFiles();
    if (files == null || files.isEmpty) return;
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    final imported = await LocalLibraryService.instance.importAll(files);
    if (mounted) Navigator.pop(context);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(imported.isEmpty ? '导入失败（格式不支持或文件损坏）' : '成功导入 ${imported.length} 本书籍'),
      ));
      setState(() {}); // 本地书列表刷新
    }
  }

  void _openBook(ShelfEntry entry) {
    final book = entry.book;
    if (book.aid.startsWith('local_')) {
      final lb = LocalLibraryService.instance.byId(book.aid);
      if (lb != null) {
        // 注册进书架服务以记录阅读进度（若无则添加）
        if (!ShelfService.instance.contains(lb.id)) {
          ShelfService.instance.add(lb.toBook());
        }
        Navigator.push(context, MaterialPageRoute(builder: (_) => ReaderPage(aid: lb.id, book: book, volumes: lb.volumes)))
            .then((_) { if (mounted) setState(() {}); }); // 返回后刷新进度显示
        return;
      }
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => BookDetailPage(aid: book.aid, book: book)))
        .then((_) { if (mounted) setState(() {}); });
  }

  // ============ 触觉反馈 ============
  void _haptic() => HapticFeedback.lightImpact();

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('书架'),
        actions: [
          IconButton(icon: const Icon(Icons.folder_copy_outlined), tooltip: '分类管理', onPressed: _manageCategories),
          IconButton(icon: const Icon(Icons.file_upload_outlined), tooltip: '导入本地书', onPressed: _importLocal),
          IconButton(icon: Icon(
            _view == 'grid' ? Icons.view_carousel_outlined : _view == 'carousel' ? Icons.view_list : Icons.grid_view,
          ), tooltip: '切换视图', onPressed: () {
            _haptic();
            setState(() {
              _view = _view == 'grid' ? 'carousel' : _view == 'carousel' ? 'list' : 'grid';
            });
          }),
        ],
      ),
      body: Column(
        children: [
          // 筛选条
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                // 来源筛选
                ChoiceChip(label: const Text('全部来源'), selected: _sourceFilter == null, onSelected: (_) => setState(() { _sourceFilter = null; _haptic(); })),
                const SizedBox(width: 6),
                ChoiceChip(label: const Text('文库'), selected: _sourceFilter == 'wenku8', onSelected: (_) => setState(() { _sourceFilter = 'wenku8'; _haptic(); })),
                const SizedBox(width: 6),
                ChoiceChip(label: const Text('哔哩'), selected: _sourceFilter == 'linovelib', onSelected: (_) => setState(() { _sourceFilter = 'linovelib'; _haptic(); })),
                const SizedBox(width: 6),
                ChoiceChip(label: const Text('本地'), selected: _sourceFilter == 'local', onSelected: (_) => setState(() { _sourceFilter = 'local'; _haptic(); })),
                const VerticalDivider(width: 16),
                // 分类筛选
                ChoiceChip(label: const Text('全部分类'), selected: _categoryFilter == null, onSelected: (_) => setState(() => _categoryFilter = null)),
                ..._categories.keys.map((c) => Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ChoiceChip(label: Text(c), selected: _categoryFilter == c, onSelected: (_) => setState(() { _categoryFilter = c; _haptic(); })),
                )),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final entries = _filtered();
    if (entries.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bookmarks_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('书架空空如也', style: TextStyle(color: Colors.grey, fontSize: 16)),
            SizedBox(height: 8),
            Text('去发现页添加书籍，或点右上角导入本地书', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    switch (_view) {
      case 'carousel': return _buildCarousel(entries);
      case 'list': return _buildList(entries);
      default: return _buildGrid(entries);
    }
  }

  // ============ 轮播视图 ============
  Widget _buildCarousel(List<ShelfEntry> entries) {
    return PageView.builder(
      controller: _carouselController,
      itemCount: entries.length,
      onPageChanged: (i) { _haptic(); setState(() => _currentCarousel = i); },
      itemBuilder: (ctx, i) {
        final entry = entries[i];
        final isCurrent = i == _currentCarousel;
        return AnimatedScale(
          scale: isCurrent ? 1.0 : 0.85,
          duration: const Duration(milliseconds: 250),
          child: AnimatedOpacity(
            opacity: isCurrent ? 1.0 : 0.6,
            duration: const Duration(milliseconds: 250),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
              child: Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _openBook(entry),
                      onLongPress: () => _entryMenu(entry),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(isCurrent ? 0.3 : 0.1), blurRadius: 16, offset: const Offset(0, 8))],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: entry.book.coverUrl != null && entry.book.coverUrl!.isNotEmpty
                              ? CachedNetworkImage(imageUrl: entry.book.coverUrl!, fit: BoxFit.cover, width: double.infinity,
                                  errorWidget: (_, __, ___) => _coverFallback(entry.book))
                              : _coverFallback(entry.book),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(entry.book.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  if (entry.lastChapterTitle != null)
                    Text('读到：${entry.lastChapterTitle}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _coverFallback(Book book) => Container(
    color: const Color(0xFFE8DCC8),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(16),
    child: Text(book.title, maxLines: 4, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF5B4636))),
  );

  // ============ 网格视图 ============
  Widget _buildGrid(List<ShelfEntry> entries) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140, childAspectRatio: 0.65, crossAxisSpacing: 12, mainAxisSpacing: 12,
      ),
      itemCount: entries.length,
      itemBuilder: (ctx, i) => _GridCard(entries[i], onOpen: _openBook, onMenu: _entryMenu),
    );
  }

  // ============ 列表视图 ============
  Widget _buildList(List<ShelfEntry> entries) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: entries.length,
      itemBuilder: (ctx, i) => _ListTile(entries[i], onOpen: _openBook, onMenu: _entryMenu),
    );
  }

  Future<void> _entryMenu(ShelfEntry entry) async {
    final action = await showModalBottomSheet<String>(context: context, builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(leading: const Icon(Icons.folder_open), title: const Text('移入分类'), onTap: () => Navigator.pop(sheetCtx, 'cat')),
          ListTile(leading: const Icon(Icons.delete_outline), title: const Text('从书架移除'), onTap: () => Navigator.pop(sheetCtx, 'del')),
        ],
      ),
    ));
    if (action == 'del') {
      await ShelfService.instance.remove(entry.book.aid);
      await LocalLibraryService.instance.remove(entry.book.aid); // 本地书同时删文件
    } else if (action == 'cat') {
      await _assignToCategory(entry.book.aid, entry.book.title);
    }
    if (mounted) setState(() {});
  }
}

class _GridCard extends StatelessWidget {
  final ShelfEntry entry;
  final void Function(ShelfEntry) onOpen;
  final Future<void> Function(ShelfEntry) onMenu;
  const _GridCard(this.entry, {required this.onOpen, required this.onMenu});

  @override
  Widget build(BuildContext context) {
    final book = entry.book;
    return GestureDetector(
      onTap: () => onOpen(entry),
      onLongPress: () => onMenu(entry),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: book.coverUrl != null && book.coverUrl!.isNotEmpty
                        ? CachedNetworkImage(imageUrl: book.coverUrl!, fit: BoxFit.cover,
                            placeholder: (_, __) => const ColoredBox(color: Color(0xFFE0E0E0), child: Center(child: Icon(Icons.book, color: Colors.grey))),
                            errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFFE0E0E0), child: Center(child: Icon(Icons.book, color: Colors.grey))))
                        : const ColoredBox(color: Color(0xFFE8DCC8), child: Center(child: Icon(Icons.book, color: Color(0xFF5B4636)))),
                  ),
                ),
                Positioned(
                  top: 4, right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: book.aid.startsWith('local_') ? Colors.teal.withOpacity(0.85)
                          : book.source == BookSource.linovelib ? Colors.orange.withOpacity(0.85)
                          : Colors.blue.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      book.aid.startsWith('local_') ? '本地' : book.source == BookSource.linovelib ? '哔哩' : '文库',
                      style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                if (entry.lastChapterTitle != null)
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      color: Colors.black.withOpacity(0.6),
                      child: Text(entry.lastChapterTitle!, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _ListTile extends StatelessWidget {
  final ShelfEntry entry;
  final void Function(ShelfEntry) onOpen;
  final Future<void> Function(ShelfEntry) onMenu;
  const _ListTile(this.entry, {required this.onOpen, required this.onMenu});

  @override
  Widget build(BuildContext context) {
    final book = entry.book;
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 50, height: 70,
          child: book.coverUrl != null && book.coverUrl!.isNotEmpty
              ? CachedNetworkImage(imageUrl: book.coverUrl!, fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFFE8DCC8)))
              : const ColoredBox(color: Color(0xFFE8DCC8), child: Center(child: Icon(Icons.book, color: Color(0xFF5B4636)))),
        ),
      ),
      title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        entry.lastChapterTitle != null ? '读到: ${entry.lastChapterTitle}' : '未开始阅读',
        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12),
      ),
      trailing: IconButton(icon: const Icon(Icons.more_vert), onPressed: () => onMenu(entry)),
      onTap: () => onOpen(entry),
    );
  }
}
