import 'package:flutter/material.dart';

import '../models.dart';
import '../widgets/app_icons.dart';

class SkillsScreen extends StatefulWidget {
  const SkillsScreen({
    super.key,
    required this.isMaterial3Installed,
    required this.isMaterial3Active,
    required this.isLibraryReady,
    required this.isUpdatingLibrary,
    required this.onAddMaterial3,
    required this.onRemoveMaterial3,
    required this.onUseMaterial3,
    required this.localSkills,
    required this.activeSkillIds,
    required this.skillsDirectoryPath,
    required this.onSkillActiveChanged,
    required this.onRefreshLocalSkills,
  });

  final bool isMaterial3Installed;
  final bool isMaterial3Active;
  final bool isLibraryReady;
  final bool isUpdatingLibrary;
  final Future<bool> Function() onAddMaterial3;
  final Future<bool> Function() onRemoveMaterial3;
  final VoidCallback onUseMaterial3;
  final List<AgentSkillProfile> localSkills;
  final Set<String> activeSkillIds;
  final String? skillsDirectoryPath;
  final void Function(String, bool) onSkillActiveChanged;
  final Future<void> Function() onRefreshLocalSkills;

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  String _category = 'All skills';

  Future<void> _showDetails() => showDialog<void>(
        context: context,
        builder: (context) => _Material3SkillDialog(
          isInstalled: widget.isMaterial3Installed,
          isActive: widget.isMaterial3Active,
          isLibraryReady: widget.isLibraryReady,
          isUpdatingLibrary: widget.isUpdatingLibrary,
          onAdd: widget.onAddMaterial3,
          onRemove: widget.onRemoveMaterial3,
          onUse: widget.onUseMaterial3,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 600 ? 20.0 : 36.0;
        final cardWidth = constraints.maxWidth - horizontalPadding * 2 >= 390
            ? 370.0
            : constraints.maxWidth - horizontalPadding * 2;
        return SingleChildScrollView(
          key: const Key('page.skills'),
          padding:
              EdgeInsets.fromLTRB(horizontalPadding, 30, horizontalPadding, 36),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Skills',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 7),
                  Text(
                    'Add reusable guidance to your coding chats.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 25),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final category in ['All skills', 'Design'])
                        ChoiceChip(
                          key: Key(
                              'skills.filter.${category.toLowerCase().replaceAll(' ', '-')}'),
                          label: Text(category),
                          selected: _category == category,
                          onSelected: (_) =>
                              setState(() => _category = category),
                          showCheckmark: false,
                        ),
                    ],
                  ),
                  const SizedBox(height: 19),
                  if (_category == 'All skills' || _category == 'Design')
                    Wrap(
                      spacing: 18,
                      runSpacing: 18,
                      children: [
                        SizedBox(
                          width: cardWidth,
                          child: _Material3SkillCard(
                            isInstalled: widget.isMaterial3Installed,
                            isActive: widget.isMaterial3Active,
                            isLibraryReady: widget.isLibraryReady,
                            isUpdatingLibrary: widget.isUpdatingLibrary,
                            onAdd: widget.onAddMaterial3,
                            onUse: widget.onUseMaterial3,
                            onDetails: _showDetails,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      'No skills in this category yet.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  const SizedBox(height: 20),
                  _LocalSkillsSection(
                    skills: widget.localSkills
                        .where((skill) => !skill.isBundled)
                        .toList(growable: false),
                    activeSkillIds: widget.activeSkillIds,
                    directoryPath: widget.skillsDirectoryPath,
                    onSkillActiveChanged: widget.onSkillActiveChanged,
                    onRefresh: widget.onRefreshLocalSkills,
                  ),
                  const SizedBox(height: 24),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(AppIcons.infoOutlineRounded,
                              color: colors.primary, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Skills add instructions to a chat when enabled. They do not run installers or grant computer access.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    height: 1.45,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LocalSkillsSection extends StatefulWidget {
  const _LocalSkillsSection({
    required this.skills,
    required this.activeSkillIds,
    required this.directoryPath,
    required this.onSkillActiveChanged,
    required this.onRefresh,
  });

  final List<AgentSkillProfile> skills;
  final Set<String> activeSkillIds;
  final String? directoryPath;
  final void Function(String, bool) onSkillActiveChanged;
  final Future<void> Function() onRefresh;

  @override
  State<_LocalSkillsSection> createState() => _LocalSkillsSectionState();
}

class _LocalSkillsSectionState extends State<_LocalSkillsSection> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Your skills',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Refresh local skills',
                onPressed: _refreshing ? null : _refresh,
                icon: _refreshing
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(AppIcons.refreshRounded, size: 18),
              ),
            ],
          ),
          Text(
            widget.directoryPath == null
                ? 'Local skills are being prepared.'
                : 'Add a folder containing SKILL.md to ${widget.directoryPath}.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (widget.skills.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 13),
              child: Text(
                'No custom skills found. Locally added skills are read as guidance; their scripts are never run.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            )
          else ...[
            const SizedBox(height: 8),
            for (final skill in widget.skills)
              SwitchListTile.adaptive(
                key: Key('skills.local.${skill.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(skill.name),
                subtitle: Text(skill.description),
                value: widget.activeSkillIds.contains(skill.id),
                onChanged: (active) =>
                    widget.onSkillActiveChanged(skill.id, active),
              ),
          ],
        ],
      ),
    );
  }
}

class _Material3SkillCard extends StatelessWidget {
  const _Material3SkillCard({
    required this.isInstalled,
    required this.isActive,
    required this.isLibraryReady,
    required this.isUpdatingLibrary,
    required this.onAdd,
    required this.onUse,
    required this.onDetails,
  });

  final bool isInstalled;
  final bool isActive;
  final bool isLibraryReady;
  final bool isUpdatingLibrary;
  final Future<bool> Function() onAdd;
  final VoidCallback onUse;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Material3Artwork(height: 154),
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 15, 17, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Material Design 3',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    _StatusPill(
                      label: isInstalled ? 'Added' : 'Built in',
                      icon: isInstalled
                          ? AppIcons.checkRounded
                          : AppIcons.component,
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  'Implement Material 3 interfaces with components, design tokens, themes, responsive layouts, and accessibility guidance.',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(height: 1.45),
                ),
                const SizedBox(height: 12),
                const Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _CategoryTag('Design'),
                    _CategoryTag('Flutter'),
                    _CategoryTag('Jetpack Compose'),
                    _CategoryTag('Web'),
                  ],
                ),
                const SizedBox(height: 15),
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: [
                    if (isInstalled)
                      FilledButton.icon(
                        key: const Key('skills.material3.use'),
                        onPressed: onUse,
                        icon: const Icon(AppIcons.chatBubbleOutlineRounded,
                            size: 16),
                        label:
                            Text(isActive ? 'Active in chat' : 'Use in chat'),
                      )
                    else
                      FilledButton.icon(
                        key: const Key('skills.material3.add'),
                        onPressed: isLibraryReady && !isUpdatingLibrary
                            ? () => onAdd()
                            : null,
                        icon: isUpdatingLibrary
                            ? const SizedBox.square(
                                dimension: 15,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(AppIcons.addRounded, size: 17),
                        label: const Text('Add to my skills'),
                      ),
                    OutlinedButton.icon(
                      key: const Key('skills.material3.details'),
                      onPressed: onDetails,
                      icon: const Icon(AppIcons.infoOutlineRounded, size: 16),
                      label: const Text('View details'),
                    ),
                  ],
                ),
                if (!isLibraryReady) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Loading your skills…',
                    style:
                        TextStyle(color: colors.onSurfaceVariant, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Material3SkillDialog extends StatelessWidget {
  const _Material3SkillDialog({
    required this.isInstalled,
    required this.isActive,
    required this.isLibraryReady,
    required this.isUpdatingLibrary,
    required this.onAdd,
    required this.onRemove,
    required this.onUse,
  });

  final bool isInstalled;
  final bool isActive;
  final bool isLibraryReady;
  final bool isUpdatingLibrary;
  final Future<bool> Function() onAdd;
  final Future<bool> Function() onRemove;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 620;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 820,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(AppIcons.closeRounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 2, 24, 23),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (compact) ...[
                      const _Material3Artwork(height: 142),
                      const SizedBox(height: 20),
                    ],
                    const Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: const [
                        _CategoryTag('Design'),
                        _CategoryTag('Flutter'),
                        _CategoryTag('Jetpack Compose'),
                        _CategoryTag('Web'),
                      ],
                    ),
                    const SizedBox(height: 11),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Material Design 3',
                                style:
                                    Theme.of(context).textTheme.headlineMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'From hamen/material-3-skill · MIT license',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 15),
                              Text(
                                'Guidance for building interfaces with Google’s Material Design 3 system. It covers color and typography tokens, components, theming, adaptive layouts, motion, and accessibility. Jetpack Compose is the primary focus, with Flutter guidance and a limited web path.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: colors.onSurface,
                                      height: 1.55,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        if (!compact) ...[
                          const SizedBox(width: 22),
                          const SizedBox(
                            width: 190,
                            child: _Material3Artwork(height: 166),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text('What it covers',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    const Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _TopicPill(
                            icon: AppIcons.palette, label: 'Color and theming'),
                        _TopicPill(
                            icon: AppIcons.component, label: '30+ components'),
                        _TopicPill(
                            icon: AppIcons.devicesOutlined,
                            label: 'Adaptive layouts'),
                        _TopicPill(
                            icon: AppIcons.accessibility,
                            label: 'Accessibility'),
                      ],
                    ),
                    const SizedBox(height: 23),
                    Text('Example prompts',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    const _ExamplePrompt(
                      text:
                          'Build a responsive Flutter settings screen using Material 3 components and color roles.',
                    ),
                    const SizedBox(height: 8),
                    const _ExamplePrompt(
                      text:
                          'Create a Material 3 light and dark theme from the project’s existing brand color.',
                    ),
                    const SizedBox(height: 8),
                    const _ExamplePrompt(
                      text:
                          'Review this interface for Material 3 layout, typography, shape, motion, and accessibility.',
                    ),
                    const SizedBox(height: 17),
                    Text(
                      'The skill is bundled with Penguin Code and works offline. Its instructions and relevant references are sent to the selected model only when the skill is enabled for a chat.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(height: 1.45),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (isInstalled)
                    TextButton.icon(
                      key: const Key('skills.material3.remove'),
                      onPressed: isUpdatingLibrary
                          ? null
                          : () async {
                              if (await onRemove() && context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                      icon: const Icon(AppIcons.deleteOutlineRounded, size: 16),
                      label: const Text('Remove from my skills'),
                    )
                  else
                    OutlinedButton.icon(
                      key: const Key('skills.material3.add'),
                      onPressed: isLibraryReady && !isUpdatingLibrary
                          ? () async {
                              if (await onAdd() && context.mounted) {
                                Navigator.pop(context);
                              }
                            }
                          : null,
                      icon: isUpdatingLibrary
                          ? const SizedBox.square(
                              dimension: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(AppIcons.addRounded, size: 17),
                      label: const Text('Add to my skills'),
                    ),
                  FilledButton.icon(
                    key: const Key('skills.material3.use'),
                    onPressed: isInstalled && isLibraryReady
                        ? () {
                            onUse();
                            Navigator.pop(context);
                          }
                        : null,
                    icon:
                        const Icon(AppIcons.chatBubbleOutlineRounded, size: 16),
                    label: Text(isActive ? 'Active in chat' : 'Use in chat'),
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

class _Material3Artwork extends StatelessWidget {
  const _Material3Artwork({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: Container(
        height: height,
        color: colors.surfaceContainerLow,
        child: Stack(
          children: [
            Positioned(
              top: -38,
              right: -14,
              child: Container(
                width: height * 0.95,
                height: height * 0.95,
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.76),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(17),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(AppIcons.palette, color: colors.primary, size: 20),
                        const SizedBox(height: 8),
                        Text(
                          'Material',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: colors.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        Text(
                          'Design 3',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: colors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Color · Type · Shape',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _TokenSample(label: 'Primary', color: colors.primary),
                      const SizedBox(height: 7),
                      _TokenSample(
                        label: 'Surface',
                        color: colors.surfaceContainerHigh,
                      ),
                      const SizedBox(height: 7),
                      _TokenSample(
                        label: 'Outline',
                        color: colors.outlineVariant,
                      ),
                    ],
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

class _TokenSample extends StatelessWidget {
  const _TokenSample({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(width: 7),
          Container(
            width: 23,
            height: 23,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
        ],
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colors.onSecondaryContainer),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTag extends StatelessWidget {
  const _CategoryTag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _TopicPill extends StatelessWidget {
  const _TopicPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colors.primary),
          const SizedBox(width: 7),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _ExamplePrompt extends StatelessWidget {
  const _ExamplePrompt({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.chatBubbleOutlineRounded,
              size: 16, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style:
                  Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
