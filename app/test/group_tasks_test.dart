import 'package:dsh_mobile/core/models/dsh_session.dart';
import 'package:dsh_mobile/core/mux/workspace_hub.dart';
import 'package:dsh_mobile/features/tasks/tasks_providers.dart';
import 'package:flutter_test/flutter_test.dart';

SessionSummary session({
  required String id,
  String? title,
  String? cwd,
  DateTime? updatedAt,
  bool running = false,
  bool blank = false,
}) {
  return SessionSummary(
    sessionId: id,
    title: title,
    cwd: cwd,
    updatedAt: updatedAt,
    running: running,
    blank: blank,
  );
}

void main() {
  final now = DateTime.now();
  final yesterday = now.subtract(const Duration(days: 1));

  test('子任务（subagent）会话不进首页列表', () {
    final visible = withoutSubagentSessions([
      session(id: 'parent', title: '绘画'),
      SessionSummary(
        sessionId: 'child',
        title: '子任务',
        origin: 'subagent',
        cwd: '/root/weaver',
      ),
      session(id: 'forked', title: '派生会话'),
    ]);
    expect(visible.map((s) => s.sessionId), ['parent', 'forked']);
  });

  test('按工作区分组', () {
    final groups = groupTasks([
      session(id: 'a', cwd: '/root/weaver', title: 'A'),
      session(id: 'b', cwd: '/root/weaver', title: 'B'),
      session(id: 'c', cwd: '/root/dsh', title: 'C'),
    ], const TaskPrefs(groupMode: TaskGroupMode.workspace));
    expect(groups, hasLength(2));
    expect(groups[0].title, 'weaver');
    expect(groups[0].sessions, hasLength(2));
    expect(groups[1].title, 'dsh');
  });

  test('按状态分组：进行中/待处理/已完成', () {
    final groups = groupTasks([
      session(id: 'a', running: true),
      session(id: 'b', blank: true),
      session(id: 'c'),
    ], const TaskPrefs(groupMode: TaskGroupMode.status));
    expect(groups.map((g) => g.title).toList(), ['进行中', '待处理', '已完成']);
  });

  test('按日期分组：今天/昨天倒序', () {
    final groups = groupTasks([
      session(id: 'a', updatedAt: yesterday),
      session(id: 'b', updatedAt: now),
    ], const TaskPrefs(groupMode: TaskGroupMode.date));
    expect(groups.map((g) => g.title).toList(), ['今天', '昨天']);
  });

  test('仅展示进行中筛选', () {
    final groups = groupTasks([
      session(id: 'a', running: true),
      session(id: 'b'),
    ], const TaskPrefs(groupMode: TaskGroupMode.status, onlyRunning: true));
    expect(groups, hasLength(1));
    expect(groups.first.sessions.first.sessionId, 'a');
  });

  test('空列表返回空分组', () {
    expect(groupTasks(const [], const TaskPrefs()), isEmpty);
  });

  test('按工作区过滤在任意分组方式下都先于分组生效', () {
    final sessions = [
      session(id: 'a', cwd: '/root/weaver', updatedAt: now),
      session(id: 'b', cwd: '/root/dsh', updatedAt: now),
    ];
    expect(
      filterSessionsByFolder(
        sessions,
        'weaver',
      ).map((s) => s.sessionId).toList(),
      ['a'],
    );
    expect(filterSessionsByFolder(sessions, null), hasLength(2));
    expect(
      groupTasks(
        filterSessionsByFolder(sessions, 'weaver'),
        const TaskPrefs(groupMode: TaskGroupMode.date),
      ).first.sessions.single.sessionId,
      'a',
    );
  });

  test('folderName 兼容 Windows 反斜杠、尾分隔符与根路径', () {
    expect(
      session(id: 'a', cwd: 'C:\\Users\\jun\\weaver').folderName,
      'weaver',
    );
    expect(
      session(id: 'b', cwd: 'C:\\Users\\jun\\weaver\\').folderName,
      'weaver',
    );
    expect(session(id: 'c', cwd: '/root/').folderName, 'root');
    expect(session(id: 'd', cwd: '/').folderName, isNull);
    expect(folderNameOf(''), isNull);
  });

  // 实测宿主（2026-10-24）：workspace/follow 的 sessionIds 只登记桌面端建过的会话，
  // 移动端 session/create 出来的会话不在其中，于是同一目录的会话被拆成
  // 「工作区分组 + 同名末段分组」两块，页面出现重复项目名与重复会话列表。
  test('未登记到工作区但同目录的会话并入该工作区分组，不产生重名分组', () {
    final groups = groupTasks(
      [
        session(id: 's1', cwd: '/root/weaver', title: 'S1'),
        session(id: 's2', cwd: '/root/weaver', title: 'S2'),
        session(id: 's3', cwd: '/root/dsh', title: 'S3'),
      ],
      const TaskPrefs(groupMode: TaskGroupMode.workspace),
      workspaces: const [
        WorkspaceRow(
          workspaceId: 'w1',
          path: '/root/weaver',
          title: 'weaver',
          sessionIds: ['s1'],
        ),
        WorkspaceRow(
          workspaceId: 'w2',
          path: '/root/dsh',
          title: 'dsh',
          sessionIds: ['s3'],
        ),
      ],
    );
    expect(groups.map((g) => g.title).toList(), ['weaver', 'dsh']);
    expect(groups.first.sessions.map((s) => s.sessionId).toList(), [
      's1',
      's2',
    ]);
  });

  test('工作区改名后按目录归并，未注册目录仍单独成组', () {
    final groups = groupTasks(
      [
        session(id: 's1', cwd: '/root/weaver', title: 'S1'),
        session(id: 's2', cwd: '/root/weaver', title: 'S2'),
        session(id: 's3', cwd: '/root/other', title: 'S3'),
      ],
      const TaskPrefs(groupMode: TaskGroupMode.workspace),
      workspaces: const [
        WorkspaceRow(
          workspaceId: 'w1',
          path: '/root/weaver',
          title: '织机',
          sessionIds: ['s1'],
        ),
      ],
    );
    expect(groups.map((g) => g.title).toList(), ['织机', 'other']);
    expect(groups.first.sessions.map((s) => s.sessionId).toList(), [
      's1',
      's2',
    ]);
  });

  // 列表的项目标识就是目录末段（筛选 chips 与 findByFolder 同样按末段匹配），
  // 因此分组标题必须唯一：末段相同的未注册会话并入同名分组，不再并列两个同名标题。
  test('分组标题唯一：同末段会话并入同名分组', () {
    final groups = groupTasks(
      [
        session(id: 's1', cwd: '/a/app', title: 'S1'),
        session(id: 's2', cwd: '/b/app', title: 'S2'),
      ],
      const TaskPrefs(groupMode: TaskGroupMode.workspace),
      workspaces: const [
        WorkspaceRow(
          workspaceId: 'w1',
          path: '/a/app',
          title: '',
          sessionIds: ['s1'],
        ),
      ],
    );
    expect(groups, hasLength(1));
    expect(groups.first.title, 'app');
    expect(groups.first.sessions.map((s) => s.sessionId).toList(), [
      's1',
      's2',
    ]);
  });
}
