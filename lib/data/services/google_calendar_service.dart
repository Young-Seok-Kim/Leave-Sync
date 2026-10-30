import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// 결과값을 담을 모델 클래스
class LeaveResult {
  final double totalUsed;
  final List<Map<String, dynamic>> events;
  LeaveResult(this.totalUsed, this.events);
}

/// 구글 로그인이 안 되어 있거나 권한이 없어 캘린더를 읽을 수 없는 상태
class NotSignedInException implements Exception {
  final String message;
  NotSignedInException([this.message = "구글 계정 로그인이 필요합니다."]);
  @override
  String toString() => message;
}

/// 설정 화면에서 보여줄 캘린더 정보
class CalendarInfo {
  final String id;
  final String name;
  final bool isPrimary;
  final bool canWrite;
  const CalendarInfo({
    required this.id,
    required this.name,
    required this.isPrimary,
    required this.canWrite,
  });
}

/// 앱에서 등록할 수 있는 휴가 종류
enum LeaveType {
  full("연차", null, null),
  morningHalf("오전 반차", 9, 13),
  afternoonHalf("오후 반차", 13, 18),
  quarter("반반차", 16, 18);

  final String label;
  final int? startHour;
  final int? endHour;
  const LeaveType(this.label, this.startHour, this.endHour);

  bool get isAllDay => startHour == null;

  /// 기본 제목 (집계 키워드가 포함되어야 함)
  String get defaultTitle => "[$label]";
}

/// 등록 화면에서 입력한 휴가 정보
class LeaveRequest {
  final LeaveType type;
  final DateTime startDay;
  final DateTime endDay;
  final String title;
  final String location;
  final String description;

  const LeaveRequest({
    required this.type,
    required this.startDay,
    required this.endDay,
    required this.title,
    this.location = '',
    this.description = '',
  });

  /// 제목에 집계 키워드(연차/반차/반반차)가 들어 있는지
  static bool hasKeyword(String title) {
    final t = title.replaceAll(' ', '');
    return t.contains('연차') || t.contains('반차');
  }
}

class GoogleCalendarService {
  // 일정 등록(events)과 캘린더 목록 조회(readonly) 모두 필요
  static const List<String> scopes = [
    CalendarApi.calendarEventsScope,
    CalendarApi.calendarReadonlyScope,
  ];

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: dotenv.env['GOOGLE_WEB_CLIENT_ID'],
    scopes: scopes,
  );

  Future<GoogleSignInAccount?> signIn() async => await _googleSignIn.signIn();
  Future<GoogleSignInAccount?> signInSilently() async => await _googleSignIn.signInSilently();
  Future<void> signOut() async => await _googleSignIn.signOut();

  /// 현재 로그인된 계정 이메일 (이벤트 링크 생성용)
  String? get currentEmail => _googleSignIn.currentUser?.email;

  /// 예전 버전(일정만 읽기)으로 로그인한 사용자에게 캘린더 목록 조회 권한을 추가 요청
  Future<bool> ensureScopes() async {
    try {
      final ok = await _googleSignIn.canAccessScopes(scopes);
      if (ok) return true;
      return await _googleSignIn.requestScopes(scopes);
    } catch (e) {
      debugPrint("⚠️ 권한 확인 실패: $e");
      return true; // 확인이 안 되면 일단 진행하고 API 에러로 판단
    }
  }

  Future<CalendarApi> _api() async {
    final httpClient = await _googleSignIn.authenticatedClient();
    if (httpClient == null) throw NotSignedInException();
    return CalendarApi(httpClient);
  }

  /// 로그인한 계정이 볼 수 있는 캘린더 목록
  Future<List<CalendarInfo>> listCalendars() async {
    final api = await _api();
    final result = await api.calendarList.list(showHidden: false);
    final items = result.items ?? [];
    final list = items
        .where((c) => c.id != null && c.deleted != true)
        .map((c) => CalendarInfo(
              id: c.id!,
              name: c.summaryOverride ?? c.summary ?? c.id!,
              isPrimary: c.primary == true,
              canWrite: c.accessRole == 'owner' || c.accessRole == 'writer',
            ))
        .toList();
    // 기본 캘린더를 맨 위로
    list.sort((a, b) {
      if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return list;
  }

  /// 앱에서 직접 휴가 일정을 생성
  Future<void> createLeaveEvent({
    required String calendarId,
    required LeaveRequest request,
  }) async {
    final api = await _api();
    final type = request.type;
    final s = request.startDay;
    final e = request.endDay;

    final event = Event()
      ..summary = request.title.trim()
      ..location = request.location.trim().isEmpty ? null : request.location.trim()
      ..description = request.description.trim().isEmpty ? null : request.description.trim();

    if (type.isAllDay) {
      // 종일 일정: 구글은 종료일을 '다음날'로 받음 (exclusive)
      event.start = EventDateTime(date: DateTime(s.year, s.month, s.day));
      event.end = EventDateTime(date: DateTime(e.year, e.month, e.day).add(const Duration(days: 1)));
    } else {
      // 시간 지정 일정: 기기 로컬 시각을 UTC로 변환해 전달
      event.start = EventDateTime(dateTime: DateTime(s.year, s.month, s.day, type.startHour!).toUtc());
      event.end = EventDateTime(dateTime: DateTime(e.year, e.month, e.day, type.endHour!).toUtc());
    }

    await api.events.insert(event, calendarId);
  }

  Future<LeaveResult> calculateUsedLeave(
    GoogleSignInAccount account,
    DateTime resetDate, {
    DateTime? entryDate,
    List<String> calendarIds = const ['primary'],
  }) async {
    final api = await _api();
    final now = DateTime.now();

    // 조회 범위: 입사일 ~ 10년 후. 주기별 집계는 Provider/UI 에서 날짜로 거름
    final timeMin = (entryDate ?? DateTime(2000)).toUtc();
    // 미래: 현재로부터 10년 후까지 넉넉하게 조회하여 1년 제한 해제
    final timeMax = now.add(const Duration(days: 3650)).toUtc();

    debugPrint("🔎 검색 주기(UTC): $timeMin ~ $timeMax, 캘린더: $calendarIds");

    // 2. 공휴일 정보 미리 가져오기 (차감 계산 시 제외 목적)
    final Set<DateTime> publicHolidays = await _getPublicHolidays(api, timeMin, timeMax);

    double totalUsed = 0.0;
    final List<Map<String, dynamic>> detectedEvents = [];
    final Set<String> seenIds = {};

    // 상세 창에 캘린더 이름을 보여주기 위해 목록 조회 (실패해도 집계에는 영향 없음)
    final Map<String, String> calendarNames = {};
    if (calendarIds.length > 1) {
      try {
        for (final c in await listCalendars()) {
          calendarNames[c.id] = c.name;
          if (c.isPrimary) calendarNames['primary'] = c.name;
        }
      } catch (e) {
        debugPrint("⚠️ 캘린더 이름 조회 실패: $e");
      }
    }

    for (final calendarId in calendarIds) {
      final events = await api.events.list(
        calendarId,
        timeMin: timeMin,
        timeMax: timeMax,
        singleEvents: true,
        orderBy: 'startTime',
        maxResults: 2500,
      );

      for (final event in events.items ?? <Event>[]) {
        if (event.status == 'cancelled') continue;
        // 같은 일정이 여러 캘린더에 공유된 경우 한 번만 계산
        if (event.id != null && !seenIds.add(event.id!)) continue;

        final title = event.summary ?? "";
        final cleanTitle = title.replaceAll(' ', '');

        double weight = 0.0;
        if (cleanTitle.contains('반반차')) {
          weight = 0.25;
        } else if (cleanTitle.contains('반차')) {
          weight = 0.5;
        } else if (cleanTitle.contains('연차')) {
          weight = 1.0;
        }
        if (weight == 0) continue;

        DateTime start = (event.start?.date ?? event.start?.dateTime ?? now).toLocal();
        DateTime end = (event.end?.date ?? event.end?.dateTime ?? now).toLocal();

        // 시간을 완전히 제거하고 '날짜' 정보만 남깁니다. (중요)
        DateTime tempDate = DateTime(start.year, start.month, start.day);
        DateTime endDate = DateTime(end.year, end.month, end.day);

        // 구글 종일 일정(All-day)은 종료일이 다음날 00:00으로 오므로,
        // 시작일과 종료일이 다른 '진짜 여러 날짜'인 경우에만 종료일 보정을 수행합니다.
        if (event.start?.date != null && endDate.isAfter(tempDate)) {
          endDate = endDate.subtract(const Duration(days: 1));
        }

        double eventDeduction = 0.0;
        // 시작일부터 종료일까지 포함해서 루프를 돕니다.
        while (!tempDate.isAfter(endDate)) {
          final bool isWeekend =
              tempDate.weekday == DateTime.saturday || tempDate.weekday == DateTime.sunday;
          final bool isPublicHoliday = publicHolidays.contains(tempDate);

          if (!isWeekend && !isPublicHoliday) {
            eventDeduction += weight;
          }
          tempDate = tempDate.add(const Duration(days: 1));
        }

        if (eventDeduction > 0) {
          totalUsed += eventDeduction;

          final DateTime finalDate = (event.start?.date != null)
              ? DateTime.parse(event.start!.date!.toString())
              : (event.start?.dateTime ?? now);

          detectedEvents.add({
            'id': event.id,
            'calendarId': calendarId,
            'calendarName': calendarNames[calendarId] ?? '',
            'title': title,
            'location': event.location ?? '',
            'description': event.description ?? '',
            'allDay': event.start?.date != null,
            'date': finalDate,
            'endDate': (event.end?.date != null)
                ? DateTime.parse(event.end!.date!.toString()).subtract(const Duration(days: 1))
                : (event.end?.dateTime ?? now),
            'deduction': eventDeduction,
          });
        }
      }
    }
    return LeaveResult(totalUsed, detectedEvents);
  }

  // 공휴일 캘린더에서 데이터 가져오는 헬퍼 함수
  Future<Set<DateTime>> _getPublicHolidays(CalendarApi api, DateTime start, DateTime end) async {
    final Set<DateTime> holidays = {};
    try {
      const holidayCalendarId = "ko.south_korea#holiday@group.v.calendar.google.com";
      final holidayEvents = await api.events.list(
        holidayCalendarId,
        timeMin: start,
        timeMax: end,
        singleEvents: true,
        maxResults: 2500,
      );

      for (final holiday in holidayEvents.items ?? <Event>[]) {
        // 구글 공휴일 캘린더에는 '기념일'(제헌절 등 쉬지 않는 날)도 포함되므로 공휴일만 사용
        final desc = (holiday.description ?? '').toLowerCase();
        final bool isObservance = desc.contains('기념일') || desc.contains('observance');
        if (holiday.start?.date != null && !isObservance) {
          // "2026-05-05" 형태의 문자열을 DateTime으로 파싱 (로컬 자정 기준으로 통일)
          final d = DateTime.parse(holiday.start!.date!.toString());
          holidays.add(DateTime(d.year, d.month, d.day));
        }
      }
    } catch (e) {
      debugPrint("⚠️ 공휴일 정보를 가져오지 못했습니다: $e");
    }
    return holidays;
  }
}
