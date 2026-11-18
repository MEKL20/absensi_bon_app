import 'package:flutter/material.dart';
import 'api_client.dart';

class AppColors {
  static const ink = Color(0xFF152C31);
  static const muted = Color(0xFF51636A);
  static const primary = Color(0xFF17634C);
  static const background = Color(0xFFF5F8F7);
  static const border = Color(0xFFD7E1DC);
}

String money(int value) {
  final digits = value.abs().toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}.',
  );
  return '${value < 0 ? '-' : ''}Rp $digits';
}

String dateTimeLabel(DateTime value) {
  final local = value.toLocal();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  return '${local.day} ${months[local.month - 1]} ${local.year}, ${local.hour.toString().padLeft(2, '0')}.${local.minute.toString().padLeft(2, '0')}';
}

String statusLabel(String status) =>
    {
      'pending': 'Diajukan',
      'approved': 'Disetujui',
      'rejected': 'Ditolak',
      'disbursed': 'Dicairkan',
      'repaid': 'Lunas',
      'check_in': 'Masuk',
      'check_out': 'Pulang',
      'active': 'Aktif',
      'inactive': 'Nonaktif',
    }[status] ??
    status;

String apiError(Object error) {
  if (error is! ApiException) {
    return 'Ada kendala saat memproses data. Coba lagi.';
  }
  return {
        'unauthorized': 'Sesi berakhir. Keluar dari akun, lalu masuk kembali.',
        'invalid_credentials': 'Username atau password tidak sesuai.',
        'login_limited': 'Terlalu banyak percobaan masuk. Coba lagi nanti.',
        'forbidden': 'Akun Anda tidak memiliki akses untuk tindakan ini.',
        'state_conflict':
            'Status data sudah berubah. Muat ulang riwayat sebelum melanjutkan.',
        'username_taken': 'Username sudah digunakan. Pilih username lain.',
        'invalid_photo':
            'Foto tidak dapat diproses. Ambil ulang foto dengan ukuran maksimal 2 MB.',
        'not_found': 'Data tidak ditemukan atau tidak lagi tersedia.',
        'internal_error':
            'Layanan belum dapat memproses permintaan. Coba lagi dengan data yang sama.',
        'idempotency_conflict':
            'Data berbeda dari pengiriman sebelumnya. Muat ulang dan periksa riwayat.',
      }[error.code] ??
      error.message;
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final warning = status == 'pending';
    final negative = status == 'rejected' || status == 'inactive';
    final color = negative
        ? const Color(0xFFA12D30)
        : warning
        ? const Color(0xFF81580A)
        : AppColors.primary;
    return Semantics(
      label: 'Status ${statusLabel(status)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          statusLabel(status),
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class ErrorNotice extends StatelessWidget {
  const ErrorNotice({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0EF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: const TextStyle(color: Color(0xFF8C292D))),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
        ],
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
    child: Column(
      children: [
        Icon(icon, size: 36, color: AppColors.muted),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted),
        ),
      ],
    ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: child,
      ),
    ),
  );
}
