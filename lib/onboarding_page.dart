import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'cloudflare_admin.dart';

import 'ui.dart';
import 'workspace_qr_page.dart';
import 'workspace_store.dart';

class WorkspaceVerification {
  const WorkspaceVerification({required this.connection, required this.ready});
  final WorkspaceConnection connection;
  final bool ready;
}

class WorkspaceClaimRequest {
  const WorkspaceClaimRequest({
    required this.workspace,
    required this.setupToken,
    required this.name,
    required this.username,
    required this.password,
    required this.workspaceName,
  });
  final WorkspaceConnection workspace;
  final String setupToken;
  final String name;
  final String username;
  final String password;
  final String workspaceName;
}

class WorkspaceClaimResult {
  const WorkspaceClaimResult({
    required this.connection,
    required this.sessionToken,
    required this.ownerId,
    required this.ownerName,
    required this.username,
  });
  final WorkspaceConnection connection;
  final String sessionToken;
  final String ownerId;
  final String ownerName;
  final String username;
}

typedef WorkspaceVerifier =
    Future<WorkspaceVerification> Function(String origin);
typedef WorkspaceClaimer =
    Future<WorkspaceClaimResult> Function(WorkspaceClaimRequest request);
typedef DeployLinkOpener = Future<void> Function(Uri uri);

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    required this.onWorkspaceSelected,
    this.onVerifyWorkspace,
    this.onClaimOwner,
    this.onOpenDeployLink,
    this.store,
    this.initialWorkspace,
  });
  final Future<void> Function(WorkspaceConnection) onWorkspaceSelected;
  final WorkspaceVerifier? onVerifyWorkspace;
  final WorkspaceClaimer? onClaimOwner;
  final DeployLinkOpener? onOpenDeployLink;
  final WorkspaceStore? store;
  final WorkspaceConnection? initialWorkspace;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const _fallbackDeployUrl =
      'https://deploy.workers.cloudflare.com/?url=https://github.com/MEKL20/absensi_bon_app/tree/main/cloudflare';
  late final WorkspaceStore _store = widget.store ?? WorkspaceStore();
  final _origin = TextEditingController();
  final _setupToken = TextEditingController();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _workspaceName = TextEditingController();
  List<WorkspaceConnection> _workspaces = [];
  WorkspaceConnection? _verified;
  bool _loading = false;
  bool _digestVisible = false;
  String? _error;
  bool _autoRunning = false;
  List<String> _autoSteps = [];
  String? _autoError;
  StreamSubscription<Uri>? _linkSub;
  ({String verifier, String state, String setupToken})? _pendingOAuth;

  static const _oauthClientId = String.fromEnvironment(
    'CLOUDFLARE_OAUTH_CLIENT_ID',
  );
  static const _oauthRedirect = 'absensi-bon://oauth';
  static final _oauthScopeIds = String.fromEnvironment(
    'CLOUDFLARE_OAUTH_SCOPES',
  ).split(',').where((value) => value.isNotEmpty).toList();

  String _randomHex() {
    final random = Random.secure();
    return List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> _startAutomaticSetup() async {
    if (_autoRunning || widget.onClaimOwner == null) return;
    if (_oauthScopeIds.isEmpty) {
      setState(
        () => _autoError =
            'Build ini belum dikonfigurasi dengan scope OAuth Cloudflare.',
      );
      return;
    }
    setState(() {
      _autoRunning = true;
      _autoError = null;
      _autoSteps = [];
    });
    final setupToken = _randomHex();
    final state = _randomHex();
    final admin = CloudflareAdmin(
      clientId: _oauthClientId,
      redirectUri: _oauthRedirect,
    );
    final verifier = admin.newPkceVerifier();
    _pendingOAuth = (verifier: verifier, state: state, setupToken: setupToken);
    try {
      await launchUrl(
        admin.authorizeUrl(
          state: state,
          codeChallenge: admin.challengeFor(verifier),
          scopeIds: _oauthScopeIds,
        ),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _autoRunning = false;
          _autoError = 'Tidak dapat membuka browser untuk login Cloudflare.';
        });
      }
    }
  }

  void _handleOAuthLink(Uri uri) {
    if (uri.scheme != 'absensi-bon' || uri.host != 'oauth') return;
    final pending = _pendingOAuth;
    if (pending == null) return;
    final code = uri.queryParameters['code'];
    if (uri.queryParameters['state'] != pending.state ||
        code == null ||
        code.isEmpty) {
      setState(() {
        _autoRunning = false;
        _autoError =
            'Respons login Cloudflare tidak cocok atau ditolak. Ulangi setup.';
      });
      return;
    }
    _continueAutomaticSetup(code, pending);
  }

  Future<void> _continueAutomaticSetup(
    String code,
    ({String verifier, String state, String setupToken}) pending,
  ) async {
    final admin = CloudflareAdmin(
      clientId: _oauthClientId,
      redirectUri: _oauthRedirect,
    );
    try {
      final session = await admin.exchangeCode(
        code: code,
        codeVerifier: pending.verifier,
      );
      final bundle = await rootBundle.load('assets/cloudflare_worker.js');
      final migrationRows =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/cloudflare_migrations.json',
                ),
              )
              as List;
      final workspace = await admin.provision(
        session: session,
        workerName: 'absensi-bon-api',
        databaseName: 'absensi-bon',
        bucketName: 'absensi-bon-photos',
        workerBundle: bundle.buffer.asUint8List(),
        migrations: migrationRows
            .map(
              (row) =>
                  CloudflareMigration.fromJson(row as Map<String, dynamic>),
            )
            .toList(),
        vars: const {
          'BUSINESS_TIMEZONE': 'Asia/Jakarta',
          'SESSION_TTL_SECONDS': '86400',
          'MAX_BON_AMOUNT': '1000000000',
          'PHOTO_RETENTION_DAYS': '0',
        },
        crons: const ['17 3 * * *'],
        compatibilityDate: '2026-08-06',
        setupDigest: sha256.convert(utf8.encode(pending.setupToken)).toString(),
        onProgress: (step) {
          if (mounted) setState(() => _autoSteps.add(step));
        },
      );
      _setupToken.text = pending.setupToken;
      _origin.text = workspace.origin;
      final verification = await _verifyOrigin(workspace.origin);
      if (mounted) {
        setState(() {
          _verified = verification.connection;
          _autoRunning = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _autoRunning = false;
          _autoError =
              error is CloudflareAdminException || error is FormatException
              ? '$error'
              : 'Setup otomatis gagal. Periksa koneksi dan izin akun Cloudflare.';
        });
      }
    } finally {
      _pendingOAuth = null;
    }
  }

  Uri get _deployUri => Uri.parse(
    const String.fromEnvironment(
      'DEPLOY_BUTTON_URL',
      defaultValue: _fallbackDeployUrl,
    ),
  );
  String get _digest =>
      sha256.convert(utf8.encode(_setupToken.text)).toString();

  @override
  void initState() {
    super.initState();
    _load();
    if (_oauthClientId.isNotEmpty) {
      _linkSub = AppLinks().uriLinkStream.listen(_handleOAuthLink);
    }
    final initial = widget.initialWorkspace;
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _verifyQr(initial));
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _setupToken.clear();
    _password.clear();
    _origin.dispose();
    _setupToken.dispose();
    _name.dispose();
    _username.dispose();
    _password.dispose();
    _workspaceName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final values = await _store.list();
      if (mounted) setState(() => _workspaces = values);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Data workspace aman tidak dapat dibaca.');
      }
    }
  }

  Future<WorkspaceVerification> _verifyOrigin(String origin) async {
    final base = parseWorkspaceOrigin(origin);
    if (widget.onVerifyWorkspace != null) {
      final result = await widget.onVerifyWorkspace!(base.toString());
      if (result.connection.origin != base.toString() ||
          !RegExp(r'^[0-9a-f]{32}$').hasMatch(result.connection.workspaceId) ||
          result.connection.name.trim().isEmpty ||
          result.connection.name.length > 100) {
        throw const FormatException(
          'Origin atau identitas hasil verifikasi tidak cocok.',
        );
      }
      return result;
    }
    final client = http.Client();
    try {
      final request = http.Request('GET', base.replace(path: '/v1/workspace'))
        ..followRedirects = false
        ..headers['Accept'] = 'application/json';
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 12));
      final body = await response.stream.bytesToString();
      if (response.statusCode != 200) {
        throw const FormatException(
          'Endpoint workspace tidak merespons. Periksa alamat dan aktifkan resource deployment.',
        );
      }
      final data = jsonDecode(body);
      if (data is! Map<String, dynamic> ||
          data.keys.toSet().difference({'id', 'name', 'ready'}).isNotEmpty ||
          data['id'] is! String ||
          data['name'] is! String ||
          data['ready'] is! bool ||
          !RegExp(r'^[0-9a-f]{32}$').hasMatch(data['id'] as String) ||
          (data['name'] as String).trim().isEmpty ||
          (data['name'] as String).length > 100) {
        throw const FormatException('Respons endpoint workspace tidak valid.');
      }
      return WorkspaceVerification(
        connection: WorkspaceConnection(
          origin: base.toString(),
          workspaceId: data['id'] as String,
          name: data['name'] as String,
        ),
        ready: data['ready'] as bool,
      );
    } finally {
      client.close();
    }
  }

  Future<bool> _confirm(WorkspaceConnection value) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Konfirmasi layanan'),
          content: Text(
            'Pastikan layanan ini milik usaha yang benar.\n\n${value.name}\n${value.origin}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Lanjutkan'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _verifyQr(WorkspaceConnection qr) async {
    if (_loading) return;
    try {
      parseWorkspaceOrigin(qr.origin);
      if (!await _confirm(qr)) return;
      setState(() {
        _loading = true;
        _error = null;
      });
      final result = await _verifyOrigin(qr.origin);
      if (result.connection.origin != qr.origin ||
          result.connection.workspaceId != qr.workspaceId ||
          result.connection.name != qr.name) {
        throw const FormatException(
          'Informasi QR tidak cocok dengan layanan. Minta QR terbaru dari pemilik workspace.',
        );
      }
      if (!result.ready) {
        throw const FormatException('Workspace belum memiliki akun pemilik.');
      }
      await _connect(result.connection);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyManual() async {
    if (_loading) return;
    try {
      final origin = parseWorkspaceOrigin(_origin.text).toString();
      setState(() {
        _loading = true;
        _error = null;
        _verified = null;
      });
      final result = await _verifyOrigin(origin);
      if (!await _confirm(result.connection)) return;
      if (result.ready) {
        await _connect(result.connection);
      } else {
        setState(() {
          _verified = result.connection;
          _workspaceName.text = result.connection.name;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connect(WorkspaceConnection value) async {
    await widget.onWorkspaceSelected(value);
    await _store.add(value);
    await _store.select(value);
    await _load();
  }

  Future<void> _claim() async {
    if (_loading || _verified == null || widget.onClaimOwner == null) return;
    final username = _username.text.trim();
    if (_setupToken.text.isEmpty ||
        _name.text.trim().isEmpty ||
        username.length < 3 ||
        username.length > 64 ||
        !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(username) ||
        _password.text.length < 12 ||
        _password.text.length > 128 ||
        _workspaceName.text.trim().isEmpty ||
        _workspaceName.text.length > 100) {
      setState(
        () => _error =
            'Periksa nama, username 3–64 karakter, password 12–128 karakter, dan semua kolom.',
      );
      return;
    }
    final token = _setupToken.text;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.onClaimOwner!(
        WorkspaceClaimRequest(
          workspace: _verified!,
          setupToken: token,
          name: _name.text.trim(),
          username: username,
          password: _password.text,
          workspaceName: _workspaceName.text.trim(),
        ),
      );
      _setupToken.clear();
      _password.clear();
      if (result.connection.origin != _verified!.origin ||
          result.connection.workspaceId != _verified!.workspaceId) {
        throw const FormatException(
          'Balasan klaim berasal dari workspace yang berbeda.',
        );
      }
      final confirmation = await _verifyOrigin(result.connection.origin);
      if (!confirmation.ready ||
          confirmation.connection.workspaceId !=
              result.connection.workspaceId ||
          confirmation.connection.name != _workspaceName.text.trim()) {
        throw const FormatException(
          'Akun dibuat, tetapi layanan belum dapat dikonfirmasi. Coba verifikasi ulang.',
        );
      }
      await _connect(confirmation.connection);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      _setupToken.clear();
      _password.clear();
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message(Object error) => error is FormatException
      ? error.message
      : 'Tidak dapat menghubungi layanan. Periksa koneksi lalu coba lagi.';

  Future<void> _scan() async {
    final result = await Navigator.of(context).push<WorkspaceConnection>(
      MaterialPageRoute(builder: (_) => const WorkspaceQrScannerPage()),
    );
    if (result != null && mounted) await _verifyQr(result);
  }

  Future<void> _openDeploy() async {
    final uri = _deployUri;
    if (uri.scheme != 'https' ||
        uri.host != 'deploy.workers.cloudflare.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.hasPort) {
      setState(
        () => _error =
            'Tautan Deploy Button tidak aman atau tidak valid. Hubungi pengelola aplikasi.',
      );
      return;
    }
    final confirm =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Deploy workspace baru'),
            content: const Text(
              'Anda memerlukan akun Cloudflare dan GitHub. Ikuti langkah deploy dan aktifkan resource yang diminta. Setelah selesai, kembali dan masukkan alamat Workers.dev untuk verifikasi.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Lanjutkan'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm) return;
    try {
      if (widget.onOpenDeployLink != null) {
        await widget.onOpenDeployLink!(uri);
      } else {
        await Clipboard.setData(ClipboardData(text: uri.toString()));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Tautan deployment disalin. Buka di browser untuk melanjutkan.',
              ),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Tautan deployment tidak dapat dibuka atau disalin.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pilih workspace')),
    body: PageBody(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            'Hubungkan usaha Anda',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sambungkan ke layanan absensi milik pemilik usaha.',
            style: TextStyle(color: AppColors.muted, height: 1.5),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            ErrorNotice(
              message: _error!,
              onRetry: () => setState(() => _error = null),
            ),
          ],
          if (_workspaces.isNotEmpty) ...[
            const SectionHeading('Workspace tersimpan'),
            for (final item in _workspaces)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.business_outlined),
                title: Text(item.name),
                subtitle: Text(item.origin),
                onTap: _loading
                    ? null
                    : () async {
                        if (await _confirm(item) && mounted) {
                          await _verifyQr(item);
                        }
                      },
                trailing: IconButton(
                  tooltip: 'Hapus ${item.name}',
                  onPressed: _loading
                      ? null
                      : () async {
                          await _store.remove(item.workspaceId);
                          await _load();
                        },
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
          ],
          const SectionHeading('Gabung workspace'),
          OutlinedButton.icon(
            onPressed: _loading ? null : _scan,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Pindai QR workspace'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _origin,
            enabled: !_loading,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Alamat Workers.dev',
              hintText: 'https://nama-layanan.workers.dev',
              prefixIcon: Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loading ? null : _verifyManual,
            child: Text(_loading ? 'Memverifikasi…' : 'Verifikasi layanan'),
          ),
          if (_oauthClientId.isNotEmpty) ...[
            const SectionHeading('Setup otomatis (beta)'),
            if (_autoError != null) ErrorNotice(message: _autoError!),
            ..._autoSteps.map(
              (step) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(step)),
                  ],
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: _autoRunning ? null : _startAutomaticSetup,
              icon: const Icon(Icons.cloud_done_outlined),
              label: Text(
                _autoRunning
                    ? 'Menyiapkan workspace…'
                    : 'Masuk & setup otomatis dengan Cloudflare',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Aplikasi login ke akun Cloudflare Anda lalu membuat Worker, database D1, bucket R2 privat, migrasi, secret setup, dan alamat workers.dev secara otomatis. Memerlukan registrasi OAuth client sekali oleh pengembang; aktivasi payment method R2 tetap dilakukan di dashboard bila diminta.',
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 16),
          ],
          const SectionHeading('Buat workspace baru'),
          const Text(
            'Token setup satu kali dibuat pada langkah deployment. Tampilkan digest SHA-256 lalu tempelkan ke secret OWNER_SETUP_TOKEN_SHA256 di pengaturan Worker. Jangan gunakan digest sebagai token klaim.',
            style: TextStyle(color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _setupToken,
            enabled: !_loading,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Token setup satu kali',
              prefixIcon: Icon(Icons.key_outlined),
            ),
          ),
          const SizedBox(height: 12),
          if (_digestVisible) ...[
            const Text(
              'Simpan digest berikut sebagai secret OWNER_SETUP_TOKEN_SHA256 pada Worker:',
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 8),
            SelectableText(
              _digest,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
          OutlinedButton(
            onPressed: _setupToken.text.isEmpty || _loading
                ? null
                : () => setState(() => _digestVisible = !_digestVisible),
            child: Text(
              _digestVisible
                  ? 'Sembunyikan digest token'
                  : 'Tampilkan digest token',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _loading ? null : _openDeploy,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Siapkan deployment Cloudflare'),
          ),
          if (_verified != null && widget.onClaimOwner == null)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: ErrorNotice(
                message:
                    'Pembuatan akun pemilik belum dihubungkan oleh pengelola aplikasi.',
              ),
            ),
          if (_verified != null && widget.onClaimOwner != null) ...[
            const SectionHeading('Buat akun pemilik'),
            const Text(
              'Layanan sudah terhubung. Token setup dikirim hanya melalui callback klaim dan tidak akan disimpan.',
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              enabled: !_loading,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nama pemilik',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _username,
              enabled: !_loading,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Username (3–64 karakter)',
                prefixIcon: Icon(Icons.alternate_email),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              enabled: !_loading,
              obscureText: true,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Password (12–128 karakter)',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _workspaceName,
              enabled: !_loading,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nama workspace',
                prefixIcon: Icon(Icons.business_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _origin,
              enabled: !_loading,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Alamat Workers.dev',
                hintText: 'https://nama-layanan.workers.dev',
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _loading ? null : _verifyManual,
              child: const Text('Verifikasi ulang layanan'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed:
                  _loading ||
                      _setupToken.text.isEmpty ||
                      widget.onClaimOwner == null
                  ? null
                  : _claim,
              child: Text(_loading ? 'Membuat akun…' : 'Klaim workspace'),
            ),
          ],
          const SizedBox(height: 16),
          TextButton(
            onPressed: _loading ? null : () => Navigator.of(context).maybePop(),
            child: const Text('Batal'),
          ),
        ],
      ),
    ),
  );
}
