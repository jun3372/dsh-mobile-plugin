import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../core/models/dsh_models.dart';
import '../../core/models/dsh_session.dart';
import '../../widgets/common.dart';
import '../servers/servers_providers.dart';
import '../sessions/session_page.dart';
import 'tasks_providers.dart';

/// 会话内容搜索页（session/search；宿主禁用索引时展示原因）。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<SearchHit>? _hits;
  AppException? _error;
  bool _searching = false;
  int _searchSeq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _searchSeq++;
      setState(() {
        _hits = null;
        _error = null;
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () => _search(value));
  }

  String _errorText(AppException error) {
    // 宿主未开启 session-query 索引时会返回英文内部说明，这里转成可操作提示。
    final message = error.userMessage;
    if (message.toLowerCase().contains('session search is disabled')) {
      return '当前服务端未启用会话搜索，请在宿主配置中开启会话索引后重试';
    }
    return message;
  }

  Future<void> _search(String query) async {
    final api = ref.read(dshApiProvider);
    if (api == null) return;
    final seq = ++_searchSeq;
    setState(() => _searching = true);
    try {
      final hits = await api.search(query.trim());
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _hits = hits;
        _error = null;
        _searching = false;
      });
    } on AppException catch (e) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _hits = const [];
        _error = e;
        _searching = false;
      });
    }
  }

  void _open(SearchHit hit) {
    final sessions = ref.read(tasksProvider).value ?? const [];
    final summary = sessions
        .where((s) => s.sessionId == hit.sessionId)
        .firstOrNull;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SessionPage(
          summary:
              summary ??
              SessionSummary(
                sessionId: hit.sessionId,
                title: hit.title ?? hit.snippet,
              ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: DshSpace.x3),
          decoration: BoxDecoration(
            color: p.canvas,
            borderRadius: BorderRadius.circular(DshRadius.pill),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 18, color: p.secondaryText),
              const SizedBox(width: DshSpace.x2),
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  style: context.dshText.bodyMedium,
                  decoration: InputDecoration.collapsed(
                    hintText: '搜索会话内容',
                    hintStyle: context.dshText.bodyMedium?.copyWith(
                      color: p.secondaryText,
                    ),
                  ),
                  onChanged: _onChanged,
                ),
              ),
            ],
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_searching) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      final p = context.dsh;
      return Padding(
        padding: const EdgeInsets.all(DshSpace.x8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 44, color: p.dotGray),
            const SizedBox(height: DshSpace.x3),
            Text(
              _errorText(_error!),
              textAlign: TextAlign.center,
              style: context.dshText.bodyMedium?.copyWith(
                fontSize: 14,
                color: p.secondaryText,
              ),
            ),
          ],
        ),
      );
    }
    final hits = _hits;
    if (hits == null) {
      return const EmptyState(icon: Icons.search, message: '输入关键词搜索会话');
    }
    if (hits.isEmpty) {
      return const EmptyState(icon: Icons.search_off, message: '没有匹配的会话');
    }
    return ListView.builder(
      itemCount: hits.length,
      itemBuilder: (context, index) {
        final hit = hits[index];
        final id = hit.sessionId;
        final fallback = id.isEmpty
            ? '会话'
            : '会话 ${id.length > 12 ? id.substring(0, 12) : id}';
        return ListTile(
          leading: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
          title: Text(
            hit.title ?? fallback,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: hit.snippet == null
              ? null
              : Text(
                  hit.snippet!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
          onTap: () => _open(hit),
        );
      },
    );
  }
}
