import 'package:dsh_mobile/core/models/agent_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preset id 映射到四种模式', () {
    expect(AgentMode.byPresetId('standard'), AgentMode.standard);
    expect(AgentMode.byPresetId('ptc'), AgentMode.ptc);
    expect(AgentMode.byPresetId('minimal'), AgentMode.minimal);
    expect(AgentMode.byPresetId('cordis'), AgentMode.creative);
  });

  test('未知 preset 原样显示，空值回退标准模式', () {
    expect(AgentMode.byPresetId('my-agent'), isNull);
    expect(AgentMode.labelOf('my-agent'), 'my-agent');
    expect(AgentMode.labelOf(null), '标准模式');
    expect(AgentMode.labelOf(''), '标准模式');
  });
}
