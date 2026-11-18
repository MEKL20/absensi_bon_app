import 'package:flutter/material.dart';
import 'api_client.dart';
import 'models.dart';
import 'ui.dart';

class EmployeesPage extends StatefulWidget {
  const EmployeesPage({super.key, required this.api});
  final ApiClient api;
  @override
  State<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends State<EmployeesPage> {
  List<AppUser> _employees = [];
  bool _loading = true;
  int? _nextOffset;
  String? _error;
  String _query = '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool append = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.employees(
        offset: append ? _nextOffset ?? 0 : 0,
      );
      _nextOffset = widget.api.employeesNextOffset;
      if (mounted) {
        setState(
          () => _employees = append
              ? [
                  ..._employees,
                  ...result.where(
                    (item) => !_employees.any((old) => old.id == item.id),
                  ),
                ]
              : result,
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = apiError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([AppUser? employee]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _EmployeeForm(api: widget.api, employee: employee),
      ),
    );
    if (saved == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _employees
        .where((e) => '${e.name} ${e.username}'.toLowerCase().contains(_query))
        .toList();
    return PageBody(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Kelola tim Anda',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Buat akun dan atur akses karyawan. Riwayat tetap tersimpan saat akun dinonaktifkan.',
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Tambah karyawan'),
            ),
            const SizedBox(height: 20),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Cari nama atau username',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.toLowerCase().trim()),
            ),
            const SizedBox(height: 12),
            if (_nextOffset != null)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Pencarian berlaku pada karyawan yang sudah dimuat. Muat berikutnya untuk mencari anggota tim lainnya.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null) ErrorNotice(message: _error!, onRetry: _load),
            if (!_loading && _error == null && visible.isEmpty)
              EmptyState(
                icon: Icons.people_outline,
                title: _query.isEmpty
                    ? 'Tim Anda dimulai di sini'
                    : 'Tidak ditemukan pada daftar yang dimuat',
                message: _query.isEmpty
                    ? 'Tambahkan karyawan untuk mulai mencatat absensi dan bon.'
                    : 'Coba kata pencarian lain.',
              ),
            ...visible.map(
              (employee) => Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFE5EFEA),
                      foregroundColor: AppColors.primary,
                      child: Text(
                        employee.name.isEmpty
                            ? '?'
                            : employee.name.characters.first.toUpperCase(),
                      ),
                    ),
                    title: Text(employee.name),
                    subtitle: Text('@${employee.username}'),
                    trailing: StatusBadge(
                      employee.active ? 'active' : 'inactive',
                    ),
                    onTap: () => _edit(employee),
                  ),
                  const Divider(height: 1),
                ],
              ),
            ),
            if (_nextOffset != null)
              TextButton(
                onPressed: _loading ? null : () => _load(append: true),
                child: const Text('Muat karyawan berikutnya'),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmployeeForm extends StatefulWidget {
  const _EmployeeForm({required this.api, this.employee});
  final ApiClient api;
  final AppUser? employee;
  @override
  State<_EmployeeForm> createState() => _EmployeeFormState();
}

class _EmployeeFormState extends State<_EmployeeForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.employee?.name ?? '');
  late final _username = TextEditingController(
    text: widget.employee?.username ?? '',
  );
  final _password = TextEditingController();
  late bool _active = widget.employee?.active ?? true;
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.saveEmployee(
        id: widget.employee?.id,
        name: _name.text,
        username: _username.text,
        password: _password.text,
        active: widget.employee == null || widget.employee!.active == _active
            ? null
            : _active,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = apiError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.employee == null ? 'Tambah karyawan' : 'Detail karyawan',
      ),
    ),
    body: PageBody(
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ErrorNotice(message: _error!),
              ),
            TextFormField(
              controller: _name,
              enabled: !_saving,
              maxLength: 100,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Nama lengkap'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Isi nama karyawan.'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _username,
              enabled: !_saving && widget.employee == null,
              maxLength: 64,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Username'),
              validator: (value) =>
                  value == null ||
                      !RegExp(r'^[a-zA-Z0-9._-]{3,64}$').hasMatch(value.trim())
                  ? 'Gunakan 3–64 huruf, angka, titik, _ atau -.'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              enabled: !_saving,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: 128,
              decoration: InputDecoration(
                labelText: widget.employee == null
                    ? 'Password awal'
                    : 'Password baru (opsional)',
              ),
              validator: (value) {
                if (widget.employee != null &&
                    (value == null || value.isEmpty)) {
                  return null;
                }
                return value == null || value.length < 12
                    ? 'Gunakan sedikitnya 12 karakter.'
                    : null;
              },
            ),
            const SizedBox(height: 8),
            const Text(
              'Bagikan password melalui saluran pribadi. Penggantian password akan mengakhiri sesi karyawan.',
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
            if (widget.employee != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Akun aktif'),
                  subtitle: const Text(
                    'Nonaktifkan untuk menghentikan akses tanpa menghapus riwayat.',
                  ),
                  value: _active,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _active = value),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Menyimpan…' : 'Simpan karyawan'),
            ),
          ],
        ),
      ),
    ),
  );
}
