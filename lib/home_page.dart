import 'package:flutter/material.dart';
import 'api_client.dart';
import 'absensi_page.dart';
import 'bon_page.dart';
import 'employees_page.dart';
import 'login_page.dart';
import 'models.dart';
import 'ui.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.api, required this.user});
  final ApiClient api;
  final AppUser user;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selected = 0;
  final Map<int, Widget> _pages = {};
  String? _logoutError;
  bool _loggingOut = false;
  bool _recovering = false;
  String? _recoveryError;
  final GlobalKey<_DashboardState> _dashboardKey = GlobalKey<_DashboardState>();

  void _select(int index) {
    setState(() => _selected = index);
    if (index == 0) _dashboardKey.currentState?._load();
  }

  Future<void> _recover() async {
    setState(() {
      _recovering = true;
      _recoveryError = null;
    });
    try {
      final message = await widget.api.recoverPending();
      if (!mounted) return;
      setState(() {
        _pages.clear();
        _selected = 0;
      });
      _dashboardKey.currentState?._load();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (mounted) setState(() => _recoveryError = apiError(error));
    } finally {
      if (mounted) setState(() => _recovering = false);
    }
  }

  Future<void> _logout() async {
    setState(() {
      _loggingOut = true;
      _logoutError = null;
    });
    try {
      await widget.api.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => LoginPage(api: widget.api)),
        (_) => false,
      );
    } catch (error) {
      if (mounted) setState(() => _logoutError = apiError(error));
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = widget.user.isOwner;
    final labels = owner
        ? ['Ringkasan', 'Karyawan', 'Absensi', 'Bon']
        : ['Beranda', 'Absensi', 'Bon', 'Akun'];
    final icons = owner
        ? [
            Icons.space_dashboard_outlined,
            Icons.people_outline,
            Icons.fact_check_outlined,
            Icons.account_balance_wallet_outlined,
          ]
        : [
            Icons.home_outlined,
            Icons.fact_check_outlined,
            Icons.account_balance_wallet_outlined,
            Icons.person_outline,
          ];
    Widget body;
    if (_selected == 0) {
      body = _Dashboard(
        key: _dashboardKey,
        api: widget.api,
        user: widget.user,
        onAttendance: () => _select(owner ? 2 : 1),
        onBon: () => _select(owner ? 3 : 2),
      );
    } else if (owner && _selected == 1) {
      body = EmployeesPage(api: widget.api);
    } else if (_selected == (owner ? 2 : 1)) {
      body = AbsensiPage(api: widget.api, user: widget.user, embedded: true);
    } else if (_selected == (owner ? 3 : 2)) {
      body = BonPage(api: widget.api, user: widget.user, embedded: true);
    } else {
      body = PageBody(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 16),
            Text(
              widget.user.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '@${widget.user.username}',
              style: const TextStyle(color: AppColors.muted),
            ),
            const SectionHeading('Akun karyawan'),
            const Text(
              'Anda dapat melihat absensi dan bon milik Anda. Untuk perubahan akun atau password, hubungi pemilik usaha.',
            ),
            const SizedBox(height: 24),
            if (_logoutError != null) ErrorNotice(message: _logoutError!),
            OutlinedButton.icon(
              onPressed: _loggingOut ? null : _logout,
              icon: const Icon(Icons.logout),
              label: Text(_loggingOut ? 'Keluar…' : 'Keluar dari akun'),
            ),
          ],
        ),
      );
    }
    if (!owner && _selected == 3) {
      _pages[3] = body;
    } else {
      _pages.putIfAbsent(_selected, () => body);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(labels[_selected]),
        actions: [
          if (owner)
            IconButton(
              tooltip: 'Keluar dari akun',
              onPressed: _loggingOut ? null : _logout,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: Column(
        children: [
          if (widget.api.hasPendingRequest)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: ErrorNotice(
                message:
                    _recoveryError ??
                    'Ada pengiriman yang belum terkonfirmasi. Periksa hasil sebelum membuat pengiriman baru.',
                onRetry: _recovering ? null : _recover,
              ),
            ),
          if (owner && _logoutError != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: ErrorNotice(message: _logoutError!),
            ),
          Expanded(
            child: IndexedStack(
              index: _selected,
              children: List.generate(
                labels.length,
                (index) => _pages[index] ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selected,
        onDestinationSelected: _select,
        destinations: List.generate(
          labels.length,
          (index) => NavigationDestination(
            icon: Icon(icons[index]),
            label: labels[index],
          ),
        ),
      ),
    );
  }
}

class _Dashboard extends StatefulWidget {
  const _Dashboard({
    super.key,
    required this.api,
    required this.user,
    required this.onAttendance,
    required this.onBon,
  });
  final ApiClient api;
  final AppUser user;
  final VoidCallback onAttendance;
  final VoidCallback onBon;
  @override
  State<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<_Dashboard> {
  DashboardData? _data;
  String? _error;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.dashboard();
      if (mounted) setState(() => _data = data);
    } catch (error) {
      if (mounted) setState(() => _error = apiError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final owner = widget.user.isOwner;
    return PageBody(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Halo, ${widget.user.name}',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              owner
                  ? 'Pantau kehadiran dan tindak lanjuti bon karyawan.'
                  : 'Catat kehadiran, lalu lanjutkan aktivitas Anda.',
              style: const TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 24),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null) ErrorNotice(message: _error!, onRetry: _load),
            if (data != null) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      owner ? 'Sedang bekerja' : 'Status kehadiran Anda',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      owner
                          ? '${data.checkedInCount} dari ${data.employeeCount} karyawan belum mencatat pulang'
                          : (data.checkedInCount > 0
                                ? 'Sudah masuk, belum mencatat pulang'
                                : 'Tidak ada sesi kerja terbuka'),
                      style: const TextStyle(
                        color: Color(0xFFD8E8E2),
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: widget.onAttendance,
                      icon: Icon(
                        owner ? Icons.arrow_forward : Icons.camera_alt_outlined,
                      ),
                      label: Text(owner ? 'Lihat absensi' : 'Buka absensi'),
                    ),
                  ],
                ),
              ),
              const SectionHeading('Bon'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Menunggu keputusan'),
                subtitle: Text('${data.pendingBonCount} pengajuan'),
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.onBon,
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  owner ? 'Total sisa utang karyawan' : 'Total sisa utang',
                ),
                subtitle: Text(
                  money(data.outstandingAmount),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.onBon,
              ),
              const SectionHeading('Absensi terbaru'),
              if (data.attendance.isEmpty)
                const EmptyState(
                  icon: Icons.fact_check_outlined,
                  title: 'Belum ada absensi',
                  message: 'Absensi yang sudah tersimpan akan muncul di sini.',
                ),
              ...data.attendance
                  .take(5)
                  .map(
                    (record) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        owner ? record.employeeName : statusLabel(record.kind),
                      ),
                      subtitle: Text(dateTimeLabel(record.recordedAt)),
                      trailing: StatusBadge(record.kind),
                      onTap: widget.onAttendance,
                    ),
                  ),
              const SectionHeading('Pengajuan terbaru'),
              if (data.bon.isEmpty)
                const EmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Belum ada pengajuan',
                  message: 'Pengajuan bon akan tampil setelah dikirim.',
                ),
              ...data.bon
                  .take(5)
                  .map(
                    (record) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(money(record.amount)),
                      subtitle: Text(
                        owner
                            ? record.employeeName
                            : dateTimeLabel(record.createdAt),
                      ),
                      trailing: StatusBadge(record.status),
                      onTap: widget.onBon,
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}
