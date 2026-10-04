import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import 'app_icons.dart';

class ModelPickerDialog extends StatefulWidget {
  const ModelPickerDialog({
    super.key,
    required this.providers,
    required this.selectedProviderId,
    required this.selectedModelId,
    required this.onConfigureModels,
  });

  final List<ProviderProfile> providers;
  final String? selectedProviderId;
  final String? selectedModelId;
  final VoidCallback onConfigureModels;

  @override
  State<ModelPickerDialog> createState() => _ModelPickerDialogState();
}

class _ModelPickerDialogState extends State<ModelPickerDialog> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ProviderProfile> get _filteredProviders {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.providers;
    return [
      for (final provider in widget.providers)
        if (provider.name.toLowerCase().contains(query) ||
            provider.availableModels.any(
              (model) =>
                  model.id.toLowerCase().contains(query) ||
                  model.displayName.toLowerCase().contains(query),
            ))
          provider.copyWith(
            models: [
              for (final model in provider.availableModels)
                if (provider.name.toLowerCase().contains(query) ||
                    model.id.toLowerCase().contains(query) ||
                    model.displayName.toLowerCase().contains(query))
                  model,
            ],
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final providers = _filteredProviders;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 540,
        height: size.height < 660 ? size.height * .78 : 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 19, 16, 13),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Choose a model',
                          style: TextStyle(
                            color: AppColors.ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Select a model from a connected provider.',
                          style:
                              TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(AppIcons.closeRounded, size: 19),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: TextField(
                key: const Key('model.picker.search'),
                controller: _search,
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search models or providers',
                  prefixIcon: const Icon(AppIcons.searchRounded, size: 18),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(AppIcons.closeRounded, size: 16),
                        ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: providers.isEmpty
                  ? _EmptyModels(query: _query)
                  : ListView(
                      key: const Key('model.picker.list'),
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      children: [
                        for (final provider in providers) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(9, 9, 9, 5),
                            child: Row(
                              children: [
                                Icon(
                                  provider.onDevice
                                      ? AppIcons.devicesOutlined
                                      : AppIcons.cloudOutlined,
                                  size: 15,
                                  color: AppColors.blueDeep,
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    provider.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.blueDeep,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: .2,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${provider.availableModels.length} ${provider.availableModels.length == 1 ? 'model' : 'models'}',
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          for (final model in provider.availableModels.where(
                            (item) =>
                                provider.models.isEmpty ||
                                _query.isEmpty ||
                                provider.name.toLowerCase().contains(
                                      _query.toLowerCase(),
                                    ) ||
                                item.id.toLowerCase().contains(
                                      _query.toLowerCase(),
                                    ) ||
                                item.displayName.toLowerCase().contains(
                                      _query.toLowerCase(),
                                    ),
                          ))
                            _ModelOption(
                              key: ValueKey(
                                'model.option.${provider.id}.${model.id}',
                              ),
                              provider: provider,
                              model: model,
                              selected:
                                  widget.selectedProviderId == provider.id &&
                                      widget.selectedModelId == model.id,
                              onTap: () => Navigator.pop(
                                context,
                                ModelReference(
                                  providerId: provider.id,
                                  modelId: model.id,
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Models are loaded from each provider endpoint.',
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('model.picker.manage'),
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onConfigureModels();
                    },
                    icon: const Icon(AppIcons.tuneRounded, size: 15),
                    label: const Text('Manage providers'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelOption extends StatelessWidget {
  const _ModelOption({
    super.key,
    required this.provider,
    required this.model,
    required this.selected,
    required this.onTap,
  });

  final ProviderProfile provider;
  final ModelProfile model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final badges = <(IconData, String)>[
      if (model.contextWindow != null)
        (AppIcons.modelContext, _formatContext(model.contextWindow!)),
      if (model.maxOutputTokens != null)
        (
          AppIcons.modelContext,
          '${_formatCount(model.maxOutputTokens!)} output'
        ),
      if (model.supportsImages == true) (AppIcons.imageOutlined, 'Images'),
      if (model.supportsTools == true) (AppIcons.modelTools, 'Tools'),
      if (model.canReason == true) (AppIcons.modelReasoning, 'Reasoning'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? AppColors.ice : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            child: Row(
              children: [
                Icon(
                  AppIcons.smartToyOutlined,
                  size: 18,
                  color: selected ? AppColors.blueDeep : AppColors.muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (model.name.isNotEmpty && model.name != model.id)
                        Text(
                          model.id,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 10.5,
                          ),
                        ),
                      if (badges.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 9,
                          runSpacing: 4,
                          children: [
                            for (final badge in badges)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(badge.$1,
                                      size: 12, color: AppColors.muted),
                                  const SizedBox(width: 4),
                                  Text(
                                    badge.$2,
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected)
                  const Icon(
                    AppIcons.checkRounded,
                    size: 17,
                    color: AppColors.blue,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatContext(int tokens) => tokens >= 1000
      ? '${(tokens / 1000).toStringAsFixed(tokens % 1000 == 0 ? 0 : 1)}k context'
      : '$tokens context';

  String _formatCount(int tokens) => tokens >= 1000
      ? '${(tokens / 1000).toStringAsFixed(tokens % 1000 == 0 ? 0 : 1)}k'
      : '$tokens';
}

class _EmptyModels extends StatelessWidget {
  const _EmptyModels({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final message = query.isEmpty
        ? 'Add a provider to load available models.'
        : 'No models or providers match "$query".';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.searchRounded, color: AppColors.sky, size: 27),
            const SizedBox(height: 9),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
