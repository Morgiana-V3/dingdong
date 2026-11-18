import 'package:flutter/material.dart';

class ConnectionBadge extends StatelessWidget {
  const ConnectionBadge({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final connected = status == '已连接';
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = connected
        ? (dark ? const Color(0xFF8CD7AE) : const Color(0xFF26734D))
        : (dark ? const Color(0xFFFFA89C) : const Color(0xFFB14535));
    return Tooltip(
      message: status,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              connected ? '已连接' : '未连接',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
