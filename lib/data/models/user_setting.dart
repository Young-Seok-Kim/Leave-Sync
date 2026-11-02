import 'package:hive/hive.dart';

part 'user_setting.g.dart';

@HiveType(typeId: 0)
class UserSetting extends HiveObject {
  @HiveField(0)
  final double totalLeave;

  @HiveField(1)
  final DateTime resetDate;

  @HiveField(2)
  final bool isFirstRun;

  @HiveField(3)
  final DateTime? entryDate; // ★ 입사일 저장을 위한 필드 추가

  @HiveField(4)
  final DateTime? lastAutoUpdate; // ★ 중복 추가 방지를 위한 필드
  @HiveField(5)
  final int? schemaVersion;

  @HiveField(6)
  final List<String>? calendarIds; // 휴가를 읽어올 구글 캘린더 ID 목록 (null이면 primary)

  @HiveField(7)
  final String? accountEmail; // 이 설정이 묶여 있는 구글 계정 (백업/복원 기준)

  @HiveField(8)
  final bool? notificationsEnabled; // 연차 소멸 알림 사용 여부 (null 이면 사용)

  UserSetting({
    required this.totalLeave,
    required this.resetDate,
    this.isFirstRun = false,
    this.entryDate,
    this.lastAutoUpdate,
    this.schemaVersion = 1,
    this.calendarIds,
    this.accountEmail,
    this.notificationsEnabled,
  });

  /// 연차 소멸 알림 사용 여부 (기본값: 사용)
  bool get remindersOn => notificationsEnabled ?? true;

  /// 구글 드라이브 백업용 JSON
  Map<String, dynamic> toJson() => {
        'totalLeave': totalLeave,
        'resetDate': resetDate.toIso8601String(),
        'entryDate': entryDate?.toIso8601String(),
        'lastAutoUpdate': lastAutoUpdate?.toIso8601String(),
        'schemaVersion': schemaVersion,
        'calendarIds': calendarIds,
        'accountEmail': accountEmail,
        'notificationsEnabled': notificationsEnabled,
      };

  static UserSetting? fromJson(Map<String, dynamic> json) {
    final total = json['totalLeave'];
    final reset = json['resetDate'];
    if (total is! num || reset is! String) return null;
    DateTime? parse(dynamic v) => v is String ? DateTime.tryParse(v) : null;
    return UserSetting(
      totalLeave: total.toDouble(),
      resetDate: DateTime.parse(reset),
      isFirstRun: false,
      entryDate: parse(json['entryDate']),
      lastAutoUpdate: parse(json['lastAutoUpdate']),
      schemaVersion: json['schemaVersion'] is int ? json['schemaVersion'] as int : 1,
      calendarIds: (json['calendarIds'] as List?)?.cast<String>(),
      accountEmail: json['accountEmail'] as String?,
      notificationsEnabled: json['notificationsEnabled'] as bool?,
    );
  }

  /// 선택된 캘린더 목록. 비어 있으면 기본 캘린더(primary)만 사용
  List<String> get effectiveCalendarIds =>
      (calendarIds == null || calendarIds!.isEmpty) ? const ['primary'] : calendarIds!;

  // 복사 메서드 (Riverpod 상태 변경용)
  UserSetting copyWith({
    double? totalLeave,
    DateTime? resetDate,
    bool? isFirstRun,
    DateTime? entryDate,
    DateTime? lastAutoUpdate,
    int? schemaVersion,
    List<String>? calendarIds,
    String? accountEmail,
    bool? notificationsEnabled,
  }) {
    return UserSetting(
      totalLeave: totalLeave ?? this.totalLeave,
      resetDate: resetDate ?? this.resetDate,
      isFirstRun: isFirstRun ?? this.isFirstRun,
      entryDate: entryDate ?? this.entryDate,
      lastAutoUpdate: lastAutoUpdate ?? this.lastAutoUpdate,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      calendarIds: calendarIds ?? this.calendarIds,
      accountEmail: accountEmail ?? this.accountEmail,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    );
  }
}