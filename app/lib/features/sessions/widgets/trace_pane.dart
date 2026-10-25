import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/models/transcript_node.dart';
import '../../../widgets/common.dart';
import '../../../widgets/memo_row.dart';
import '../session_providers.dart';

/// 轨迹面板：由已加载的转写窗口派生的事件流（工具调用 / 轮次锚点 / 状态行）。
class TracePane extends ConsumerStatefulWidget {
  final SessionKey sessionKey;

  const TracePane({super.key, required this.sessionKey});

  @override
  ConsumerState<TracePane> createState() => _TracePaneState();
}

class _TracePaneState extends ConsumerState<TracePane>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  SessionKey get _key => widget.sessionKey;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(sessionProvider(_key));
    return state.when(
      skipLoadingOnReload: true,
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (error, _) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(sessionProvider(_key)),
      ),
      data: _buildTrace,
    );
  }

  Widget _buildTrace(SessionViewState view) {
    if (view.nodes.isEmpty) {
      return const EmptyState(
        icon: Icons.route_outlined,
        message: '会话开始后，这里会展示工具调用与执行轨迹',
      );
    }
    int turn = 0;
    final rows = <Widget>[
      if (view.hasMore) _TraceHint('仅显示已加载窗口，更早的历史请在对话页上滑加载'),
    ];
    for (final node in view.nodes) {
      switch (node.kind) {
        case TranscriptKind.user:
          if (node.text.isNotEmpty) turn++;
          rows.add(
            _TurnAnchor(
              key: ValueKey('turn-${node.id}'),
              turn: turn,
              text: node.text,
            ),
          );
        case TranscriptKind.assistant:
          if (node.text.isNotEmpty) {
            rows.add(
              MemoTranscriptRow(
                key: ValueKey('summary-${node.id}'),
                node: node,
                builder: (n) => _SummaryRow(
                  icon: Icons.smart_toy_outlined,
                  label: '回复',
                  text: n.text,
                ),
              ),
            );
          }
        case TranscriptKind.tool:
          rows.add(
            MemoTranscriptRow(
              key: ValueKey(node.id),
              node: node,
              builder: (n) => _TraceToolRow(node: n),
            ),
          );
        case TranscriptKind.error:
        case TranscriptKind.notice:
        case TranscriptKind.compaction:
          rows.add(
            MemoTranscriptRow(
              key: ValueKey(node.id),
              node: node,
              builder: (n) => _StatusRow(node: n),
            ),
          );
      }
    }
    rows.add(const SizedBox(height: 12));
    return ListView.builder(
      // 键盘弹起时补底部高度，末行可滚到键盘上方（页面不压缩 body）。
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index],
    );
  }
}

/// 工具名 → 轨迹动词（对齐 Web 端轨迹行的说法）。
(String, IconData) _traceVerb(String? toolName) {
  final name = (toolName ?? '').toLowerCase();
  if (name.contains('bash') || name.contains('command') || name == 'sh') {
    return ('执行了命令', Icons.terminal_outlined);
  }
  if (name.contains('edit') ||
      name.contains('write') ||
      name.contains('patch')) {
    return ('修改了文件', Icons.edit_note_outlined);
  }
  if (name.contains('read')) {
    return ('读取了文件', Icons.description_outlined);
  }
  if (name.contains('search') ||
      name.contains('grep') ||
      name.contains('glob')) {
    return ('检索了内容', Icons.search_outlined);
  }
  return ('已调用工具', Icons.build_outlined);
}

class _TraceHint extends StatelessWidget {
  final String text;

  const _TraceHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: context.dshText.labelSmall?.copyWith(
          color: context.dsh.tertiaryText,
        ),
      ),
    );
  }
}

class _TurnAnchor extends StatelessWidget {
  final int turn;
  final String text;

  const _TurnAnchor({super.key, required this.turn, required this.text});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: p.chipGray,
              borderRadius: BorderRadius.circular(DshRadius.pill),
            ),
            child: Text(
              turn > 0 ? '第 $turn 轮' : '输入',
              style: context.dshText.labelSmall?.copyWith(
                color: p.secondaryText,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.dshText.bodySmall?.copyWith(color: p.midText),
            ),
          ),
        ],
      ),
    );
  }
}

class _TraceToolRow extends StatelessWidget {
  final TranscriptNode node;

  const _TraceToolRow({required this.node});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final failed = node.toolFailed;
    final running = !node.toolFinished;
    final (verb, icon) = _traceVerb(node.toolName);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        leading: Icon(
          failed
              ? Icons.error_outline
              : running
              ? Icons.autorenew_rounded
              : icon,
          size: 16,
          color: failed
              ? p.dangerRed
              : running
              ? p.runningYellow
              : p.secondaryText,
        ),
        title: Text(
          verb,
          style: context.dshText.bodySmall?.copyWith(
            fontSize: 13.5,
            color: p.midText,
          ),
        ),
        subtitle: (node.toolName ?? '').isEmpty
            ? null
            : Text(
                running
                    ? '执行中…'
                    : failed
                    ? '执行失败'
                    : node.toolName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.dshText.labelSmall?.copyWith(
                  color: failed ? p.dangerRed : p.tertiaryText,
                ),
              ),
        children: [
          if ((node.toolArguments ?? '').isNotEmpty)
            _TraceCode(node.toolArguments!),
          if ((node.toolResult ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            _TraceCode(node.toolResult!, error: failed),
          ],
        ],
      ),
    );
  }
}

class _TraceCode extends StatelessWidget {
  final String text;
  final bool error;

  const _TraceCode(this.text, {this.error = false});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 220),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: error ? p.dangerRed.withValues(alpha: 0.06) : p.chipGray,
        borderRadius: BorderRadius.circular(DshRadius.thumb),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          text,
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: error ? p.dangerRed : p.foreground,
            fontFamilyFallback: const ['Menlo', 'monospace'],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String text;

  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        leading: Icon(icon, size: 16, color: p.secondaryText),
        title: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.dshText.bodySmall?.copyWith(
            fontSize: 13.5,
            color: p.midText,
          ),
        ),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: p.chipGray,
              borderRadius: BorderRadius.circular(DshRadius.thumb),
            ),
            child: SelectableText(
              text,
              style: context.dshText.bodySmall?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final TranscriptNode node;

  const _StatusRow({required this.node});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final failed = node.kind == TranscriptKind.error || node.failed;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Row(
        children: [
          Icon(
            failed ? Icons.error_outline : Icons.info_outline,
            size: 14,
            color: failed ? p.dangerRed : p.tertiaryText,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              node.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.dshText.labelSmall?.copyWith(
                color: failed ? p.dangerRed : p.tertiaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
