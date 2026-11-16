import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'data/inbox_repository.dart';
import 'features/inbox/inbox_page.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DingdongApp());
}

class DingdongApp extends StatelessWidget {
  const DingdongApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '叮咚',
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    debugShowCheckedModeBanner: false,
    theme: inboxTheme(Brightness.light),
    darkTheme: inboxTheme(Brightness.dark),
    home: InboxPage(repository: InboxRepository()),
  );
}
