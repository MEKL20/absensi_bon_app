import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'api_client.dart';
import 'models.dart';
import 'ui.dart';

class AbsensiPage extends StatefulWidget {
  const AbsensiPage({
    super.key,
    required this.api,
    required this.user,
    this.embedded = false,
  });

  final ApiClient api;
  final AppUser user;
  final bool embedded;

  @override
  State<AbsensiPage> createState() => _AbsensiPageState();
}

class _AbsensiPageState extends State<AbsensiPage> {
  final _picker = ImagePicker();
  List<AttendanceRecord> _records = [];
  File? _photo;
  String _kind = 'check_in';
  String _query = '';
  String? _requestId;
  String? _listError;
  String? _formError;
  AttendanceRecord? _receipt;
  bool _loading = true;
  int? _nextOffset;
  bool _submitting = false;
  bool _uncertain = false;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    _load();
    if (!widget.user.isOwner && Platform.isAndroid) _recoverCapture();
  }

  Future<void> _load({bool append = false}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _listError = null;
      });
    }
    try {
      final records = await widget.api.attendance(
        offset: append ? _nextOffset ?? 0 : 0,
      );
      _nextOffset = widget.api.attendanceNextOffset;
      if (!mounted) return;
      setState(() {
        _records =
            (append
                  ? [
                      ..._records,
                      ...records.where(
                        (item) => !_records.any((old) => old.id == item.id),
                      ),
                    ]
                  : records)
              ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
      });
    } catch (error) {
      if (mounted) setState(() => _listError = apiError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _recoverCapture() async {
    try {
      final result = await _picker.retrieveLostData();
      if (!mounted || result.isEmpty) return;
      final files = result.files;
      if (files != null && files.isNotEmpty) {
        setState(() {
          _photo = File(files.first.path);
          _requestId = null;
        });
      } else if (result.exception != null) {
        setState(
          () => _formError =
              'Foto belum dapat dipulihkan. Silakan ambil selfie kembali.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _formError =
              'Foto belum dapat dipulihkan. Silakan ambil selfie kembali.',
        );
      }
    }
  }

  Future<void> _capture() async {
    setState(() {
      _capturing = true;
      _formError = null;
    });
    try {
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 75,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (!mounted || image == null) return;
      setState(() {
        _photo = File(image.path);
        _requestId = null;
        _receipt = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _formError =
              'Kamera tidak dapat dibuka. Periksa izin kamera di pengaturan perangkat, lalu coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _submit() async {
    final photo = _photo;
    if (photo == null || _submitting || _capturing) return;
    final requestId = _requestId ??= newRequestId();
    setState(() {
      _submitting = true;
      _formError = null;
    });
    try {
      final receipt = await widget.api.submitAttendance(
        kind: _kind,
        photo: photo,
        requestId: requestId,
      );
      if (!mounted) return;
      setState(() {
        _receipt = receipt;
        _uncertain = false;
        _photo = null;
        _requestId = null;
        _records = [
          receipt,
          ..._records.where((item) => item.id != receipt.id),
        ];
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _formError = apiError(error);
          _uncertain = error is! ApiException || error.uncertain;
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _kindLabel(String kind) => kind == 'check_in' ? 'Masuk' : 'Pulang';

  Future<void> _viewPhoto(AttendanceRecord record) async {
    if (!widget.user.isOwner) return;
    final future = widget.api.attendancePhoto(record.id);
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  record.employeeName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  '${_kindLabel(record.kind)} · ${dateTimeLabel(record.recordedAt)}',
                ),
                const SizedBox(height: 16),
                FutureBuilder<Uint8List>(
                  future: future,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return ErrorNotice(message: apiError(snapshot.error!));
                    }
                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(
                          child: CircularProgressIndicator(
                            semanticsLabel: 'Memuat selfie',
                          ),
                        ),
                      );
                    }
                    return InteractiveViewer(
                      child: Image.memory(
                        snapshot.data!,
                        fit: BoxFit.contain,
                        semanticLabel: 'Selfie absensi ${record.employeeName}',
                        errorBuilder: (_, __, ___) =>
                            const Text('Foto tidak dapat ditampilkan.'),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Tutup'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _form() {
    final busy = _submitting || _capturing;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeading('Catat absensi'),
            Text(
              widget.user.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final kind in ['check_in', 'check_out'])
                  ChoiceChip(
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(_kindLabel(kind)),
                    ),
                    selected: _kind == kind,
                    onSelected: busy || _uncertain
                        ? null
                        : (_) {
                            if (_kind == kind) return;
                            setState(() {
                              _kind = kind;
                              _requestId = null;
                              _receipt = null;
                            });
                          },
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Selfie absensi',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Ambil foto wajah yang jelas. Foto digunakan sebagai bukti absensi dan dapat dilihat oleh pemilik.',
            ),
            const SizedBox(height: 12),
            if (_photo != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: ColoredBox(
                    color: AppColors.background,
                    child: Image.file(
                      _photo!,
                      fit: BoxFit.contain,
                      semanticLabel: 'Pratinjau selfie absensi',
                      errorBuilder: (_, __, ___) => const Center(
                        child: Text('Foto tidak tersedia. Ambil ulang selfie.'),
                      ),
                    ),
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.add_a_photo_outlined, size: 32),
                    SizedBox(height: 8),
                    Text('Selfie belum ditambahkan'),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: busy || _uncertain ? null : _capture,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(
                _capturing
                    ? 'Membuka kamera…'
                    : _photo == null
                    ? 'Ambil selfie'
                    : 'Ambil ulang selfie',
              ),
            ),
            if (_formError != null) ...[
              const SizedBox(height: 12),
              ErrorNotice(message: _formError!),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy || _photo == null ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(
                _submitting
                    ? 'Mengirim absensi…'
                    : 'Kirim absensi ${_kindLabel(_kind).toLowerCase()}',
              ),
            ),
            if (_receipt != null) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Absensi tercatat',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${_kindLabel(_receipt!.kind)} · ${dateTimeLabel(_receipt!.recordedAt)}',
                      ),
                      Text(
                        'ID: ${_receipt!.id}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final records = _records
        .where(
          (record) =>
              !widget.user.isOwner ||
              record.employeeName.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    final content = SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!widget.user.isOwner) _form(),
                    SectionHeading(
                      widget.user.isOwner
                          ? 'Absensi karyawan'
                          : 'Riwayat absensi',
                      trailing: IconButton(
                        tooltip: 'Muat ulang absensi',
                        onPressed: _loading ? null : _load,
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                    if (widget.user.isOwner) ...[
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Cari nama karyawan',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_nextOffset != null)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Pencarian berlaku pada riwayat yang sudah dimuat. Muat berikutnya untuk mencari riwayat lebih lama.',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ),
                    if (_loading)
                      const LinearProgressIndicator(
                        semanticsLabel: 'Memuat riwayat absensi',
                      ),
                    if (_listError != null) ...[
                      const SizedBox(height: 12),
                      ErrorNotice(message: _listError!, onRetry: _load),
                    ],
                    if (!_loading && _listError == null && records.isEmpty)
                      EmptyState(
                        icon: Icons.event_available_outlined,
                        title: _query.isEmpty
                            ? 'Belum ada absensi'
                            : 'Tidak ditemukan pada riwayat yang dimuat',
                        message: _query.isEmpty
                            ? (widget.user.isOwner
                                  ? 'Absensi karyawan akan muncul di sini setelah dikirim.'
                                  : 'Ambil selfie dan kirim absensi pertama Anda.')
                            : 'Coba nama lain atau hapus pencarian.',
                      ),
                    for (final record in records) ...[
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        leading: Icon(
                          record.kind == 'check_in'
                              ? Icons.login
                              : Icons.logout,
                          color: AppColors.primary,
                        ),
                        title: Text(
                          widget.user.isOwner
                              ? record.employeeName
                              : 'Absensi ${_kindLabel(record.kind).toLowerCase()}',
                        ),
                        subtitle: Text(
                          '${widget.user.isOwner ? '${_kindLabel(record.kind)} · ' : ''}${dateTimeLabel(record.recordedAt)}',
                        ),
                        trailing: widget.user.isOwner
                            ? IconButton(
                                tooltip: 'Lihat selfie ${record.employeeName}',
                                onPressed: record.photoPath.isEmpty
                                    ? null
                                    : () => _viewPhoto(record),
                                icon: const Icon(Icons.photo_outlined),
                              )
                            : null,
                      ),
                      const Divider(height: 1),
                    ],
                    if (_nextOffset != null)
                      TextButton(
                        onPressed: _loading ? null : () => _load(append: true),
                        child: const Text('Muat riwayat berikutnya'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return widget.embedded
        ? content
        : Scaffold(
            appBar: AppBar(title: const Text('Absensi')),
            body: content,
          );
  }
}
