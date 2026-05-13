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

  UserSetting({
    required this.totalLeave,
    required this.resetDate,
    this.isFirstRun = false,
    this.entryDate,
    this.lastAutoUpdate,
    this.schemaVersion = 1,
  });

  // 복사 메서드 (Riverpod 상태 변경용)
  UserSetting copyWith({
    double? totalLeave,
    DateTime? resetDate,
    bool? isFirstRun,
    DateTime? entryDate,
    DateTime? lastAutoUpdate,
    int? schemaVersion,
  }) {
    return UserSetting(
      totalLeave: totalLeave ?? this.totalLeave,
      resetDate: resetDate ?? this.resetDate,
      isFirstRun: isFirstRun ?? this.isFirstRun,
      entryDate: entryDate ?? this.entryDate,
      lastAutoUpdate: lastAutoUpdate ?? this.lastAutoUpdate,
      schemaVersion: schemaVersion ?? this.schemaVersion,
    );
  }
}