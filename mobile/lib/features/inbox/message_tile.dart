import 'package:flutter/material.dart';
import '../../data/inbox_repository.dart';

class SourceAvatar extends StatelessWidget {
  const SourceAvatar(this.source, {super.key});
  final String source;
  @override
  Widget build(BuildContext context) {
    const palette = [
      Color(0xFFE36547),
      Color(0xFF558275),
      Color(0xFF6383A5),
      Color(0xFFAA8852),
    ];
    final index =
        source.runes.fold<int>(0, (sum, rune) => sum + rune) % palette.length;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette[index].withValues(alpha: .12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        source.isEmpty ? '源' : source.characters.first,
        style: TextStyle(
          color: palette[index],
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class MessageTile extends StatefulWidget {
  const MessageTile({
    super.key,
    required this.message,
    required this.onTap,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
  });
  final InboxMessage message;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selecting;
  final bool selected;

  @override
  State<MessageTile> createState() => _MessageTileState();
}

class _MessageTileState extends State<MessageTile> {
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final colors = Theme.of(context).colorScheme;
    final time =
        '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}';
    final summary = message.excerpt.isEmpty ? message.summary : message.excerpt;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final labels = [
      if (!message.isRead) '未读',
      if (message.starred) '已收藏',
      switch (message.format) {
        'html' => '图文',
        'markdown' => '文档',
        _ => '文本',
      },
    ];
    return AnimatedScale(
      scale: pressed && !MediaQuery.disableAnimationsOf(context) ? .985 : 1,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOutCubic,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: widget.selected
            ? colors.primaryContainer
            : (dark ? const Color(0xFF22252A) : Colors.white),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onHighlightChanged: (value) => setState(() => pressed = value),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (widget.selecting)
                      Checkbox(
                        value: widget.selected,
                        onChanged: (_) => widget.onTap(),
                      )
                    else
                      SourceAvatar(message.source),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        message.source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  message.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    height: 1.4,
                    fontWeight: message.isRead
                        ? FontWeight.w600
                        : FontWeight.w700,
                  ),
                ),
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    for (final label in labels)
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: label == '未读'
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: label == '未读'
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
