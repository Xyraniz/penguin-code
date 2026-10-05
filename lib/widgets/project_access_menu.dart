import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import 'app_icons.dart';

extension AgentPermissionModePresentation on AgentPermissionMode {
  String get title => switch (this) {
        AgentPermissionMode.chatOnly => 'Chat only',
        AgentPermissionMode.askBeforeEachAction => 'Ask before every action',
        AgentPermissionMode.autoApproveProjectReads => 'Auto-approve reads',
        AgentPermissionMode.fullAccess => 'Full access',
      };

  String get description => switch (this) {
        AgentPermissionMode.chatOnly =>
          'The agent cannot access files on your computer.',
        AgentPermissionMode.askBeforeEachAction =>
          'Approve every file list, search, or read anywhere on the computer. File edits always ask first.',
        AgentPermissionMode.autoApproveProjectReads =>
          'List, search, and read supported files anywhere. File edits still require approval.',
        AgentPermissionMode.fullAccess =>
          'Read and edit files anywhere and run commands without per-action approval. Risky.',
      };

  String get compactLabel => switch (this) {
        AgentPermissionMode.chatOnly => 'Chat only',
        AgentPermissionMode.askBeforeEachAction => 'Ask first',
        AgentPermissionMode.autoApproveProjectReads => 'Read access',
        AgentPermissionMode.fullAccess => 'Full access',
      };

  IconData get icon => switch (this) {
        AgentPermissionMode.chatOnly => AppIcons.chatBubbleOutlineRounded,
        AgentPermissionMode.askBeforeEachAction => AppIcons.hand,
        AgentPermissionMode.autoApproveProjectReads => AppIcons.shieldCheck,
        AgentPermissionMode.fullAccess => AppIcons.securityOutlined,
      };
}

class ProjectAccessMenu extends StatelessWidget {
  const ProjectAccessMenu({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
    this.enabled = true,
  });

  final AgentPermissionMode value;
  final ValueChanged<AgentPermissionMode> onChanged;
  final bool compact;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<AgentPermissionMode>(
      key: const Key('project.access.menu'),
      enabled: enabled,
      tooltip: 'Computer access: ${value.title}',
      position: PopupMenuPosition.over,
      constraints: const BoxConstraints(minWidth: 340, maxWidth: 360),
      onSelected: (mode) async {
        if (mode == value) return;
        if (mode != AgentPermissionMode.fullAccess) {
          onChanged(mode);
          return;
        }
        final enabled = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            key: const Key('project.access.confirm.dialog'),
            constraints: const BoxConstraints(maxWidth: 460),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            icon: const Icon(
              AppIcons.securityOutlined,
              color: AppColors.amber,
            ),
            title: const Text('Enable full access?'),
            content: const Text(
              'The connected model can read and edit files anywhere on your computer and run commands without confirmation. It could overwrite or delete data. File contents and command output are sent to your selected provider. Only enable this for a model you trust.',
              style: TextStyle(height: 1.45),
            ),
            actions: [
              TextButton(
                key: const Key('project.access.confirm.cancel'),
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('project.access.confirm.enable'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Enable full access'),
              ),
            ],
          ),
        );
        if (enabled == true) onChanged(mode);
      },
      itemBuilder: (context) => [
        const PopupMenuItem<AgentPermissionMode>(
          enabled: false,
          height: 43,
          child: Padding(
            padding: EdgeInsets.only(left: 2, top: 4),
            child: Text(
              'Computer access',
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        for (final mode in AgentPermissionMode.values)
          PopupMenuItem<AgentPermissionMode>(
            key: Key('project.access.option.${mode.name}'),
            value: mode,
            height: 79,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: mode == AgentPermissionMode.fullAccess
                        ? const Color(0xFFFFF5E5)
                        : AppColors.ice,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    mode.icon,
                    size: 18,
                    color: mode == AgentPermissionMode.fullAccess
                        ? AppColors.amber
                        : AppColors.blueDeep,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mode.title,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        mode.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 18,
                  child: mode == value
                      ? const Icon(
                          AppIcons.checkRounded,
                          size: 18,
                          color: AppColors.blueDeep,
                        )
                      : null,
                ),
              ],
            ),
          ),
      ],
      child: Container(
        key: const Key('project.access.current'),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 9 : 12,
          vertical: compact ? 7 : 10,
        ),
        decoration: BoxDecoration(
          color: enabled ? AppColors.ice : AppColors.canvas,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(compact ? 10 : 12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value.icon,
              size: compact ? 15 : 17,
              color: value == AgentPermissionMode.fullAccess
                  ? AppColors.amber
                  : AppColors.blueDeep,
            ),
            const SizedBox(width: 6),
            Text(
              compact ? value.compactLabel : value.title,
              style: TextStyle(
                color: enabled ? AppColors.ink : AppColors.muted,
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 3),
            const Icon(
              AppIcons.keyboardArrowDownRounded,
              size: 16,
              color: AppColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}
