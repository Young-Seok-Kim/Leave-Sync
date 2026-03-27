import 'package:hive/hive.dart';

part 'user_setting.g.dart'; // 터미널에서 build_runner 실행 필요

@HiveType(typeId: 0)
class UserSetting extends HiveObject {
  @HiveField(0)
  double totalLeave; // 총 연차

  @HiveField(1)
  DateTime resetDate; // 초기화 날짜

  @HiveField(2)
  bool isFirstRun; // 첫 실행 여부

  UserSetting({
    required this.totalLeave,
    required this.resetDate,
    this.isFirstRun = true,
  });
}