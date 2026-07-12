import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

void main() {
  runApp(const WaxDeckApp());
}

/// Server origin: on web the SPA is served by the WaxDeck server itself, so
/// relative URLs hit the same origin. Native/desktop dev builds default to
/// localhost and can override with `--dart-define=WAXDECK_BASE_URL=<url>`.
///
/// Note the Android loopback gotcha: an emulator reaches the host at
/// http://10.0.2.2:4420 (not localhost, which is the emulator itself), and a
/// physical device needs the host's LAN IP; pass either via WAXDECK_BASE_URL.
const _envBase = String.fromEnvironment('WAXDECK_BASE_URL');
String get _baseUrl =>
    _envBase.isNotEmpty ? _envBase : (kIsWeb ? '' : 'http://localhost:4420');

class WaxDeckApp extends StatelessWidget {
  const WaxDeckApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Dark-first per the UX blueprint; art-driven dynamic theming lands with
    // the real player UI.
    return MaterialApp(
      title: 'WaxDeck',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD9A648),
          brightness: Brightness.dark,
        ),
      ),
      home: const ShellPage(),
    );
  }
}

/// Placeholder shell: proves the app-to-server round trip through the
/// generated client by showing the server's health probe. The adaptive
/// library shell replaces this later.
class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  late final Future<ServerHealth> _health;

  @override
  void initState() {
    super.initState();
    _health = WaxDeckClient(baseUrl: _baseUrl).health();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('WaxDeck', style: textTheme.displaySmall),
            const SizedBox(height: 8),
            Text('Music, podcasts, and audiobooks', style: textTheme.bodyLarge),
            const SizedBox(height: 24),
            FutureBuilder<ServerHealth>(
              future: _health,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const CircularProgressIndicator();
                }
                final health = snapshot.data;
                if (snapshot.hasError || health == null || !health.ok) {
                  return Text(
                    'Server unreachable',
                    style: textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  );
                }
                return Text(
                  'Server ${health.version}, API v${health.apiVersion}',
                  style: textTheme.bodyMedium,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
