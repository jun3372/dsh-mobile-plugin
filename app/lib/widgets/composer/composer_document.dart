/// 输入区文档模型：触发 token 的检测、插入与提交展开。
///
/// `@` 语法逐字移植宿主浏览器端共享语法
/// `@deepseek-ai/dsh-file-reference/lib/types/grammar.js`
/// （activeAtToken / formatFileMention），`/` 语法按
/// `dsh-client-ui-input-trigger/lib/types/core/detect.d.ts` 的约定实现：
/// 向左扫到第一个空白，该切片以 `/` 开头才算触发，
/// 因此 URL 里的斜杠继续当普通字符。
library;

/// 光标处的触发类型。
enum ComposerTriggerKind {
  /// `/` —— 命令与技能。
  slash,

  /// `@` —— 文件、目录与会话引用。
  at,
}

/// 一次触发命中：`query` 是触发符到光标之间的切片。
class ActiveComposerTrigger {
  final ComposerTriggerKind kind;
  final String query;

  /// 命中 token 在草稿中的区间，替换时用。
  final int start;
  final int end;

  /// `@"…` 未闭合引号形态，只在 [ComposerTriggerKind.at] 出现。
  final bool quoted;

  const ActiveComposerTrigger({
    required this.kind,
    required this.query,
    required this.start,
    required this.end,
    this.quoted = false,
  });
}

/// 触发符可用档位（宿主叫 guard tiers）。
enum TriggerGuard {
  /// 两个触发符都可用。
  plain,

  /// 已认领命令 token：`/` 全抑制，`@` 仍可用。
  claimed,

  /// 都不可用（如宿主离线、只读）。
  frozen,
}

final _quotedAtPattern = RegExp(r'''(?:^|\s)(@"([^"]*))$''');
final _plainAtPattern = RegExp(r'(?:^|\s)(@([^\s]*))$');

/// 检测光标处是否落在触发 token 内；无命中返回 null。
///
/// 顺序与宿主一致：先 `@`（共享语法，含跨空白的未闭合引号），再 `/`。
ActiveComposerTrigger? detectComposerTrigger(
  String draft,
  int caret, {
  TriggerGuard guard = TriggerGuard.plain,
}) {
  if (guard == TriggerGuard.frozen) return null;
  final offset = caret.clamp(0, draft.length);
  final beforeCaret = draft.substring(0, offset);

  if (_quotedAtPattern.firstMatch(beforeCaret) case final quoted?) {
    return ActiveComposerTrigger(
      kind: ComposerTriggerKind.at,
      query: quoted.group(2) ?? '',
      start: _triggerOffset(quoted),
      end: offset,
      quoted: true,
    );
  }
  if (_plainAtPattern.firstMatch(beforeCaret) case final plain?) {
    return ActiveComposerTrigger(
      kind: ComposerTriggerKind.at,
      query: plain.group(2) ?? '',
      start: _triggerOffset(plain),
      end: offset,
    );
  }
  if (guard == TriggerGuard.claimed) return null;

  // 向左扫到第一个空白，整段以 / 开头才算命令触发。
  var start = offset;
  while (start > 0 && !_isBoundary(draft.codeUnitAt(start - 1))) {
    start--;
  }
  if (start >= offset) return null;
  final token = draft.substring(start, offset);
  if (!token.startsWith('/')) return null;
  return ActiveComposerTrigger(
    kind: ComposerTriggerKind.slash,
    query: token.substring(1),
    start: start,
    end: offset,
  );
}

/// 命中区间从 `@` 本身开始：前缀 `(?:^|\s)` 可能是零宽的行首，
/// 用整体结束位置减去 `@…` 前缀长度定位，避免把 `@` 留在草稿里变成 `@@`。
int _triggerOffset(RegExpMatch match) {
  final prefix = match.group(1) ?? '';
  return match.end - prefix.length;
}

bool _isBoundary(int codeUnit) =>
    codeUnit == 0x20 ||
    codeUnit == 0x09 ||
    codeUnit == 0x0a ||
    codeUnit == 0x0d ||
    codeUnit == 0x0b ||
    codeUnit == 0x0c;

/// 草稿最前面是否已经是一个命令 token（对应宿主的 claimed 档位）。
bool hasClaimedCommand(String draft) {
  final trimmed = draft.replaceFirst(RegExp(r'^[ \t]+'), '');
  if (!trimmed.startsWith('/')) return false;
  var end = 1;
  while (end < trimmed.length && !_isBoundary(trimmed.codeUnitAt(end))) {
    end++;
  }
  return end > 1;
}

/// 把选中的路径格式化回草稿文本；空白走 `@"path"`，
/// 目录保持引号打开以便继续下钻（与宿主 formatFileMention 一致）。
String? formatFileMention(
  String path, {
  required bool isDirectory,
  bool preserveQuote = false,
}) {
  final normalized = isDirectory && !path.endsWith('/') ? '$path/' : path;
  // 控制字符与引号无法用该语法安全表达（宿主的 code-unit 区间等价写法）。
  if (RegExp('[\\u0000-\\u001f\\u007f-\\u009f"]').hasMatch(normalized) ||
      normalized.contains('"')) {
    return null;
  }
  final quoted = preserveQuote || RegExp(r'\s').hasMatch(normalized);
  if (!quoted) return '@$normalized';
  if (isDirectory) return '@"$normalized';
  return '@"$normalized"';
}

/// 会话引用的规范形态由宿主直接给出（`@[label](dsh-session:…)`）。
String formatSessionMention(String mention) => mention;

/// 用命中区间把 token 替换成插入文本，返回新草稿与光标位置。
({String text, int caret}) replaceTrigger(
  String draft,
  ActiveComposerTrigger trigger,
  String insertion,
) {
  final text =
      draft.substring(0, trigger.start) +
      insertion +
      draft.substring(trigger.end);
  return (text: text, caret: trigger.start + insertion.length);
}

/// 与宿主一致的排序：大小写不敏感的有序子序列匹配，前缀优先。
/// 返回按分数从高到低、同分按名称字典序的稳定列表。
List<T> rankByQuery<T>(
  String query,
  List<T> items, {
  required String Function(T item) name,
  String Function(T item)? label,
  int limit = 40,
}) {
  if (query.isEmpty) {
    final sorted = [...items]
      ..sort((a, b) => name(a).toLowerCase().compareTo(name(b).toLowerCase()));
    return sorted.length > limit ? sorted.sublist(0, limit) : sorted;
  }
  final needle = query.toLowerCase();
  final scored = <({T item, int score})>[];
  for (final item in items) {
    final candidates = <String>[
      name(item),
      if (label != null) label(item),
    ].where((value) => value.isNotEmpty).toSet();
    var best = -1;
    for (final haystack in candidates) {
      final score = _subsequenceScore(needle, haystack.toLowerCase());
      if (score > best) best = score;
    }
    if (best >= 0) scored.add((item: item, score: best));
  }
  scored.sort((a, b) {
    if (a.score != b.score) return b.score - a.score;
    return name(a.item).toLowerCase().compareTo(name(b.item).toLowerCase());
  });
  return scored.take(limit).map((entry) => entry.item).toList(growable: false);
}

/// 有序子序列打分：不匹配返回 -1；前缀命中给最高分，命中越靠前排越高。
int _subsequenceScore(String needle, String haystack) {
  if (needle.isEmpty) return 0;
  if (haystack.startsWith(needle)) return 10000 - haystack.length;
  var cursor = 0;
  var firstMatch = -1;
  var gaps = 0;
  for (var n = 0; n < needle.length; n++) {
    final char = needle[n];
    var found = -1;
    while (cursor < haystack.length) {
      if (haystack[cursor] == char) {
        found = cursor;
        cursor++;
        break;
      }
      cursor++;
    }
    if (found < 0) return -1;
    if (firstMatch < 0) firstMatch = found;
    if (n > 0) gaps += found - cursor + 1;
  }
  return (9000 - firstMatch * 20 - gaps).clamp(1, 9999);
}
