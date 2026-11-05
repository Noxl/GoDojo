import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'analysis/katago.dart';
import 'app_state.dart';
import 'cloud/cloud_sync.dart';
import 'model/starter.dart';
import 'storage/storage.dart';
import 'ui/account.dart';
import 'ui/app_logo.dart';
import 'ui/board_view.dart';
import 'ui/editor_page.dart';
import 'ui/library_page.dart';
import 'ui/trainer_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await storage.init();
  final state = AppState();
  await state.loadSettings();
  await state.library.init();
  await importStarterPack(state.library);
  await state.analysis.load();
  try {
    await Supabase.initialize(url: kSupabaseUrl, publishableKey: kSupabaseKey);
    state.cloud
      ..onPasswordRecovery = () {
        final c = navigatorKey.currentContext;
        if (c != null) showAccount(c);
      }
      ..attach(Supabase.instance.client);
  } catch (e) {
    debugPrint('No accounts: $e');
  }
  runApp(GoDojoApp(state: state));
}

/// To open a dialog from outside the widgets (password e-mail link).
final navigatorKey = GlobalKey<NavigatorState>();

ThemeData _theme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF3D5A80),
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.neutral,
  );
  return ThemeData(
    colorScheme: scheme,
    visualDensity: VisualDensity.compact,
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
  );
}

class GoDojoApp extends StatelessWidget {
  const GoDojoApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          title: 'Go Dojo',
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          themeMode: state.themeMode,
          home: const HomeShell(),
        ),
      ),
    );
  }
}

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final body = switch (state.section) {
      AppSection.library => const LibraryPage(),
      AppSection.editor => const EditorPage(),
      AppSection.trainer => const TrainerPage(),
      AppSection.drill => const GlobalTrainerPage(),
    };
    const destinations = [
      (Icons.folder_outlined, Icons.folder, 'Library'),
      (Icons.edit_outlined, Icons.edit, 'Editor'),
      (Icons.school_outlined, Icons.school, 'Trainer'),
      (Icons.all_inclusive, Icons.all_inclusive, 'Global'),
    ];
    void select(int i) => AppSection.values[i] == AppSection.drill
        ? state.openDrill()
        : state.goTo(AppSection.values[i]);

    if (!wide) {
      return Scaffold(
        body: SafeArea(child: body),
        bottomNavigationBar: NavigationBar(
          selectedIndex: state.section.index,
          onDestinationSelected: select,
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: Icon(d.$1),
                selectedIcon: Icon(d.$2),
                label: d.$3,
              ),
          ],
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: state.section.index,
            onDestinationSelected: select,
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Tooltip(message: 'Go Dojo', child: AppLogo(size: 40)),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AccountButton(compact: true),
                      const SizedBox(height: 4),
                      IconButton(
                        tooltip: 'Settings',
                        onPressed: () => showSettings(context),
                        icon: const Icon(Icons.settings_outlined),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                  icon: Icon(d.$1),
                  selectedIcon: Icon(d.$2),
                  label: Text(d.$3),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}

Future<void> showSettings(BuildContext context) {
  final state = AppScope.read(context);
  return showDialog(
    context: context,
    builder: (c) => ListenableBuilder(
      listenable: state,
      builder: (c, _) => AlertDialog(
        title: const Text('Settings'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Theme'),
              const SizedBox(height: 6),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ],
                selected: {state.themeMode},
                onSelectionChanged: (v) => state.setThemeMode(v.first),
              ),
              const SizedBox(height: 20),
              const Text('Board'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final s in BoardStyle.values)
                    _BoardSwatch(
                      style: s,
                      selected: state.boardStyle == s,
                      onTap: () => state.setBoardStyle(s),
                    ),
                ],
              ),
              if (!kIsWeb) ...[
                const SizedBox(height: 20),
                const _KataGoSettings(),
                const SizedBox(height: 12),
                _analysisKeyRow(state),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );
}

Widget _analysisKeyRow(AppState state) => Row(
  children: [
    const Expanded(child: Text('Key to toggle the analysis in the editor')),
    SizedBox(
      width: 56,
      child: TextFormField(
        initialValue: state.analysisKey,
        maxLength: 1,
        textAlign: TextAlign.center,
        decoration: const InputDecoration(
          counterText: '',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        onChanged: state.setAnalysisKey,
      ),
    ),
  ],
);

class _BoardSwatch extends StatelessWidget {
  const _BoardSwatch({
    required this.style,
    required this.selected,
    required this.onTap,
  });
  final BoardStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [style.light, style.dark]),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(style.label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _KataGoSettings extends StatelessWidget {
  const _KataGoSettings();

  @override
  Widget build(BuildContext context) {
    final analysis = AppScope.read(context).analysis;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: analysis,
      builder: (context, _) {
        final paths = analysis.paths;
        String name(String path) => path.split(RegExp(r'[\/]')).last;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('KataGo (AI analysis)'),
            const SizedBox(height: 6),
            if (paths == null)
              Text('Not configured.', style: theme.textTheme.bodySmall)
            else
              Text(
                '${analysis.configured ? '✓' : '⚠ missing files:'} '
                '${name(paths.exe)} · ${name(paths.model)} · ${name(paths.config)}',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final dir = await FilePicker.getDirectoryPath(
                      dialogTitle:
                          'Folder containing katago.exe and a network (.bin.gz)',
                    );
                    if (dir == null) return;
                    final found = KataGoPaths.detect(dir);
                    if (found == null) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'No katago.exe and network (.bin.gz) found in that folder.',
                            ),
                          ),
                        );
                      }
                      return;
                    }
                    await analysis.setPaths(found);
                  },
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Choose KataGo folder…'),
                ),
                const Text('Visits per position:'),
                DropdownButton<int>(
                  value: analysis.maxVisits,
                  items: [
                    for (final v in {
                      100,
                      200,
                      500,
                      1000,
                      2000,
                      5000,
                      analysis.maxVisits,
                    })
                      DropdownMenuItem(value: v, child: Text('$v')),
                  ],
                  onChanged: (v) => analysis.setMaxVisits(v!),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
