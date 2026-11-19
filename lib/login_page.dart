import 'package:flutter/material.dart';
import 'api_client.dart';
import 'home_page.dart';
import 'models.dart';
import 'ui.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.api,
    this.signedInUser,
    this.onChangeWorkspace,
  });
  final ApiClient api;
  final AppUser? signedInUser;
  final Future<void> Function()? onChangeWorkspace;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = widget.signedInUser;
    if (user != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => HomePage(api: widget.api, user: user),
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await widget.api.login(_username.text, _password.text);
      if (!mounted) return;
      _password.clear();
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => HomePage(api: widget.api, user: user),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = apiError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBody(
      child: AutofillGroup(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.badge_outlined,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Absensi & Bon',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Satu tempat untuk kehadiran dan bon karyawan.',
              style: TextStyle(
                fontSize: 17,
                height: 1.5,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 36),
            Text(
              'Masuk ke akun Anda',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Gunakan akun yang diberikan pemilik usaha.',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 24),
            if (!widget.api.hasVerifiedWorkspace)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: ErrorNotice(
                  message:
                      'Layanan belum dikonfigurasi. Hubungi pengelola aplikasi.',
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ErrorNotice(message: _error!),
              ),
            Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _username,
                    enabled: !_loading,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Isi username Anda.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    enabled: !_loading,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    enableSuggestions: false,
                    onFieldSubmitted: (_) => _login(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _obscure
                            ? 'Tampilkan password'
                            : 'Sembunyikan password',
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Isi password Anda.'
                        : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading || !widget.api.hasVerifiedWorkspace
                        ? null
                        : _login,
                    child: _loading
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text('Memeriksa akun…'),
                            ],
                          )
                        : const Text('Masuk'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Lupa password? Hubungi pemilik usaha untuk mengatur ulang akun.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
            if (widget.onChangeWorkspace != null)
              TextButton(
                onPressed: widget.onChangeWorkspace,
                child: const Text('Ganti atau hubungkan workspace'),
              ),
          ],
        ),
      ),
    ),
  );
}
