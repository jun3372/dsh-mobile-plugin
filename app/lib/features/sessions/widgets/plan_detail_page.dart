import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../app/theme.dart';
import 'detail_header.dart';

/// 计划 markdown 限高预览：超过 [maxHeight] 裁切并在底部渐隐，点击进全文页。
/// 计划审批卡与计划评审问答卡共用。
class PlanMarkdownPreview extends StatelessWidget {
  final String markdown;
  final VoidCallback onTap;

  const PlanMarkdownPreview({
    super.key,
    required this.markdown,
    required this.onTap,
  });

  static const double maxHeight = 320;

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final body = MarkdownBody(
      data: markdown,
      styleSheet: MarkdownStyleSheet(
        p: context.dshText.bodyMedium?.copyWith(height: 1.55),
        listBullet: context.dshText.bodyMedium,
        h1: context.dshText.titleLarge?.copyWith(fontSize: 18),
        h2: context.dshText.titleMedium?.copyWith(fontSize: 16),
        h3: context.dshText.titleMedium,
        codeblockDecoration: BoxDecoration(
          color: p.chipGray,
          borderRadius: BorderRadius.circular(DshRadius.codeBlock),
          border: Border.all(color: p.divider),
        ),
      ),
    );
    final long = markdown.length > 600 || markdown.split('\n').length > 12;
    if (!long) return GestureDetector(onTap: onTap, child: body);
    return GestureDetector(
      onTap: onTap,
      child: ClipRect(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: maxHeight),
          child: Stack(
            children: [
              SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: body,
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 48,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        // 起点必须是「透明版 surface」而非 Colors.transparent
                        // （透明黑）：渐变按非预乘插值，透明黑→白会经过半透明
                        // 灰，在白色卡面上呈现一条发黑的底部阴影带
                        colors: [p.surface.withValues(alpha: 0), p.surface],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 计划详情全文页：从计划审批卡表头进入，完整渲染 exit_plan_mode 提交的
/// markdown 计划正文（审批卡内只做限高预览）。
class PlanDetailPage extends StatelessWidget {
  final String markdown;

  const PlanDetailPage({super.key, required this.markdown});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: '计划详情',
              subtitleIcon: Icons.assignment_outlined,
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  DshSpace.x4,
                  0,
                  DshSpace.x4,
                  DshSpace.x6,
                ),
                child: MarkdownBody(
                  data: markdown,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet(
                    p: context.dshText.bodyMedium?.copyWith(height: 1.6),
                    listBullet: context.dshText.bodyMedium,
                    h1: context.dshText.titleLarge?.copyWith(fontSize: 20),
                    h2: context.dshText.titleLarge?.copyWith(fontSize: 18),
                    h3: context.dshText.titleMedium?.copyWith(fontSize: 16),
                    h4: context.dshText.titleMedium,
                    codeblockDecoration: BoxDecoration(
                      color: p.chipGray,
                      borderRadius: BorderRadius.circular(DshRadius.codeBlock),
                      border: Border.all(color: p.divider),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
