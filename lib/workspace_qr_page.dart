import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'ui.dart';
import 'workspace_store.dart';

class WorkspaceQrPage extends StatelessWidget {
  const WorkspaceQrPage({super.key, required this.workspace});
  final WorkspaceConnection workspace;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Bagikan workspace')),
    body: PageBody(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Hubungkan perangkat lain',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Kode ini berisi alamat layanan dan identitas workspace saja. Token Cloudflare tidak disertakan.',
            style: TextStyle(color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 28),
          Center(
            child: Semantics(
              label: 'Kode QR workspace ${workspace.name}',
              child: QrImageView(
                data: workspace.toQr(),
                size: 240,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            workspace.name,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          SelectableText(
            workspace.origin,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}

class WorkspaceQrScannerPage extends StatefulWidget {
  const WorkspaceQrScannerPage({super.key});
  @override
  State<WorkspaceQrScannerPage> createState() => _WorkspaceQrScannerPageState();
}

class _WorkspaceQrScannerPageState extends State<WorkspaceQrScannerPage> {
  bool _processing = false;
  String? _error;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final raw = capture.barcodes.isEmpty
        ? null
        : capture.barcodes.first.rawValue;
    if (raw == null) return;
    _processing = true;
    try {
      final workspace = WorkspaceConnection.fromQr(raw);
      if (mounted) Navigator.of(context).pop(workspace);
    } on FormatException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _processing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pindai QR workspace')),
    body: PageBody(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Arahkan kamera ke QR workspace yang dibagikan pemilik usaha.',
            style: TextStyle(color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 1,
              child: MobileScanner(
                onDetect: _onDetect,
                errorBuilder: (context, error) => Center(
                  child: Text(
                    error.errorCode == MobileScannerErrorCode.permissionDenied
                        ? 'Izin kamera ditolak. Aktifkan izin kamera untuk memindai QR.'
                        : 'Kamera tidak tersedia. Masukkan alamat workspace secara manual.',
                  ),
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            ErrorNotice(
              message: _error!,
              onRetry: () => setState(() => _error = null),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Batal'),
          ),
        ],
      ),
    ),
  );
}
