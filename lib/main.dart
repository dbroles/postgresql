import 'package:material_ui/material_ui.dart';
import 'views/role_manager_home.dart';

final ValueNotifier<ThemeMode> appThemeModeNotifier = ValueNotifier<ThemeMode>(.system);

void main() {
  runApp(const MyApp());
}

class const MyApp({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeModeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'User Manager for PostgreSQL',
          debugShowCheckedModeBanner: false,
          scrollBehavior: const MaterialScrollBehavior().copyWith(
            dragDevices: {
              .mouse,
              .touch,
              .stylus,
              .trackpad,
            },
          ),
          theme: ThemeData(
            colorScheme: .fromSeed(
              seedColor: const Color(0xFF88AA00),
              brightness: .light,
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: .fromSeed(
              seedColor: const Color(0xFF88AA00),
              brightness: .dark,
            ),
          ),
          themeMode: themeMode,
          home: const RoleManagerHome(),
        );
      },
    );
  }
}
