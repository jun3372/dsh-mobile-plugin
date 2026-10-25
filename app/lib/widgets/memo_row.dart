import 'package:flutter/material.dart';

import '../core/models/transcript_node.dart';

/// 按节点实例身份缓存构建结果的转写行。
///
/// 新版 Flutter 将 Widget.==/hashCode 声明为 non-virtual，无法以
/// 相等性短路 rebuild；改为在 StatefulWidget 内缓存上次构建的子树：
/// 流式发布期间未变化的节点实例保持同一，build 直接返回缓存的子树，
/// Element 层因新旧 widget identical 而整段跳过 rebuild。
/// 依赖（主题/媒体查询等 InheritedWidget）变化时经 didChangeDependencies 失效。
typedef TranscriptRowBuilder = Widget Function(TranscriptNode node);

class MemoTranscriptRow extends StatefulWidget {
  final TranscriptNode node;
  final TranscriptRowBuilder builder;

  const MemoTranscriptRow({
    super.key,
    required this.node,
    required this.builder,
  });

  @override
  State<MemoTranscriptRow> createState() => _MemoTranscriptRowState();
}

class _MemoTranscriptRowState extends State<MemoTranscriptRow> {
  TranscriptNode? _node;
  Widget? _child;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 主题/方向等依赖变化后缓存子树的样式已过期，强制重建一次。
    _node = null;
  }

  @override
  Widget build(BuildContext context) {
    if (!identical(_node, widget.node)) {
      _node = widget.node;
      // 用行自身的 context 构建：Theme.of 等依赖注册在本元素上，
      // 主题变化时经 didChangeDependencies 失效缓存。
      _child = widget.builder(widget.node);
    }
    return _child!;
  }
}
