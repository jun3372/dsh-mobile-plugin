/// 会话 Agent 模式：与宿主内置 agent preset 一一对应。
///
/// 创造模式在宿主侧的 preset id 是 `cordis`，其余同名。
enum AgentMode {
  standard('standard', '标准模式', '处理代码、文件和资料，适合大多数任务。Agent 会按需使用检索、编辑和终端等工具。'),
  ptc('ptc', 'PTC 模式', '包含标准模式的所有能力，更适合批量调用工具，并对结果进行筛选、整理、去重、统计或汇总的任务。'),
  minimal('minimal', '极简模式', 'Agent 使用终端和图片读取工具，并支持上下文压缩，适合测试和对比其基础表现。'),
  creative(
    'cordis',
    '创造模式',
    '用对话定制 DSH：让 Agent 编写插件，添加新功能或界面；也能组合工具和提示词，创建自己的模式。',
  );

  final String presetId;
  final String label;
  final String description;

  const AgentMode(this.presetId, this.label, this.description);

  static AgentMode? byPresetId(String? id) {
    for (final mode in values) {
      if (mode.presetId == id) return mode;
    }
    return null;
  }

  /// 未知的自定义 preset 原样显示；尚未拿到投影时回退标准模式。
  static String labelOf(String? id) {
    final mode = byPresetId(id);
    if (mode != null) return mode.label;
    return (id?.isNotEmpty ?? false) ? id! : standard.label;
  }
}
