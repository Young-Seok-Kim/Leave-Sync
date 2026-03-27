import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/user_setting.dart';
import '../services/google_calendar_service.dart';

final calendarServiceProvider = Provider((ref) => GoogleCalendarService());

final leaveStateProvider = StateNotifierProvider<LeaveNotifier, UserSetting?>((ref) {
  return LeaveNotifier();
});

class LeaveNotifier extends StateNotifier<UserSetting?> {
  LeaveNotifier() : super(null) {
    _init();
  }

  void _init() {
    final box = Hive.box<UserSetting>('settings');
    if (box.isNotEmpty) {
      state = box.getAt(0);
    }
  }

  Future<void> saveSettings(double total, DateTime reset) async {
    final box = Hive.box<UserSetting>('settings');
    final setting = UserSetting(totalLeave: total, resetDate: reset, isFirstRun: false);
    await box.put(0, setting);
    state = setting;
  }
}