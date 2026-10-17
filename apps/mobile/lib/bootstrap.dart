import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ui/account_view_model.dart';
import 'data/account_api.dart';
import 'data/backend_config.dart';
import 'data/supabase_sessions.dart';
import 'data/command_journal.dart';
import 'data/private_values.dart';

Future<AccountViewModel> createAccountServices() async {
  try {
    final config = BackendConfig.fromEnvironment();
    if (config == null) return AccountViewModel();
    final LocalStorage storage = kIsWeb
        ? const EmptyLocalStorage()
        : SecureSessionStorage(
            key: 'awaaz.session.v1.${config.supabaseUrl.host}',
          );
    final supabase = await Supabase.initialize(
      url: config.supabaseUrl.toString(),
      publishableKey: config.publishableKey,
      debug: false,
      authOptions: FlutterAuthClientOptions(
        localStorage: storage,
        detectSessionInUri: false,
      ),
    );
    final sessions = SupabaseSessions(supabase.client, storage);
    final client = http.Client();
    return AccountViewModel(
      sessions: sessions,
      journal: CommandJournal(
        values: kIsWeb ? MemoryPrivateValues() : const SecurePrivateValues(),
        namespace: '${config.supabaseUrl}|${config.apiUrl}',
      ),
      repository: AccountApi(
        baseUrl: config.apiUrl,
        sessions: sessions,
        client: client,
      ),
      onClose: client.close,
    );
  } catch (_) {
    // Startup failure must leave the preview usable and reveal no config/key.
    return AccountViewModel(configurationProblem: true);
  }
}
