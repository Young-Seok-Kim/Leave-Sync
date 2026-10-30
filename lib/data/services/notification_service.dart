import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 연차 초기화일이 다가오는데 잔여 연차가 남아 있으면 알려주는 로컬 알림
class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channelId = 'leave_reset_reminder';
  static const _channelName = '연차 소멸 알림';
  static const _channelDesc = '연차 초기화일이 다가오면 남은 연차를 알려줍니다';

  /// 초기화일 기준 며칠 전에 알릴지 (알림 ID는 일수를 그대로 사용)
  static const List<int> _reminderDaysBefore = [30, 7, 1];

  Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    try {
      // 한국 사용자 대상 앱이라 Asia/Seoul 기준. 다른 지역이면 기기 오프셋과 맞는 곳을 찾음
      final offset = DateTime.now().timeZoneOffset;
      final seoul = tz.getLocation('Asia/Seoul');
      if (tz.TZDateTime.now(seoul).timeZoneOffset == offset) {
        tz.setLocalLocation(seoul);
      } else {
        tz.setLocalLocation(_findLocationByOffset(offset) ?? tz.UTC);
      }
    } catch (e) {
      debugPrint("⚠️ 타임존 설정 실패: $e");
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/launcher_icon'),
    );
    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  tz.Location? _findLocationByOffset(Duration offset) {
    for (final loc in tz.timeZoneDatabase.locations.values) {
      if (tz.TZDateTime.now(loc).timeZoneOffset == offset) return loc;
    }
    return null;
  }

  /// Android 13 이상에서 알림 권한 요청 (처음 한 번만 시스템 팝업이 뜸)
  Future<void> requestPermission() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint("⚠️ 알림 권한 요청 실패: $e");
    }
  }

  /// 잔여 연차와 초기화일을 기준으로 알림을 다시 예약 (데이터 갱신 때마다 호출)
  Future<void> scheduleResetReminders({
    required double remaining,
    required DateTime resetDate,
  }) async {
    if (!_initialized) await init();
    try {
      await _plugin.cancelAll();
      if (remaining <= 0) return;

      final now = tz.TZDateTime.now(tz.local);
      final reset = resetDate.toLocal();

      for (final days in _reminderDaysBefore) {
        final target = tz.TZDateTime(tz.local, reset.year, reset.month, reset.day, 9)
            .subtract(Duration(days: days));
        if (!target.isAfter(now)) continue;

        final remainingText = _fmt(remaining);
        await _plugin.zonedSchedule(
          id: days,
          title: "연차 $remainingText개가 아직 남아 있어요",
          body: "초기화일(${reset.year}.${_pad(reset.month)}.${_pad(reset.day)})까지 $days일 남았습니다. 소멸 전에 사용하세요!",
          scheduledDate: target,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              channelDescription: _channelDesc,
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
            ),
          ),
          // 정확한 알람 권한 없이도 동작하도록 inexact 모드 사용 (몇 분 오차 허용)
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      debugPrint("⚠️ 알림 예약 실패: $e");
    }
  }

  Future<void> cancelAll() async {
    if (!_initialized) await init();
    await _plugin.cancelAll();
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
  String _fmt(double n) =>
      n == n.toInt() ? n.toInt().toString() : n.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
}
