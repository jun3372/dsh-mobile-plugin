import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/models/agent_mode.dart';
import 'common.dart';

/// 会话模式选择：四项 Agent 预设，带描述与选中打勾。
Future<AgentMode?> showAgentModeSheet(
  BuildContext context, {
  required String? currentPresetId,
}) {
  final current = AgentMode.byPresetId(currentPresetId);
  return showDshSheet<AgentMode>(
    context,
    builder: (sheetContext) => SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DshSheetTitle(title: '会话模式'),
          for (final mode in AgentMode.values)
            ListTile(
              title: Text(mode.label),
              subtitle: Text(
                mode.description,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: mode == current
                  ? const Icon(Icons.check_rounded, size: 20)
                  : null,
              onTap: () => Navigator.of(sheetContext).pop(mode),
            ),
          const SizedBox(height: DshSpace.x2),
        ],
      ),
    ),
  );
}
