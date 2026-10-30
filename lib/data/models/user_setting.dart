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

  UserSetting({
    required this.totalLeave,
    required this.resetDate,
    this.isFirstRun = false,
    this.entryDate,
    this.lastAutoUpdate,
    this.schemaVersion = 1,
    this.calendarIds,
  });

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
  }) {
    return UserSetting(
      totalLeave: totalLeave ?? this.totalLeave,
      resetDate: resetDate ?? this.resetDate,
      isFirstRun: isFirstRun ?? this.isFirstRun,
      entryDate: entryDate ?? this.entryDate,
      lastAutoUpdate: lastAutoUpdate ?? this.lastAutoUpdate,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      calendarIds: calendarIds ?? this.calendarIds,
    );
  }
}