import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api_client.dart';
import 'login_page.dart';
import 'models.dart';
import 'onboarding_page.dart';
import 'ui.dart';
import 'workspace_store.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.api, this.workspaceStore});
  final ApiClient? api;
  final WorkspaceStore? workspaceStore;
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final ApiClient _api = widget.api ?? ApiClient();
  late final WorkspaceStore _store = widget.workspaceStore ?? WorkspaceStore();
  WorkspaceConnection? _workspace;
  AppUser? _claimedOwner;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final selected = await _store.selected();
      if (selected != null) {
        final verified = await _api.inspectWorkspace(selected.origin);
        if (verified.workspaceId == selected.workspaceId) {
          await _api.switchWorkspace(verified);
          _workspace = verified;
        } else {
          await _store.remove(selected.workspaceId);
        }
      }
    } catch (_) {
      _workspace = null;
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _selectWorkspace(WorkspaceConnection connection) async {
    await _store.add(connection);
    await _api.switchWorkspace(connection);
    await _store.select(connection);
    if (mounted) {
      setState(() {
        _workspace = connection;
        _claimedOwner = null;
      });
    }
  }

  Future<WorkspaceClaimResult> _claimOwner(
    WorkspaceClaimRequest request,
  ) async {
    final result = await _api.claimWorkspaceOwner(
      request.workspace,
      setupToken: request.setupToken,
      name: request.name,
      username: request.username,
      password: request.password,
      workspaceName: request.workspaceName,
    );
    final verified = await _api.inspectWorkspace(request.workspace.origin);
    if (verified.workspaceId != request.workspace.workspaceId ||
        !verified.ready ||
        verified.name != request.workspaceName.trim()) {
      throw const ApiException(
        'workspace_mismatch',
        'Workspace hasil klaim tidak cocok. Periksa dashboard Cloudflare sebelum melanjutkan.',
      );
    }
    await _selectWorkspace(verified);
    await _api.acceptSession(
      result.$1,
      result.$2,
      workspaceId: verified.workspaceId,
    );
    _claimedOwner = result.$1;
    return WorkspaceClaimResult(
      connection: verified,
      sessionToken: result.$2,
      ownerId: result.$1.id,
      ownerName: result.$1.name,
      username: result.$1.username,
    );
  }

  Future<void> _openSetup() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OnboardingPage(
          onWorkspaceSelected: _selectWorkspace,
          onVerifyWorkspace: (origin) async {
            final connection = await _api.inspectWorkspace(origin);
            return WorkspaceVerification(
              connection: connection,
              ready: connection.ready,
            );
          },
          onClaimOwner: _claimOwner,
          onOpenDeployLink: (uri) async {
            await Clipboard.setData(ClipboardData(text: uri.toString()));
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Tautan deployment disalin. Tempelkan di browser untuk melanjutkan.',
                  ),
                ),
              );
            }
          },
          store: _store,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (widget.api == null) _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.primary,
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: AppColors.ink,
        );
    return MaterialApp(
      title: 'Absensi & Bon',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.ink,
          centerTitle: false,
          scrolledUnderElevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: scheme.primaryContainer,
          height: 76,
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.border,
          thickness: 1,
        ),
      ),
      home: _checking
          ? const _WorkspaceLoading()
          : _workspace == null
          ? _WorkspaceRequired(onContinue: _openSetup)
          : LoginPage(
              api: _api,
              signedInUser: _claimedOwner,
              onChangeWorkspace: _openSetup,
            ),
    );
  }
}

class _WorkspaceLoading extends StatelessWidget {
  const _WorkspaceLoading();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _WorkspaceRequired extends StatelessWidget {
  const _WorkspaceRequired({required this.onContinue});
  final VoidCallback onContinue;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBody(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.business_outlined,
              color: Colors.white,
              size: 36,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Hubungkan usaha Anda',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Setiap usaha menggunakan Worker, database, dan penyimpanan foto milik Cloudflare akun sendiri. Buat workspace atau pindai QR dari pemilik.',
            style: TextStyle(color: AppColors.muted, height: 1.55),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onContinue,
            icon: const Icon(Icons.add_business_outlined),
            label: const Text('Buat atau gabung workspace'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Anda akan masuk ke Cloudflare untuk menyetujui deployment. Aplikasi tidak meminta Cloudflare API token.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, height: 1.45),
          ),
        ],
      ),
    ),
  );
}
