/// `/` 与 `@` 触发菜单的控制器：检测 token、拉取候选、维护高亮与开关状态。
///
/// 语义对齐宿主 `dsh-client-ui-input-trigger`：
/// - 菜单打开期间编辑器保持焦点，点行即选定（App 用 tap）；
/// - 目录行选定后保持打开并停在尾斜杠上（等于 Web 的 Tab 下钻）；
/// - Escape / 外部点击只关闭菜单，从不改写草稿；
/// - 被关闭的菜单保持关闭：同一个 token 以同一查询重新出现时不重开，
///   必须输入新查询或换到另一个 token 才重新武装。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'composer_document.dart';
import 'trigger_sources.dart';

/// 选定候选后的落地动作。
class TriggerPick {
  final String? insertion;
  final ActiveComposerTrigger trigger;
  final TriggerItem item;
  final void Function()? onPick;

  const TriggerPick({
    required this.trigger,
    required this.item,
    this.insertion,
    this.onPick,
  });
}

class TriggerMenuController extends ChangeNotifier {
  final List<TriggerSource> sources;

  /// 文本被候选改写时回调（App 侧写回 TextEditingController 并放置光标）。
  final void Function(String text, int caret) onDraftEdited;

  /// 纯 UI 动作候选（打开模型/权限选择器等）。
  final void Function(TriggerPick pick) onActionPick;

  TriggerMenuController({
    required this.sources,
    required this.onDraftEdited,
    required this.onActionPick,
    Duration debounce = const Duration(milliseconds: 120),
  }) : _debounce = debounce;

  final Duration _debounce;
  Timer? _debounceTimer;
  int _generation = 0;

  ActiveComposerTrigger? _trigger;
  List<TriggerGroup> _groups = const [];
  int _highlight = 0;
  bool _open = false;

  /// 指针关闭时记录的 token 指纹；同指纹同查询不再重开。
  String? _dismissedKey;

  TriggerGuard guard = TriggerGuard.plain;

  ActiveComposerTrigger? get trigger => _trigger;
  List<TriggerGroup> get groups => _groups;
  bool get isOpen => _open;
  bool get loading => _pending > 0;
  int get highlight => _highlight;
  int _pending = 0;

  List<TriggerItem> get _flat => [for (final group in _groups) ...group.items];

  /// 草稿或光标变化时调用。[caret] 为selection.base（无选区时即插入点）。
  void onDraftChanged(String draft, int caret) {
    _draft = draft;
    final hit = detectComposerTrigger(draft, caret, guard: guard);
    if (hit == null) {
      _close(keepDismiss: false);
      return;
    }
    final key = '${hit.kind.name}:${hit.start}:${hit.query}';
    if (_dismissedKey == key) return;
    if (!_open && hit.kind != _trigger?.kind) {
      // 换到另一个 token：重新武装。
      _dismissedKey = null;
    }
    _trigger = hit;
    _open = true;
    _highlight = 0;
    _scheduleFetch(draft, hit);
  }

  void _scheduleFetch(String draft, ActiveComposerTrigger hit) {
    _debounceTimer?.cancel();
    final generation = ++_generation;
    // 空 query（刚敲下触发符）立即出菜单，输入后再防抖，避免连续打字符时刷屏。
    if (hit.query.isEmpty) {
      _fetch(generation, hit);
      return;
    }
    _debounceTimer = Timer(_debounce, () => _fetch(generation, hit));
  }

  Future<void> _fetch(int generation, ActiveComposerTrigger hit) async {
    final live = sources.where((source) => source.accepts(hit.kind)).toList();
    _pending = live.length;
    _notifyIfCurrent(generation);
    final groups = <TriggerGroup>[];
    for (final source in live) {
      List<TriggerItem> items = const [];
      try {
        items = await source.candidates(hit.query);
      } catch (_) {
        // 单源失败不影响其它分组（宿主可能未挂 fileReferences 等插件）。
        items = const [];
      }
      if (generation != _generation) return;
      _pending--;
      if (items.isNotEmpty) {
        groups.add(TriggerGroup(title: source.groupTitle, items: items));
      }
      _notifyIfCurrent(generation);
    }
    if (generation != _generation) return;
    _pending = 0;
    _groups = groups;
    // 无候选时 clamp(0, -1) 会抛错，直接归零。
    _highlight = _flat.isEmpty ? 0 : _highlight.clamp(0, _flat.length - 1);
    _notifyIfCurrent(generation);
  }

  void _notifyIfCurrent(int generation) {
    if (generation != _generation) return;
    notifyListeners();
  }

  /// ↑/↓：由硬件键盘或页面箭头驱动。
  void moveHighlight(int delta) {
    final count = _flat.length;
    if (!_open || count == 0) return;
    _highlight = (_highlight + delta) % count;
    if (_highlight < 0) _highlight += count;
    notifyListeners();
  }

  void setHighlight(int index) {
    if (index < 0 || index >= _flat.length || index == _highlight) return;
    _highlight = index;
    notifyListeners();
  }

  TriggerItem? get currentItem {
    final items = _flat;
    if (items.isEmpty) return null;
    return items[_highlight.clamp(0, items.length - 1)];
  }

  /// 选定一条候选（tap / Enter / Tab）。
  void pick(TriggerItem item) {
    final trigger = _trigger;
    if (trigger == null) return;
    if (item.onPick case final action?) {
      _close(keepDismiss: false);
      onActionPick(TriggerPick(trigger: trigger, item: item, onPick: action));
      return;
    }
    final insertion = item.insertion;
    if (insertion == null) return;
    // 目录行插入后停在尾斜杠，菜单保持在原地继续下钻。
    final keepOpenForDrill = item.drill;
    final dismissedKey = _dismissedKey;
    final result = _apply(trigger, insertion);
    if (!keepOpenForDrill) {
      _close(keepDismiss: false);
    } else {
      _dismissedKey = dismissedKey;
    }
    onDraftEdited(result.text, result.caret);
    if (keepOpenForDrill) {
      onDraftChanged(result.text, result.caret);
    }
  }

  ({String text, int caret}) _apply(
    ActiveComposerTrigger trigger,
    String insertion,
  ) {
    return replaceTrigger(_draft, trigger, insertion);
  }

  /// 当前草稿全文；[onDraftChanged] 每次同步，pick 时用于替换区间。
  String _draft = '';

  /// 指针/外部点击关闭：不改写草稿，并记住当前 token 指纹防止立刻重开。
  void dismiss() {
    final trigger = _trigger;
    if (trigger != null) {
      _dismissedKey = '${trigger.kind.name}:${trigger.start}:${trigger.query}';
    }
    _close(keepDismiss: true);
  }

  void _close({required bool keepDismiss}) {
    if (!_open && _groups.isEmpty) return;
    _generation++;
    _debounceTimer?.cancel();
    _open = false;
    _trigger = null;
    _groups = const [];
    _highlight = 0;
    _pending = 0;
    if (!keepDismiss) _dismissedKey = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
