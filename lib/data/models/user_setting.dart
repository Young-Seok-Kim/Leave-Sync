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

  UserSetting({
    required this.totalLeave,
    required this.resetDate,
    this.isFirstRun = false,
    this.entryDate,
  });
}