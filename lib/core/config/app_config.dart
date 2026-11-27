/// Build-time configuration. Values come from `--dart-define` (or a local
/// .env passed by tooling). No keys are stored in this repository.
abstract final class AppConfig {
  static const String supabaseUrl = String.fromEnvironment(
    'NEXT_PUBLIC_SUPABASE_URL',
  );
  static const String supabasePublishableKey = String.fromEnvironment(
    'NEXT_PUBLIC_SUPABASE_PUBLISHABLE_DEFAULT_KEY',
  );
  static const String cloudflareWorkerUrl = String.fromEnvironment(
    'CLOUDFLARE_WORKER_URL',
  );

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
  static bool get hasWorker => cloudflareWorkerUrl.isNotEmpty;

  static const String buildHint =
      'Pass --dart-define=NEXT_PUBLIC_SUPABASE_URL=...,'
      '--dart-define=NEXT_PUBLIC_SUPABASE_PUBLISHABLE_DEFAULT_KEY=...,'
      '--dart-define=CLOUDFLARE_WORKER_URL=...';
}
