import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/models/composer_models.dart';
import '../core/models/dsh_models.dart';
import '../core/services/dsh_api.dart';
import 'common.dart';

/// 模型选择结果：provider / model / effort id + 展示名。
typedef ModelSelection = (
  String provider,
  String model,
  String? effort,
  String label,
);

/// 两页共用的模型选择菜单：从底部弹出。
/// 多推理力度时在同一弹层里翻到第二页，不再叠一层对话框。
/// 用户取消返回 null。
Future<ModelSelection?> showModelSelectionSheet(
  BuildContext context, {
  required DshApi api,
  String? selectedProvider,
  String? selectedModel,
}) async {
  final catalog = await loadModelCatalog(api);
  if (!context.mounted) return null;
  if (catalog.groups.isEmpty) {
    showDshSnack(context, '模型目录为空，请稍后重试');
    return null;
  }
  return showDshSheet<ModelSelection>(
    context,
    heightFactor: 0.75,
    builder: (_) => _ModelPickerBody(
      catalog: catalog,
      selectedProvider: selectedProvider,
      selectedModel: selectedModel,
    ),
  );
}

/// 目录为空时让宿主初始化默认模型，再重取一次。
Future<ModelCatalog> loadModelCatalog(DshApi api) async {
  var catalog = await api.modelCatalog();
  if (catalog.groups.isEmpty) {
    await api.initializeDefaultModel();
    catalog = await api.modelCatalog();
  }
  return catalog;
}

/// 两页共用的权限预设菜单。返回所选选项；取消返回 null。
Future<PermissionPresetOption?> showPermissionSelectionSheet(
  BuildContext context, {
  required DshApi api,
  String? current,
}) async {
  final catalog = await api.permissionCatalog();
  if (!context.mounted) return null;
  if (catalog.options.isEmpty) {
    showDshSnack(context, '宿主未提供权限预设');
    return null;
  }
  return showDshSheet<PermissionPresetOption>(
    context,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DshSheetTitle(title: '权限预设'),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: DshSpace.x2),
            children: [
              for (final option in catalog.options)
                ListTile(
                  title: Text(option.name),
                  subtitle: option.description == null
                      ? null
                      : Text(
                          option.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing: option.value == current
                      ? const Icon(Icons.check, size: 20)
                      : null,
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop<PermissionPresetOption>(option),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ModelPickerBody extends StatefulWidget {
  const _ModelPickerBody({
    required this.catalog,
    this.selectedProvider,
    this.selectedModel,
  });

  final ModelCatalog catalog;
  final String? selectedProvider;
  final String? selectedModel;

  @override
  State<_ModelPickerBody> createState() => _ModelPickerBodyState();
}

class _ModelPickerBodyState extends State<_ModelPickerBody> {
  ModelGroup? _group;
  ModelOption? _effortModel;

  @override
  Widget build(BuildContext context) {
    final model = _effortModel;
    if (model != null && _group != null) {
      return _buildEfforts(context, _group!, model);
    }
    return _buildModels(context);
  }

  Widget _buildModels(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DshSheetTitle(title: '选择模型'),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: DshSpace.x2),
            children: [
              for (final group in widget.catalog.groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DshSpace.x5,
                    DshSpace.x2,
                    DshSpace.x5,
                    DshSpace.x1,
                  ),
                  child: Text(
                    group.name,
                    style: context.dshText.bodySmall?.copyWith(
                      fontSize: 13,
                      color: context.dsh.secondaryText,
                    ),
                  ),
                ),
                for (final model in group.models)
                  ListTile(
                    title: Text(model.name),
                    subtitle: model.efforts.isEmpty
                        ? null
                        : Text(
                            '推理力度：${model.efforts.map((e) => e.name).join(' / ')}',
                          ),
                    trailing:
                        (widget.selectedProvider == group.id &&
                            widget.selectedModel == model.id)
                        ? const Icon(Icons.check, size: 20)
                        : null,
                    onTap: () => _chooseModel(group, model),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEfforts(
    BuildContext context,
    ModelGroup group,
    ModelOption model,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DshSpace.x2,
            DshSpace.x2,
            DshSpace.x4,
            DshSpace.x1,
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: '返回模型列表',
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                onPressed: () => setState(() => _effortModel = null),
              ),
              Expanded(
                child: Text(
                  '${model.name} · 推理力度',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.dshText.titleMedium,
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: DshSpace.x2),
            children: [
              for (final effort in model.efforts)
                ListTile(
                  title: Text(effort.name),
                  onTap: () => Navigator.of(
                    context,
                  ).pop<ModelSelection>(_selection(group, model, effort)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _chooseModel(ModelGroup group, ModelOption model) {
    if (model.efforts.length > 1) {
      setState(() {
        _group = group;
        _effortModel = model;
      });
      return;
    }
    final effort = model.efforts.isEmpty ? null : model.efforts.first;
    Navigator.of(context).pop<ModelSelection>(_selection(group, model, effort));
  }

  ModelSelection _selection(
    ModelGroup group,
    ModelOption model,
    ReasoningEffort? effort,
  ) => (
    group.id,
    model.id,
    effort?.id,
    effort == null ? model.name : '${model.name} ${effort.name}',
  );
}
