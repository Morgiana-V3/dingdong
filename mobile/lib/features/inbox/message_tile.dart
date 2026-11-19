import '../../data/message_preview.dart';
import 'package:flutter/material.dart';
import '../../data/inbox_repository.dart';

class MessageTile extends StatelessWidget {
  const MessageTile({
    super.key,
    required this.message,
    required this.preview,
    required this.onTap,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
  });

  final InboxMessage message;
  final Future<MessagePreview?>? preview;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final time =
        '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}';
    final meta = TextStyle(
      fontSize: 12,
      color: colors.onSurfaceVariant,
      height: 1.3,
    );
    return FutureBuilder<MessagePreview?>(
      future: preview,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final headline = data?.headline ?? '';
        final title = headline.isEmpty ? message.title : headline;
        final summary =
            (data?.hasTranslation == true
                    ? data!.description
                    : message.excerpt.isNotEmpty
                    ? message.excerpt
                    : headline.isNotEmpty
                    ? data!.description
                    : message.summary)
                .trim();
        final taskName = data?.taskName ?? '';
        final label = taskName.isNotEmpty
            ? taskName
            : headline.isNotEmpty
            ? message.title
            : message.source;
        final image = data?.cover;
        return Semantics(
          selected: selecting ? selected : null,
          child: Card(
            color: colors.surfaceContainerLow,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: selected
                    ? colors.primary
                    : colors.outlineVariant.withValues(alpha: .52),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = (constraints.maxWidth * .27).clamp(
                          64.0,
                          118.0,
                        );
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 15,
                                      height: 1.4,
                                      color: colors.onSurface,
                                      fontWeight: message.isRead
                                          ? FontWeight.w500
                                          : FontWeight.w600,
                                    ),
                                  ),
                                  if (summary.isNotEmpty &&
                                      summary != title) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      summary,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.45,
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (image != null) ...[
                              const SizedBox(width: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  image,
                                  width: width,
                                  height: width * .72,
                                  fit: BoxFit.cover,
                                  excludeFromSemantics: true,
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (selecting)
                                Icon(
                                  selected
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  size: 16,
                                  color: selected
                                      ? colors.primary
                                      : colors.outline,
                                  semanticLabel: selected ? '已选中' : '未选中',
                                ),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: colors.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!message.isRead) ...[
                                        Icon(
                                          Icons.circle,
                                          size: 5,
                                          color: colors.primary,
                                          semanticLabel: '未读',
                                        ),
                                        const SizedBox(width: 5),
                                      ],
                                      Flexible(
                                        child: Text(
                                          label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: meta.copyWith(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (message.starred)
                                Icon(
                                  Icons.bookmark_rounded,
                                  size: 14,
                                  color: colors.primary,
                                  semanticLabel: '已收藏',
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(time, style: meta),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
