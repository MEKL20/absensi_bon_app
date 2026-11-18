class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.username,
    required this.role,
    this.active = true,
  });
  final String id;
  final String name;
  final String username;
  final String role;
  final bool active;
  bool get isOwner => role == 'owner';

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    name: json['name'] as String,
    username: json['username'] as String,
    role: json['role'] as String,
    active: json['active'] == true || json['active'] == 1,
  );
}

class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.kind,
    required this.recordedAt,
    required this.photoPath,
  });
  final String id;
  final String employeeId;
  final String employeeName;
  final String kind;
  final DateTime recordedAt;
  final String photoPath;
  factory AttendanceRecord.fromJson(Map<String, dynamic> json) =>
      AttendanceRecord(
        id: json['id'] as String,
        employeeId: json['employeeId'] as String,
        employeeName: json['employeeName'] as String,
        kind: json['kind'] as String,
        recordedAt: DateTime.parse(json['recordedAt'] as String),
        photoPath: json['photoPath'] as String? ?? '',
      );
}

class BonRecord {
  const BonRecord({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.amount,
    required this.note,
    required this.status,
    required this.repaidAmount,
    required this.createdAt,
  });
  final String id;
  final String employeeId;
  final String employeeName;
  final int amount;
  final String note;
  final String status;
  final int repaidAmount;
  final DateTime createdAt;
  int get outstanding => status == 'disbursed' ? amount - repaidAmount : 0;
  factory BonRecord.fromJson(Map<String, dynamic> json) => BonRecord(
    id: json['id'] as String,
    employeeId: json['employeeId'] as String,
    employeeName: json['employeeName'] as String,
    amount: (json['amount'] as num).toInt(),
    note: json['note'] as String? ?? '',
    status: json['status'] as String,
    repaidAmount: (json['repaidAmount'] as num? ?? 0).toInt(),
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

class DashboardData {
  const DashboardData({
    required this.employeeCount,
    required this.checkedInCount,
    required this.pendingBonCount,
    required this.outstandingAmount,
    required this.attendance,
    required this.bon,
  });
  final int employeeCount;
  final int checkedInCount;
  final int pendingBonCount;
  final int outstandingAmount;
  final List<AttendanceRecord> attendance;
  final List<BonRecord> bon;
  factory DashboardData.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] as Map<String, dynamic>;
    return DashboardData(
      employeeCount: (summary['employeeCount'] as num).toInt(),
      checkedInCount: (summary['checkedInCount'] as num).toInt(),
      pendingBonCount: (summary['pendingBonCount'] as num).toInt(),
      outstandingAmount: (summary['outstandingAmount'] as num).toInt(),
      attendance: (json['attendance'] as List)
          .map((v) => AttendanceRecord.fromJson(v as Map<String, dynamic>))
          .toList(),
      bon: (json['bon'] as List)
          .map((v) => BonRecord.fromJson(v as Map<String, dynamic>))
          .toList(),
    );
  }
}
