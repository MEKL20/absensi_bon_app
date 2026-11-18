import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';
import 'models.dart';
import 'ui.dart';

class BonPage extends StatefulWidget {
  const BonPage({
    super.key,
    required this.api,
    required this.user,
    this.embedded = false,
  });

  final ApiClient api;
  final AppUser user;
  final bool embedded;

  @override
  State<BonPage> createState() => _BonPageState();
}

class _BonPageState extends State<BonPage> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final Map<String, String> _actionRequests = {};
  List<BonRecord> _records = [];
  String? _requestId;
  String _draftAmount = '';
  String _draftNote = '';
  String? _formError;
  String? _listError;
  String? _actionError;
  BonRecord? _receipt;
  String? _busyRecord;
  BonRecord? _uncertainActionRecord;
  String? _uncertainAction;
  int? _uncertainActionAmount;
  String _query = '';
  String _status = 'all';
  bool _loading = true;
  int? _nextOffset;
  bool _submitting = false;
  bool _uncertain = false;

  @override
  void initState() {
    super.initState();
    _amount.addListener(_draftChanged);
    _note.addListener(_draftChanged);
    _load();
  }

  void _draftChanged() {
    if (_draftAmount == _amount.text && _draftNote == _note.text) return;
    _draftAmount = _amount.text;
    _draftNote = _note.text;
    _requestId = null;
    if (mounted) {
      setState(() {
        _formError = null;
        _receipt = null;
      });
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _listError = null;
      });
    }
    try {
      final records = await widget.api.bon(
        offset: append ? _nextOffset ?? 0 : 0,
      );
      _nextOffset = widget.api.bonNextOffset;
      if (mounted) {
        setState(
          () => _records =
              (append
                    ? [
                        ..._records,
                        ...records.where(
                          (item) => !_records.any((old) => old.id == item.id),
                        ),
                      ]
                    : records)
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _listError = apiError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    final amount = int.parse(_amount.text);
    final note = _note.text.trim();
    final requestId = _requestId ??= newRequestId();
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _formError = null;
    });
    try {
      final receipt = await widget.api.submitBon(
        amount: amount,
        note: note,
        requestId: requestId,
      );
      if (!mounted) return;
      _amount.clear();
      _note.clear();
      setState(() {
        _requestId = null;
        _receipt = receipt;
        _uncertain = false;
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

  String _actionLabel(String action) {
    switch (action) {
      case 'approve':
        return 'Setujui';
      case 'reject':
        return 'Tolak';
      case 'disburse':
        return 'Catat pencairan';
      default:
        return 'Catat pembayaran';
    }
  }

  Future<void> _confirmAction(BonRecord record, String action) async {
    if (_busyRecord != null ||
        !widget.user.isOwner ||
        _uncertainActionRecord != null) {
      return;
    }
    var amountText = '';
    final formKey = GlobalKey<FormState>();
    final repayment = action == 'repay';
    final amount = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_actionLabel(action)),
        scrollable: true,
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.employeeName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text('Jumlah bon: ${money(record.amount)}'),
              const SizedBox(height: 12),
              if (repayment) ...[
                Text('Sisa utang: ${money(record.outstanding)}'),
                const SizedBox(height: 16),
                TextFormField(
                  onChanged: (value) => amountText = value,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Jumlah pembayaran',
                    prefixText: 'Rp ',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) {
                    final parsed = int.tryParse(value ?? '');
                    if (parsed == null || parsed <= 0) {
                      return 'Masukkan jumlah lebih dari nol.';
                    }
                    if (parsed > record.outstanding) {
                      return 'Jumlah melebihi sisa utang.';
                    }
                    return null;
                  },
                ),
              ] else
                Text(
                  action == 'disburse'
                      ? 'Pastikan dana sudah diberikan. Tindakan ini mencatat pencairan dan menambah utang karyawan.'
                      : action == 'reject'
                      ? 'Pengajuan akan ditolak dan tidak menambah utang karyawan.'
                      : 'Pengajuan akan disetujui. Utang baru dihitung setelah pencairan dicatat.',
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (repayment && !formKey.currentState!.validate()) return;
              Navigator.pop(
                dialogContext,
                repayment ? int.parse(amountText) : 0,
              );
            },
            child: Text(_actionLabel(action)),
          ),
        ],
      ),
    );
    if (!mounted || amount == null) return;
    await _performAction(record, action, repayment ? amount : null);
  }

  Future<void> _performAction(
    BonRecord record,
    String action,
    int? amount,
  ) async {
    final key = '${record.id}:$action:${amount ?? 0}';
    final requestId = _actionRequests.putIfAbsent(key, newRequestId);
    setState(() {
      _busyRecord = record.id;
      _actionError = null;
    });
    try {
      final updated = await widget.api.bonAction(
        record.id,
        action,
        amount: amount,
        requestId: requestId,
      );
      if (!mounted) return;
      setState(() {
        _records = _records
            .map((item) => item.id == updated.id ? updated : item)
            .toList();
        _actionRequests.remove(key);
        _uncertainActionRecord = null;
        _uncertainAction = null;
        _uncertainActionAmount = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_actionLabel(action)} berhasil.')),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _actionError = apiError(error);
          final uncertain = error is! ApiException || error.uncertain;
          _uncertainActionRecord = uncertain ? record : null;
          _uncertainAction = uncertain ? action : null;
          _uncertainActionAmount = uncertain ? amount : null;
        });
      }
    } finally {
      if (mounted) setState(() => _busyRecord = null);
    }
  }

  Widget _form() => Align(
    alignment: Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeading('Ajukan bon'),
            const Text(
              'Isi jumlah dan keterangan bila diperlukan. Pemilik akan meninjau pengajuan Anda.',
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _amount,
              enabled: !_submitting && !_uncertain,
              decoration: const InputDecoration(
                labelText: 'Jumlah bon',
                prefixText: 'Rp ',
                helperText: 'Masukkan jumlah dalam rupiah tanpa desimal.',
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (value) {
                final amount = int.tryParse(value ?? '');
                if (amount == null || amount <= 0) {
                  return 'Masukkan jumlah lebih dari nol.';
                }
                if (amount > 1000000000) {
                  return 'Jumlah maksimal Rp 1.000.000.000.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _note,
              enabled: !_submitting && !_uncertain,
              decoration: const InputDecoration(
                labelText: 'Keterangan (opsional)',
                alignLabelWithHint: true,
              ),
              minLines: 2,
              maxLines: 5,
              maxLength: 500,
              validator: (value) => (value ?? '').length > 500
                  ? 'Keterangan maksimal 500 karakter.'
                  : null,
            ),
            if (_formError != null) ...[
              const SizedBox(height: 12),
              ErrorNotice(message: _formError!),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(
                _submitting
                    ? 'Mengirim pengajuan…'
                    : _uncertain
                    ? 'Periksa pengiriman'
                    : 'Kirim pengajuan',
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
                        'Pengajuan bon tercatat',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(money(_receipt!.amount)),
                      Text(dateTimeLabel(_receipt!.createdAt)),
                      Text(
                        'ID: ${_receipt!.id}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      StatusBadge(_receipt!.status),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    ),
  );

  Widget _record(BonRecord record) {
    final busy = _busyRecord != null || _uncertainActionRecord != null;
    final actions = <String>[
      if (record.status == 'pending') ...['approve', 'reject'],
      if (record.status == 'approved') 'disburse',
      if (record.status == 'disbursed' && record.outstanding > 0) 'repay',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                money(record.amount),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              StatusBadge(record.status),
            ],
          ),
          const SizedBox(height: 8),
          if (widget.user.isOwner)
            Text(
              record.employeeName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          Text(
            dateTimeLabel(record.createdAt),
            style: TextStyle(color: AppColors.muted),
          ),
          if (record.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(record.note),
          ],
          if (record.status == 'disbursed' || record.status == 'repaid') ...[
            const SizedBox(height: 10),
            Text(
              'Terbayar ${money(record.repaidAmount)} · Sisa ${money(record.outstanding)}',
            ),
          ],
          if (widget.user.isOwner && actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final action in actions)
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => _confirmAction(record, action),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    child: Text(_actionLabel(action)),
                  ),
              ],
            ),
          ],
          if (_busyRecord == record.id) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(
              semanticsLabel: 'Menyimpan perubahan bon',
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final records = _records
        .where(
          (record) =>
              (_status == 'all' || record.status == _status) &&
              record.employeeName.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    final outstanding = _records.fold<int>(
      0,
      (sum, item) => sum + item.outstanding,
    );
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
                      widget.user.isOwner ? 'Bon karyawan' : 'Riwayat bon',
                      trailing: IconButton(
                        tooltip: 'Muat ulang bon',
                        onPressed: _loading ? null : _load,
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                    if (!_loading && _listError == null) ...[
                      Text(
                        '${widget.user.isOwner ? 'Total sisa utang karyawan' : 'Total sisa utang'} ${money(outstanding)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Dihitung dari bon yang sudah dicairkan dalam riwayat yang ditampilkan, setelah pembayaran.',
                      ),
                      const SizedBox(height: 20),
                    ],
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
                          'Filter berlaku pada riwayat yang sudah dimuat. Muat berikutnya untuk mencari riwayat lebih lama.',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ),
                    DropdownButtonFormField<String>(
                      value: _status,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Status bon',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('Semua status'),
                        ),
                        for (final status in [
                          'pending',
                          'approved',
                          'rejected',
                          'disbursed',
                          'repaid',
                        ])
                          DropdownMenuItem(
                            value: status,
                            child: Text(statusLabel(status)),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _status = value ?? 'all'),
                    ),
                    const SizedBox(height: 16),
                    if (_loading)
                      const LinearProgressIndicator(
                        semanticsLabel: 'Memuat riwayat bon',
                      ),
                    if (_listError != null)
                      ErrorNotice(message: _listError!, onRetry: _load),
                    if (_actionError != null) ...[
                      const SizedBox(height: 12),
                      ErrorNotice(
                        message: _actionError!,
                        onRetry:
                            _uncertainActionRecord == null ||
                                _busyRecord != null
                            ? null
                            : () => _performAction(
                                _uncertainActionRecord!,
                                _uncertainAction!,
                                _uncertainActionAmount,
                              ),
                      ),
                    ],
                    if (!_loading && _listError == null && records.isEmpty)
                      EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: _status == 'all' && _query.isEmpty
                            ? 'Belum ada bon'
                            : 'Tidak ada hasil pada riwayat yang dimuat',
                        message: _status == 'all' && _query.isEmpty
                            ? (widget.user.isOwner
                                  ? 'Pengajuan karyawan akan muncul di sini.'
                                  : 'Pengajuan bon Anda akan muncul di sini setelah dikirim.')
                            : 'Pilih semua status atau ubah pencarian.',
                      ),
                    for (final record in records) ...[
                      _record(record),
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
            appBar: AppBar(title: const Text('Bon')),
            body: content,
          );
  }
}
