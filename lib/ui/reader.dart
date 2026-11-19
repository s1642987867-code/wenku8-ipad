/// 阅读器：滚动 / 横排翻页 / 竖排翻页 / 大屏对页。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import 'design_system.dart';

/// 阅读器统一入口。
class ReaderView extends StatefulWidget {
  final String title;
  final String content;
  final ReaderSettings settings;
  final ValueChanged<ReaderSettings>? onSettingsChanged;
  final VoidCallback? onPrevChapter;
  final VoidCallback? onNextChapter;
  // 书签
  final String? aid;
  final String? cid;
  final BookmarkService? bookmarkService;
  // 段落索引回调（书签/TTS 跟踪用）
  final ValueChanged<int>? onParagraphVisible;
  final int? initialParagraph; // 跳转到指定段（书签定位）
  const ReaderView({
    super.key,
    required this.title,
    required this.content,
    required this.settings,
    this.onSettingsChanged,
    this.onPrevChapter,
    this.onNextChapter,
    this.aid,
    this.cid,
    this.bookmarkService,
    this.onParagraphVisible,
    this.initialParagraph,
  });

  @override
  State<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<ReaderView> {
  late ReaderSettings s = widget.settings;
  bool _autoScrolling = false;
  final _autoScrollCtrl = StreamController<double>.broadcast();
  int? _pendingJumpParagraph;
  bool _jumpConsumed = true;

  @override
  void dispose() {
    _autoScrollCtrl.close();
    super.dispose();
  }

  @override
  void didUpdateWidget(ReaderView old) {
    super.didUpdateWidget(old);
    if (old.content != widget.content) {
      s = widget.settings;
      _stopAutoScroll();
      _jumpConsumed = false;
    }
    if (old.settings != widget.settings) {
      // M7 修复：模式切换也停止自动滚动（否则图标卡在"暂停"态）
      if (old.settings.mode != widget.settings.mode) {
        _stopAutoScroll();
      }
      s = widget.settings;
    }
    if (widget.initialParagraph != null &&
        widget.initialParagraph != old.initialParagraph) {
      _pendingJumpParagraph = widget.initialParagraph;
      _jumpConsumed = false;
    }
  }

  void _toggleAutoScroll() {
    setState(() => _autoScrolling = !_autoScrolling);
    // C1 修复：真正发送速度信号（1.0 = 默认速度档，-1 = 停止）
    _autoScrollCtrl.add(_autoScrolling ? 1.0 : -1);
  }

  void _stopAutoScroll() {
    if (_autoScrolling) {
      _autoScrolling = false;
      _autoScrollCtrl.add(-1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (s.mode) {
      ReaderMode.scroll => _ScrollReader(
          content: widget.content,
          settings: s,
          autoScroll: _autoScrollCtrl.stream,
          onParagraphVisible: widget.onParagraphVisible,
          initialParagraph: _jumpConsumed ? null : _pendingJumpParagraph,
          onNextChapter: widget.onNextChapter,
        ),
      ReaderMode.horizontalPage =>
        _PageReader(content: widget.content, settings: s, axis: Axis.horizontal),
      ReaderMode.verticalPage =>
        _PageReader(content: widget.content, settings: s, axis: Axis.vertical),
      ReaderMode.twoPage => _TwoPageReader(content: widget.content, settings: s),
    };
    return Column(
      children: [
        Expanded(child: body),
        _ReaderToolbar(
          settings: s,
          onSettingsChanged: (ns) {
            setState(() => s = ns);
            widget.onSettingsChanged?.call(ns);
          },
          onPrev: widget.onPrevChapter,
          onNext: widget.onNextChapter,
          autoScrolling: _autoScrolling,
          onToggleAutoScroll: s.mode == ReaderMode.scroll
              ? _toggleAutoScroll
              : null,
        ),
      ],
    );
  }
}

/// 文本段落化。
List<String> paragraphs(String content) => content
    .split('\n')
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();

TextStyle _bodyStyle(ReaderSettings s, double? fontSizeOverride) {
  final fs = fontSizeOverride ?? s.fontSize;
  return TextStyle(
    fontSize: fs,
    height: s.lineHeight,
    color: _themeInk(s.theme),
    fontFamily: _mapFont(s.fontFamily),
  );
}

Color _themeInk(String theme) =>
    theme == 'dark' ? const Color(0xFFD8D2C6) : CreamTokens.ink;
Color _themeBg(String theme) => switch (theme) {
      'dark' => const Color(0xFF221E19),
      'paper' => const Color(0xFFFFFCF5),
      _ => CreamTokens.bgBase,
    };

String _mapFont(String name) => switch (name) {
      'Songti' => 'Songti SC',
      'Kaiti' => 'Kaiti SC',
      _ => 'PingFang SC',
    };

// ---------------- 滚动模式 ----------------

class _ScrollReader extends StatefulWidget {
  final String content;
  final ReaderSettings settings;
  final Stream<double>? autoScroll; // 速度流；-1 = 停止
  final ValueChanged<int>? onParagraphVisible;
  final int? initialParagraph;
  final VoidCallback? onNextChapter; // M1：滚到底自动衔接下一章
  const _ScrollReader({
    required this.content,
    required this.settings,
    this.autoScroll,
    this.onParagraphVisible,
    this.initialParagraph,
    this.onNextChapter,
  });

  @override
  State<_ScrollReader> createState() => _ScrollReaderState();
}

class _ScrollReaderState extends State<_ScrollReader> {
  final _ctrl = ScrollController();
  StreamSubscription<double>? _sub;
  Timer? _tick;
  double _speed = 0;

  @override
  void initState() {
    super.initState();
    // minor1 修复：保存订阅引用
    _sub = widget.autoScroll?.listen(_onAutoScroll);
    if (widget.initialParagraph != null) {
      // 初始跳段：等首帧布局后估算偏移
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToParagraph(
          widget.initialParagraph!, widget.onParagraphVisible != null));
    }
  }

  void _onAutoScroll(double speed) {
    _tick?.cancel();
    _tick = null;
    if (speed <= 0) return;
    _speed = speed;
    _tick = Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (!mounted || !_ctrl.hasClients) return;
      final px = 0.6 * _speed; // px per 40ms
      final atBottom = _ctrl.offset >=
          _ctrl.position.maxScrollExtent - 1;
      if (atBottom) {
        // M1 修复：滚到底自动衔接下一章并停表
        _tick?.cancel();
        _tick = null;
        widget.onNextChapter?.call();
        return;
      }
      _ctrl.jumpTo((_ctrl.offset + px)
          .clamp(0, _ctrl.position.maxScrollExtent));
    });
  }

  /// 估算第 [index] 段的滚动偏移（按行高近似）。M10 修复：
  /// 用真实视口宽度估 charsPerLine，去掉 linesPerPage 上限。
  double _paragraphOffset(int index) {
    const hPadding = 28.0;
    const vPadding = 24.0;
    final fs = widget.settings.fontSize;
    final lineH = fs * widget.settings.lineHeight;
    final ps = paragraphs(widget.content);
    final vw = (context.size?.width ?? 800) - hPadding * 2;
    final charsPerLine = (vw / (fs * 1.02)).floor().clamp(1, 200);
    var offset = vPadding;
    for (var i = 0; i < index && i < ps.length; i++) {
      final lines = ((ps[i].length + 2) / charsPerLine).ceil().clamp(1, 10000);
      offset += lines * lineH + 10; // 10 = separator SizedBox 高度
    }
    // 长段超过视口时 clamp 上限仍可能导致误差，但 index 未超视口时精确
    final maxOffset = _ctrl.hasClients ? _ctrl.position.maxScrollExtent : offset;
    final capped = offset.clamp(0, maxOffset);
    return capped >= 0 ? capped.toDouble() : 0.0;
  }

  void _jumpToParagraph(int index, bool notify) {
    if (!_ctrl.hasClients) return;
    _ctrl.jumpTo(_paragraphOffset(index).clamp(0, _ctrl.position.maxScrollExtent));
    if (notify) widget.onParagraphVisible?.call(index);
  }

  @override
  void didUpdateWidget(_ScrollReader old) {
    super.didUpdateWidget(old);
    if (widget.content != old.content) {
      _tick?.cancel();
      _tick = null;
      if (_ctrl.hasClients) _ctrl.jumpTo(0);
    }
    if (widget.initialParagraph != null &&
        widget.initialParagraph != old.initialParagraph &&
        _ctrl.hasClients) {
      _jumpToParagraph(widget.initialParagraph!, false);
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _sub?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ps = paragraphs(widget.content);
    return Container(
      color: _themeBg(widget.settings.theme),
      child: Scrollbar(
        controller: _ctrl,
        child: ListView.separated(
          controller: _ctrl,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          itemCount: ps.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => GestureDetector(
            onLongPress:
                widget.onParagraphVisible == null ? null : () => widget.onParagraphVisible!(i),
            child: SelectableText(
              '　　${ps[i]}',
              style: _bodyStyle(widget.settings, null),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- 翻页模式（横排 / 竖排共用分页器） ----------------

class _PageReader extends StatefulWidget {
  final String content;
  final ReaderSettings settings;
  final Axis axis;
  const _PageReader({
    super.key,
    required this.content,
    required this.settings,
    required this.axis,
  });

  @override
  State<_PageReader> createState() => _PageReaderState();
}

class _PageReaderState extends State<_PageReader> {
  final _controller = PageController();
  late List<String> _pages = const [];
  String? _lastContent;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _paginate();
  }

  @override
  void didUpdateWidget(_PageReader old) {
    super.didUpdateWidget(old);
    _paginate();
  }

  void _paginate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox;
      final size = box.size;
      final ps = paragraphs(widget.content);
      final style = _bodyStyle(widget.settings, null);
      final pages = _layoutPages(ps, style, size, widget.axis);
      final contentChanged = widget.content != _lastContent;
      setState(() => _pages = pages);
      _lastContent = widget.content;
      if (contentChanged) _controller.jumpTo(0);
    });
  }

  List<String> _layoutPages(
      List<String> ps, TextStyle style, Size size, Axis axis) {
    // 近似分页：按字符宽度估算每页可容纳字符数。
    final usable = (axis == Axis.horizontal
            ? Size(size.width - 56, size.height - 48)
            : Size(size.width - 48, size.height - 56));
    final charW = (style.fontSize ?? 19) * 1.02;
    final charsPerLine = (usable.width / charW).floor().clamp(6, 100);
    final lineH = (style.fontSize ?? 19) * (style.height ?? 1.8);
    final linesPerPage = (usable.height / lineH).floor().clamp(4, 200);
    final capacity = charsPerLine * linesPerPage;

    final pages = <String>[];
    final buf = StringBuffer();
    var count = 0.0;
    for (final p in ps) {
      final text = '　　$p\n';
      for (final ch in text.runes) {
        if (count >= capacity) {
          pages.add(buf.toString());
          buf.clear();
          count = 0;
        }
        buf.writeCharCode(ch);
        // 全角 1、半角 0.5（m5 修复：原 0.5.round() == 1 导致半角按全角计）
        count += (ch > 0x2E80) ? 1.0 : 0.5;
      }
    }
    if (buf.isNotEmpty) pages.add(buf.toString());
    return pages.isEmpty ? [''] : pages;
  }

  @override
  Widget build(BuildContext context) {
    final vertical = widget.axis == Axis.vertical;
    return Container(
      color: _themeBg(widget.settings.theme),
      child: PageView(
        scrollDirection:
            vertical ? Axis.vertical : Axis.horizontal,
        controller: _controller,
        children: [
          for (final p in _pages)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: vertical ? 24 : 28,
                vertical: vertical ? 28 : 24,
              ),
              child: vertical
                  ? // 竖排：右起竖行
                  _VerticalText(text: p, style: _bodyStyle(widget.settings, null))
                  : Text(p, style: _bodyStyle(widget.settings, null)),
            ),
        ],
      ),
    );
  }
}

/// 竖排文字：从右到左的竖行列。
class _VerticalText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const _VerticalText({required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n').where((e) => e.isNotEmpty).toList();
    return LayoutBuilder(builder: (context, cons) {
      // 每列字符数 = 可用高 / 行高
      final lineH = (style.fontSize ?? 19) * 1.15;
      final charsPerCol = (cons.maxHeight / lineH).floor().clamp(4, 200);
      final cols = <List<String>>[];
      for (final para in lines) {
        final runes = para.runes.toList();
        for (var i = 0; i < runes.length; i += charsPerCol) {
          cols.add(
            runes.sublist(i, (i + charsPerCol).clamp(0, runes.length))
                .map(String.fromCharCode)
                .toList(),
          );
        }
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true, // 右起（m3 修复：去掉 Row 的 rtl，避免双重反转）
        child: Row(
          children: [
            for (final col in cols)
              SizedBox(
                width: (style.fontSize ?? 19) * 1.5,
                child: Column(
                  children: [
                    for (final ch in col)
                      SizedBox(
                        height: lineH,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Text(ch, style: style),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
    });
  }
}

// ---------------- 大屏对页 ----------------

class _TwoPageReader extends StatefulWidget {
  final String content;
  final ReaderSettings settings;
  const _TwoPageReader({required this.content, required this.settings});

  @override
  State<_TwoPageReader> createState() => _TwoPageReaderState();
}

class _TwoPageReaderState extends State<_TwoPageReader> {
  final _controller = PageController();
  late List<List<String>> _spreads = const [];
  String? _lastContent;
  bool _narrow = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final narrow = MediaQuery.of(context).size.width <= 700;
    if (narrow != _narrow) {
      _narrow = narrow;
    }
    if (!narrow) _paginate();
  }

  @override
  void didUpdateWidget(_TwoPageReader old) {
    super.didUpdateWidget(old);
    if (!_narrow) _paginate();
  }

  void _paginate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox;
      final size = box.size;
      final ps = paragraphs(widget.content);
      final style = _bodyStyle(widget.settings, null);
      // 每个物理页拆成左右两个逻辑页。
      final single = _layoutPagesForSize(ps, style,
          Size(size.width / 2 - 40, size.height - 56));
      // 两两一组
      final spreads = <List<String>>[];
      for (var i = 0; i < single.length; i += 2) {
        spreads.add([
          single[i],
          if (i + 1 < single.length) single[i + 1] else '',
        ]);
      }
      final contentChanged = widget.content != _lastContent;
      // C2/C3 修复：_pages 与 _spreads 都在 setState 内更新
      setState(() {
        _spreads = spreads;
        _lastContent = widget.content;
      });
      if (contentChanged) _controller.jumpTo(0);
    });
  }

  List<String> _layoutPagesForSize(
      List<String> ps, TextStyle style, Size size) {
    final charW = (style.fontSize ?? 19) * 1.02;
    final charsPerLine = ((size.width) / charW).floor().clamp(6, 100);
    final lineH = (style.fontSize ?? 19) * (style.height ?? 1.8);
    final linesPerPage = ((size.height) / lineH).floor().clamp(4, 200);
    final capacity = charsPerLine * linesPerPage;
    final pages = <String>[];
    final buf = StringBuffer();
    var count = 0.0;
    for (final p in ps) {
      final text = '　　$p\n';
      for (final ch in text.runes) {
        if (count >= capacity) {
          pages.add(buf.toString());
          buf.clear();
          count = 0;
        }
        buf.writeCharCode(ch);
        count += (ch > 0x2E80) ? 1.0 : 0.5; // 与 _PageReader 一致
      }
    }
    if (buf.isNotEmpty) pages.add(buf.toString());
    return pages.isEmpty ? [''] : pages;
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 700;
    if (!isWide) {
      // 窄屏退化为单页模式（m4 修复：固定 key 防 State 混用）
      return _PageReader(
        key: const ValueKey('twopage-fallback'),
        content: widget.content,
        settings: widget.settings,
        axis: Axis.horizontal,
      );
    }
    return Container(
      color: _themeBg(widget.settings.theme),
      child: PageView(
        controller: _controller,
        children: [
          for (final spread in _spreads)
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(spread[0],
                        style: _bodyStyle(widget.settings, null)),
                  ),
                ),
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(vertical: 20),
                  color: CreamTokens.glassBorder,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(spread[1],
                        style: _bodyStyle(widget.settings, null)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ---------------- 工具栏 ----------------

class _ReaderToolbar extends StatelessWidget {
  final ReaderSettings settings;
  final ValueChanged<ReaderSettings> onSettingsChanged;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final bool autoScrolling;
  final VoidCallback? onToggleAutoScroll;
  const _ReaderToolbar({
    required this.settings,
    required this.onSettingsChanged,
    this.onPrev,
    this.onNext,
    this.autoScrolling = false,
    this.onToggleAutoScroll,
  });

  @override
  Widget build(BuildContext context) {
    const modes = [
      (ReaderMode.scroll, '滚动'),
      (ReaderMode.horizontalPage, '横排'),
      (ReaderMode.verticalPage, '竖排'),
      (ReaderMode.twoPage, '对页'),
    ];
    return CreamGlass(
      radius: BorderRadius.zero,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
          // 自动滚动（仅滚动模式可用）
          IconButton(
            tooltip: '自动滚动',
            icon: Icon(
              autoScrolling ? Icons.pause_circle_outline : Icons.vertical_align_center,
              color: autoScrolling ? Colors.black : CreamTokens.inkSoft,
            ),
            onPressed: onToggleAutoScroll,
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final (m, label) in modes)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: settings.mode == m,
                      onSelected: (_) =>
                          onSettingsChanged(settings.copyWith(mode: m)),
                    ),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.text_decrease),
                onPressed: () => onSettingsChanged(settings.copyWith(
                    fontSize: (settings.fontSize - 1).clamp(12, 40))),
              ),
              Text('${settings.fontSize.round()}',
                  style: const TextStyle(color: CreamTokens.ink)),
              IconButton(
                icon: const Icon(Icons.text_increase),
                onPressed: () => onSettingsChanged(settings.copyWith(
                    fontSize: (settings.fontSize + 1).clamp(12, 40))),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.palette_outlined),
                onSelected: (t) => onSettingsChanged(settings.copyWith(theme: t)),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'cream', child: Text('奶白')),
                  PopupMenuItem(value: 'paper', child: Text('纸白')),
                  PopupMenuItem(value: 'dark', child: Text('夜间')),
                ],
              ),
              // 行距调节弹窗
              PopupMenuButton<double>(
                tooltip: '行距',
                icon: const Icon(Icons.format_line_spacing),
                onSelected: (v) =>
                    onSettingsChanged(settings.copyWith(lineHeight: v)),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 1.5, child: Text('行距 1.5')),
                  PopupMenuItem(value: 1.8, child: Text('行距 1.8')),
                  PopupMenuItem(value: 2.0, child: Text('行距 2.0')),
                  PopupMenuItem(value: 2.4, child: Text('行距 2.4')),
                ],
              ),
              IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
            ],
          ),
        ],
      ),
    );
  }
}
