import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/user_setting.dart';
import '../services/google_calendar_service.dart';
import '../services/notification_service.dart';
import '../services/settings_backup_service.dart';
import '../services/widget_service.dart';

final calendarServiceProvider = Provider((ref) => GoogleCalendarService());

final settingsBackupProvider =
    Provider((ref) => SettingsBackupService(ref.read(calendarServiceProvider)));

final leaveStateProvider = StateNotifierProvider<LeaveNotifier, UserSetting?>((ref) {
  return LeaveNotifier(backup: ref.read(settingsBackupProvider));
});

final holidayListProvider = AsyncNotifierProvider<HolidayListNotifier, List<Map<String, dynamic>>>(() {
  return HolidayListNotifier();
});

class LeaveNotifier extends StateNotifier<UserSetting?> {

  static const int _currentSchemaVersion = 2;

  /// 구글 드라이브 백업 (테스트 등에서는 null)
  final SettingsBackupService? _backup;

  LeaveNotifier({SettingsBackupService? backup})
      : _backup = backup,
        super(null) {
    _init();
  }

  void _init() {
    final box = Hive.box<UserSetting>('settings');
    if (box.isNotEmpty) {
      UserSetting savedData = box.get(0)!;

      if ((savedData.schemaVersion ?? 0) < _currentSchemaVersion) {
        savedData = _migrate(savedData, savedData.schemaVersion ?? 0);
        box.put(0, savedData); // 최신 버전으로 갱신 저장
      }

      state = savedData;
      Future.microtask(() => refreshTotalLeave());
    }
  }

  UserSetting _migrate(UserSetting oldData, int oldVersion) {
    UserSetting newData = oldData;

    if (oldVersion < 1) {
      final now = DateTime.now();
      final entry = oldData.entryDate;

      if (entry != null) {
        // 1. 이번 달의 연차 지급 예정일 (예: 2026년 5월 13일)
        final thisMonthPayDay = DateTime(now.year, now.month, entry.day);

        // 2. 오늘이 지급일보다 같거나 지났는지 확인
        bool isPayDayPassed = !now.isBefore(thisMonthPayDay);

        if (isPayDayPassed) {
          // [케이스 A] 오늘이 13일 이후인데, 아직 lastAutoUpdate가 없어서 연차를 못 받은 상태라면?
          // -> 지난달 날짜를 넣어주어 refreshTotalLeave가 "이번 달(5월) 꺼 줘야지!" 하게 만듭니다.
          newData = newData.copyWith(
            lastAutoUpdate: DateTime(now.year, now.month - 1, entry.day),
            schemaVersion: 1,
          );
        } else {
          // [케이스 B] 아직 이번 달 지급일(13일)이 안 왔다면?
          // -> 역시 지난달 날짜를 넣어둡니다. 그러면 나중에 13일이 되었을 때 정상 지급됩니다.
          newData = newData.copyWith(
            lastAutoUpdate: DateTime(now.year, now.month - 1, entry.day),
            schemaVersion: 1,
          );
        }
      } else {
        // 입사일 정보가 아예 없는 예외 케이스
        newData = newData.copyWith(
          lastAutoUpdate: now,
          schemaVersion: 1,
        );
      }
    }

    // 버전 2 처리 (예: 새로운 필드 추가 시)
    if (oldVersion < 2) {
      newData = newData.copyWith(
        // 추가된 필드 초기화 로직
        schemaVersion: 2,
      );
    }

    return newData;
  }

  void refreshTotalLeave({DateTime? mockDate}) {
    if (state == null || state!.entryDate == null) return;

    final now = mockDate ?? DateTime.now();
    final entry = state!.entryDate!;
    final reset = state!.resetDate;

    // 1. [리셋 로직] 초기화 날짜는 "그날까지 사용 가능"한 마지막 날이므로, 그 다음 날부터 새 주기가 시작된다.
    //    예: 초기화일 12.31 → 1.1 에 새 연차 지급, 다음 초기화일은 내년 12.31
    final today = DateTime(now.year, now.month, now.day);
    final resetDay = DateTime(reset.year, reset.month, reset.day);
    if (today.isAfter(resetDay)) {
      // ★ 시뮬레이션 중인 'now'를 계산 함수에 전달
      final newTotal = _calculateFullLegalLeave(entry, now: now);
      // 오랫동안 앱을 안 열었어도 다음 초기화일이 오늘 이후가 될 때까지 1년씩 넘긴다
      var nextReset = DateTime(resetDay.year + 1, resetDay.month, resetDay.day);
      while (today.isAfter(nextReset)) {
        nextReset = DateTime(nextReset.year + 1, nextReset.month, nextReset.day);
      }

      // ★ 저장 시점도 'now'로 기록해야 무한 루프 안 도미
      saveSettings(newTotal, nextReset, entry, updateLastUpdate: true, mockDate: now);
      return;
    }

    // 2. [증분 로직] 1년 미만
    int totalMonths = (now.year - entry.year) * 12 + now.month - entry.month;
    if (now.day < entry.day) totalMonths--;

    if (totalMonths < 12 && totalMonths > 0) {
      // 기록이 없으면 입사일 기준으로 판단
      final lastUpdate = state!.lastAutoUpdate ?? entry;

      bool alreadyUpdatedThisMonth =
          lastUpdate.year == now.year && lastUpdate.month == now.month;

      if (now.day >= entry.day && !alreadyUpdatedThisMonth) {
        final updatedState = state!.copyWith(
          totalLeave: state!.totalLeave + 1.0,
          lastAutoUpdate: now,
        );
        _saveState(updatedState);
      }
    }
  }


  Future<void> _saveState(UserSetting setting, {bool backup = true}) async {
    state = setting;
    final box = Hive.box<UserSetting>('settings');
    await box.put(0, setting);
    // 로그인돼 있으면 구글 드라이브에도 올려 두어 앱을 지워도 설정이 남도록 함
    final b = _backup;
    if (backup && b != null) unawaited(b.backup(setting));
  }

  /// 드라이브 백업에서 받아온 설정을 그대로 적용 (다시 올릴 필요는 없음)
  Future<void> applyRestored(UserSetting restored, String email) async {
    var setting = restored.copyWith(accountEmail: email, isFirstRun: false);
    if ((setting.schemaVersion ?? 0) < _currentSchemaVersion) {
      setting = _migrate(setting, setting.schemaVersion ?? 0);
    }
    await _saveState(setting, backup: false);
    refreshTotalLeave();
  }

  /// 로그인한 계정과 로컬 설정을 맞춘다.
  /// - 로컬 설정이 아직 어느 계정에도 묶이지 않았으면 이 계정에 묶고 백업
  /// - 다른 계정으로 바뀌었으면 그 계정의 백업이 있을 때 그것으로 교체, 없으면 현재 설정을 그 계정에 묶어 백업
  Future<void> syncAccount(String email) async {
    final current = state;
    if (current == null || current.accountEmail == email) return;

    final b = _backup;
    if (current.accountEmail != null && b != null) {
      final restored = await b.restore();
      if (restored != null) {
        await applyRestored(restored, email);
        return;
      }
    }
    await _saveState(current.copyWith(accountEmail: email));
  }

  Future<void> saveSettings(
      double total,
      DateTime reset,
      DateTime? entry,
      {bool updateLastUpdate = true,
        DateTime? mockDate, // ★ 시뮬레이션을 위한 mockDate 추가
        List<String>? calendarIds}
      ) async {
    final now = mockDate ?? DateTime.now(); // 실제 오늘 대신 주입된 날짜 사용
    final setting = UserSetting(
      totalLeave: total,
      resetDate: reset,
      entryDate: entry,
      isFirstRun: false,
      lastAutoUpdate: updateLastUpdate ? now : state?.lastAutoUpdate,
      schemaVersion: _currentSchemaVersion, // 저장 시 스키마 버전 명시
      calendarIds: calendarIds ?? state?.calendarIds,
      accountEmail: state?.accountEmail,
      notificationsEnabled: state?.notificationsEnabled,
    );
    await _saveState(setting);
  }

  /// 연차 소멸 알림 사용 여부만 변경
  Future<void> saveNotificationsEnabled(bool enabled) async {
    if (state == null) return;
    await _saveState(state!.copyWith(notificationsEnabled: enabled));
  }

  /// 휴가를 읽어올 캘린더 목록만 변경
  Future<void> saveCalendarIds(List<String> ids) async {
    if (state == null) return;
    await _saveState(state!.copyWith(calendarIds: ids));
  }
  double _calculateFullLegalLeave(DateTime entryDate, {DateTime? now}) {
    final referenceDate = now ?? DateTime.now(); // 주입된 날짜가 없으면 실제 오늘 사용

    int totalMonths = (referenceDate.year - entryDate.year) * 12 + referenceDate.month - entryDate.month;
    if (referenceDate.day < entryDate.day) totalMonths--;

    if (totalMonths < 12) {
      return totalMonths.clamp(0, 11).toDouble();
    } else {
      int years = (totalMonths ~/ 12);
      int extra = (years - 1) ~/ 2;
      return (15.0 + extra).clamp(15.0, 25.0);
    }
  }

  double calculateByEntryDate(DateTime entryDate) {
    final now = DateTime.now();

    // 1. 전체 근속 개월 수 계산
    int totalMonths = (now.year - entryDate.year) * 12 + now.month - entryDate.month;

    // 아직 해당 월의 입사일이 지나지 않았으면 한 달을 다 채운 게 아님
    if (now.day < entryDate.day) {
      totalMonths--;
    }

    // 2. 1년 미만인지 확인 (근속 12개월 미만)
    if (totalMonths < 12) {
      // 1개월 개근 시 1개씩 발생 (최대 11개)
      return totalMonths.clamp(0, 11).toDouble();
    } else {
      // 3. 1년 이상자 로직 (기존 로직 유지)
      int years = (totalMonths ~/ 12);
      int extra = (years - 1) ~/ 2;
      return (15.0 + extra).clamp(15.0, 25.0);
    }
  }
}

class HolidayListNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    return _fetchCalendarData();
  }

  Future<List<Map<String, dynamic>>> _fetchCalendarData() async {
    final service = ref.read(calendarServiceProvider);
    var settings = ref.read(leaveStateProvider);

    if (settings == null) return [];

    var account = await service.signInSilently() ?? await service.signIn();
    if (account == null) throw NotSignedInException();

    // 예전 버전(읽기 전용)으로 로그인한 경우 일정 등록/백업 권한을 추가로 요청
    await service.ensureScopes();

    // 로그인한 계정 기준으로 설정을 맞춤 (계정이 바뀌었으면 그 계정의 백업으로 교체)
    final leaveNotifier = ref.read(leaveStateProvider.notifier);
    await leaveNotifier.syncAccount(account.email);
    settings = ref.read(leaveStateProvider) ?? settings;

    // ★ 수정: 서비스 호출 시 입사일 정보 전달
    final result = await service.calculateUsedLeave(
        account,
        settings.resetDate,
        entryDate: settings.entryDate,
        calendarIds: settings.effectiveCalendarIds,
    );

    final List<Map<String, dynamic>> allEvents = List.from(result.events);

    // 1. 정렬 (오늘 기준 과거/미래)
    sortLeaveEvents(allEvents);

    // 2. 이번 주기(초기화일 기준)의 사용량으로 홈 위젯 갱신 + 소멸 알림 재예약
    final period = currentPeriod(settings.resetDate);
    final cycleEvents = filterLeaveEvents(allEvents, period.start, period.end);
    final used = cycleEvents.fold<double>(0.0, (sum, e) => sum + (e['deduction'] ?? 0.0));
    final remaining = (settings.totalLeave - used).clamp(0.0, settings.totalLeave);
    debugPrint("📊 동기화 완료: 전체 ${allEvents.length}건, 주기(${period.start.toIso8601String().substring(0, 10)}~${period.end.toIso8601String().substring(0, 10)}) ${cycleEvents.length}건, 사용 $used, 잔여 $remaining");
    unawaited(WidgetService.update(
      total: settings.totalLeave,
      remaining: remaining,
      resetDate: settings.resetDate,
    ));
    if (settings.remindersOn) {
      unawaited(NotificationService.instance.scheduleResetReminders(
        remaining: remaining,
        resetDate: settings.resetDate,
      ));
    } else {
      unawaited(NotificationService.instance.cancelAll());
    }

    // 전체 일정을 돌려주고, 화면에서 기간을 골라 거른다
    return allEvents;
  }

  Future<void> refresh() async {
    // 연차 증분 체크 후 리스트 갱신
    ref.read(leaveStateProvider.notifier).refreshTotalLeave();
    state = await AsyncValue.guard(() => _fetchCalendarData());
  }

  /// 앱에서 휴가 일정을 생성한 뒤 목록 갱신
  Future<void> addLeave(LeaveRequest request) async {
    final service = ref.read(calendarServiceProvider);
    final settings = ref.read(leaveStateProvider);
    final ids = settings?.effectiveCalendarIds ?? const ['primary'];
    // 기본 캘린더가 선택돼 있으면 거기에, 아니면 첫 번째 선택 캘린더에 등록
    final targetCalendar = ids.contains('primary') ? 'primary' : ids.first;
    await service.createLeaveEvent(calendarId: targetCalendar, request: request);
    await refresh();
  }

  /// 로그아웃 후 다시 로그인하면서 목록 갱신 (오류 화면의 "다시 로그인" 버튼용)
  Future<void> reSignIn() async {
    await ref.read(calendarServiceProvider).signOut();
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchCalendarData());
  }

}

DateTime leaveEventDate(Map<String, dynamic> e) =>
    (e['date'] is DateTime ? e['date'] as DateTime : DateTime.parse(e['date'].toString())).toLocal();

/// 현재 집계 주기: 지난 초기화일 다음 날 ~ 다가오는 초기화일(그날 포함)
/// 예: 초기화일 12.31 → 1.1 ~ 12.31, 초기화일 4.12 → 작년 4.13 ~ 올해 4.12
({DateTime start, DateTime end}) currentPeriod(DateTime resetDate, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final r = resetDate.toLocal();
  DateTime end = DateTime(today.year, r.month, r.day);
  if (end.isBefore(today)) end = DateTime(today.year + 1, r.month, r.day);
  final start = DateTime(end.year - 1, r.month, r.day).add(const Duration(days: 1));
  return (start: start, end: end);
}

/// 시작일이 [start]~[end] 안에 있는 일정만
List<Map<String, dynamic>> filterLeaveEvents(
    List<Map<String, dynamic>> events, DateTime start, DateTime end) {
  final s = DateTime(start.year, start.month, start.day);
  final e = DateTime(end.year, end.month, end.day);
  return events.where((ev) {
    final d = leaveEventDate(ev);
    final day = DateTime(d.year, d.month, d.day);
    return !day.isBefore(s) && !day.isAfter(e);
  }).toList();
}

/// 다가오는 일정은 가까운 순으로 위에, 지난 일정은 최근 순으로 아래에
void sortLeaveEvents(List<Map<String, dynamic>> events, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final todayStart = DateTime(n.year, n.month, n.day);
  events.sort((a, b) {
    final dateA = leaveEventDate(a);
    final dateB = leaveEventDate(b);
    final dayA = DateTime(dateA.year, dateA.month, dateA.day);
    final dayB = DateTime(dateB.year, dateB.month, dateB.day);
    final isPastA = dayA.isBefore(todayStart);
    final isPastB = dayB.isBefore(todayStart);
    if (isPastA != isPastB) return isPastA ? 1 : -1;
    return isPastA ? dateB.compareTo(dateA) : dateA.compareTo(dateB);
  });
}
