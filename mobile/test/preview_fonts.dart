import 'dart:io';
import 'package:flutter/services.dart';

Future<void> loadPreviewFonts() async {
  if (!Platform.isWindows) return;
  final bytes = await File(
    '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts/msyh.ttc',
  ).readAsBytes();
  for (final family in ['Roboto']) {
    await (FontLoader(
      family,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }
  var directory = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    final font = File(
      '${directory.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (await font.exists()) {
      final icons = await font.readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(icons)))).load();
      return;
    }
    directory = directory.parent;
  }
  throw StateError('Cannot locate the Flutter Material icon font for previews');
}
