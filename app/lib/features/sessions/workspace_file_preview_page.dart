import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../core/models/workspace_file.dart';
import '../../core/services/dsh_api.dart';
import '../../widgets/common.dart';
import '../servers/servers_providers.dart';
import 'widgets/code_highlight.dart';
import 'widgets/detail_header.dart';

/// 图片预览支持的扩展名（与 Flutter 内置解码器一致）。
const _imageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'wbmp'};

/// 判断一个文件名是否按图片渲染。
bool isPreviewableImage(String name) =>
    _imageExtensions.contains(extensionOf(name));

/// 小写扩展名（不含点）；无扩展名返回空串。
String extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

/// 工作区文件预览：图片走 `readBytes`，其余按文本/代码渲染。
/// 代码用 re_highlight 做语法高亮（配色取自设计 token），并带行号与横向滚动；
/// 语言未覆盖或解析异常时退回纯文本，行号始终与内容对齐。
class WorkspaceFilePreviewPage extends ConsumerStatefulWidget {
  final String sessionId;
  final String? cwd;

  /// 工作区相对路径（不含开头的 `/`）。
  final String path;

  /// basename，用于标题与类型判断。
  final String name;

  const WorkspaceFilePreviewPage({
    super.key,
    required this.sessionId,
    this.cwd,
    required this.path,
    required this.name,
  });

  @override
  ConsumerState<WorkspaceFilePreviewPage> createState() =>
      _WorkspaceFilePreviewPageState();
}

class _WorkspaceFilePreviewPageState
    extends ConsumerState<WorkspaceFilePreviewPage> {
  static const _pageLines = 1000;

  late final bool _isImage = isPreviewableImage(widget.name);

  bool _loading = true;
  Object? _error;
  bool _unsupported = false;

  WorkspaceFileText? _page;
  String _text = '';
  int _nextOffset = 1;
  bool _hasMore = false;
  bool _loadingMore = false;

  Uint8List? _image;
  int? _imageBytes;

  /// 高亮结果缓存：文本/语言/深浅色任一变化才重算（1000 行解析不便宜）。
  String? _highlightKey;
  List<List<InlineSpan>>? _highlighted;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _unsupported = false;
    });
    try {
      if (_isImage) {
        await _loadImage();
      } else {
        await _loadText();
      }
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ServerException(_friendlyMessage(e), code: e.code);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadImage() async {
    final api = _api();
    final bytes = await api.readWorkspaceFileBytes(
      sessionId: widget.sessionId,
      path: widget.path,
    );
    if (!mounted) return;
    setState(() {
      _image = bytes.data;
      _imageBytes = bytes.totalBytes ?? bytes.length;
      _loading = false;
    });
  }

  Future<void> _loadText() async {
    final api = _api();
    final page = await api.readWorkspaceFile(
      sessionId: widget.sessionId,
      path: widget.path,
      limit: _pageLines,
    );
    if (!mounted) return;
    if (page.text.contains('\u0000')) {
      setState(() {
        _unsupported = true;
        _loading = false;
      });
      return;
    }
    setState(() {
      _page = page;
      _text = page.text;
      _nextOffset = page.offset + (page.lines > 0 ? page.lines : 1);
      _hasMore = !page.eof;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final api = _api();
      final page = await api.readWorkspaceFile(
        sessionId: widget.sessionId,
        path: widget.path,
        offset: _nextOffset,
        limit: _pageLines,
      );
      if (!mounted) return;
      setState(() {
        _text = _text.isEmpty ? page.text : '$_text\n${page.text}';
        _nextOffset = page.offset + (page.lines > 0 ? page.lines : 1);
        _hasMore = !page.eof;
        _loadingMore = false;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      showDshError(context, _friendlyMessage(e));
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      showDshError(context, '加载失败，请稍后重试');
    }
  }

  DshApi _api() {
    final api = ref.read(dshApiProvider);
    if (api == null) {
      throw const ServerException('服务端未连接', code: 'not_ready');
    }
    return api;
  }

  String get _subtitle {
    final cwd = widget.cwd;
    if (cwd == null || cwd.isEmpty) return widget.path;
    return '$cwd/${widget.path}';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: widget.name,
              subtitle: _subtitle,
              subtitleIcon: _isImage
                  ? Icons.image_outlined
                  : Icons.code_rounded,
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final error = _error;
    if (error != null) return ErrorView(error: error, onRetry: _load);
    if (_unsupported) {
      return const EmptyState(
        icon: Icons.visibility_off_outlined,
        message: '该文件类型暂不支持预览',
      );
    }
    if (_isImage) return _buildImage();
    return _buildCode();
  }

  Widget _buildImage() {
    final p = context.dsh;
    final data = _image;
    if (data == null || data.isEmpty) {
      return const EmptyState(
        icon: Icons.broken_image_outlined,
        message: '图片内容为空',
      );
    }
    final size = _imageBytes;
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => InteractiveViewer(
              minScale: 0.5,
              maxScale: 6,
              boundaryMargin: const EdgeInsets.all(DshSpace.x8),
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: Image.memory(
                  data,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const EmptyState(
                    icon: Icons.broken_image_outlined,
                    message: '图片解码失败',
                  ),
                ),
              ),
            ),
          ),
        ),
        if (size != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DshSpace.x4,
              DshSpace.x1,
              DshSpace.x4,
              DshSpace.x3,
            ),
            child: Text(
              '${extensionOf(widget.name).toUpperCase()} · ${_formatSize(size)}',
              style: context.dshText.bodySmall?.copyWith(color: p.tertiaryText),
            ),
          ),
      ],
    );
  }

  Widget _buildCode() {
    final page = _page;
    if (page == null || _text.isEmpty) {
      return const EmptyState(
        icon: Icons.description_outlined,
        message: '这个文件是空的',
      );
    }
    final p = context.dsh;
    // tab 宽度由字体决定，统一换成 2 空格保证行内对齐可预期。
    final source = _text.replaceAll('\t', '  ');
    final base = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Courier New'],
      fontSize: 13,
      height: 1.55,
      color: p.foreground,
    );
    final lines = _highlightedLines(source, base, p);
    final gutter = '${page.offset + lines.length - 1}'.length;
    final spans = <InlineSpan>[];
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: '\n'));
      spans.add(
        TextSpan(
          text: '${(page.offset + i).toString().padLeft(gutter)}  ',
          style: TextStyle(color: p.tertiaryText),
        ),
      );
      spans.add(TextSpan(children: lines[i]));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        DshSpace.x4,
        DshSpace.x1,
        DshSpace.x5,
        DshSpace.x6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText.rich(TextSpan(style: base, children: spans)),
          ),
          const SizedBox(height: DshSpace.x4),
          if (_hasMore)
            Center(
              child: _loadingMore
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(onPressed: _loadMore, child: const Text('加载更多')),
            )
          else
            Text(
              '已显示全部 ${page.offset + lines.length - 1} 行',
              style: context.dshText.bodySmall?.copyWith(
                color: context.dsh.tertiaryText,
              ),
            ),
        ],
      ),
    );
  }

  /// 逐行的高亮 span；语言未覆盖或解析异常时退回纯文本行。
  List<List<InlineSpan>> _highlightedLines(
    String source,
    TextStyle base,
    DshPalette p,
  ) {
    final language = DshCodeHighlight.languageFor(widget.name);
    final brightness = Theme.of(context).brightness;
    final key = '$brightness|$language|${_text.hashCode}';
    final cached = _highlighted;
    if (cached != null && _highlightKey == key) return cached;
    final lines =
        DshCodeHighlight.highlightLines(
          source: source,
          language: language,
          base: base,
          theme: dshCodeTheme(p, brightness),
        ) ??
        [
          for (final line in source.split('\n'))
            <InlineSpan>[TextSpan(text: line)],
        ];
    _highlightKey = key;
    _highlighted = lines;
    return lines;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
  }

  String _friendlyMessage(AppException error) => switch (error.code) {
    'workspace-file/not-found' => '文件不存在',
    'workspace-file/outside-workspace' => '文件不在当前工作区内',
    _ => error.userMessage,
  };
}
