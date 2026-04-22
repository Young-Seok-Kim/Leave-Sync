import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart'; // 별칭(as) 없이 임포트
import 'package:flutter/material.dart';

// 결과값을 담을 모델 클래스
class LeaveResult {
  final double totalUsed;
  final List<Map<String, dynamic>> events;
  LeaveResult(this.totalUsed, this.events);
}

class GoogleCalendarService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [CalendarApi.calendarEventsReadonlyScope],
  );

  Future<GoogleSignInAccount?> signIn() async => await _googleSignIn.signIn();
  Future<GoogleSignInAccount?> signInSilently() async => await _googleSignIn.signInSilently();
  Future<void> signOut() async => await _googleSignIn.signOut();

  Future<LeaveResult> calculateUsedLeave(GoogleSignInAccount account, DateTime resetDate) async {
    final httpClient = await _googleSignIn.authenticatedClient();
    if (httpClient == null) return LeaveResult(0.0, []);

    // 1. 클래스명(CalendarApi)과 겹치지 않게 변수명을 'api'로 설정
    final api = CalendarApi(httpClient);
    final now = DateTime.now();

    DateTime periodStart = DateTime(now.year, resetDate.month, resetDate.day);
    if (periodStart.isAfter(now)) {
      periodStart = DateTime(now.year - 1, resetDate.month, resetDate.day);
    }
    final periodEnd = periodStart.add(const Duration(days: 365));

    final timeMin = periodStart.toUtc();
    final timeMax = periodEnd.toUtc();

    debugPrint("🔎 검색 주기: $timeMin ~ $timeMax");

    try {
      // 2. 공휴일 데이터 가져오기 (매개변수로 api 전달)
      final Set<DateTime> publicHolidays = await _getPublicHolidays(api, timeMin, timeMax);

      // 3. 내 기본 캘린더 일정 가져오기
      final events = await api.events.list(
        'primary',
        timeMin: timeMin,
        timeMax: timeMax,
        singleEvents: true,
        orderBy: 'startTime',
        maxResults: 2500,
      );

      double totalUsed = 0.0;
      List<Map<String, dynamic>> detectedEvents = [];

      if (events.items != null) {
        for (var event in events.items!) {
          if (event.status == 'cancelled') continue;

          final title = event.summary ?? "";
          final cleanTitle = title.replaceAll(' ', '');

          double dayScore = 0.0;
          if (cleanTitle.contains('연차')) {
            dayScore = 1.0;
          } else if (cleanTitle.contains('반차')) {
            dayScore = 0.5;
          } else if (cleanTitle.contains('반반차')) {
            dayScore = 0.25;
          }

          if (dayScore > 0) {
            DateTime start = (event.start?.date ?? event.start?.dateTime ?? now).toLocal();
            DateTime end = (event.end?.date ?? event.end?.dateTime ?? now).toLocal();

            double eventDeduction = 0.0;
            DateTime tempDate = DateTime(start.year, start.month, start.day);

            while (tempDate.isBefore(end)) {
              bool isWeekend = tempDate.weekday == DateTime.saturday || tempDate.weekday == DateTime.sunday;

              // 공휴일 체크 로직
              bool isPublicHoliday = publicHolidays.any((h) =>
              h.year == tempDate.year && h.month == tempDate.month && h.day == tempDate.day);

              if (!isWeekend && !isPublicHoliday) {
                eventDeduction += dayScore;
              }
              tempDate = tempDate.add(const Duration(days: 1));
            }

            if (eventDeduction > 0) {
              totalUsed += eventDeduction;
              detectedEvents.add({
                'id': event.id,
                'title': title,
                'date': event.start?.date ?? event.start?.dateTime,
                'deduction': eventDeduction,
              });
            }
          }
        }
      }
      return LeaveResult(totalUsed, detectedEvents);
    } catch (e) {
      debugPrint("❌ API 에러: $e");
      return LeaveResult(0.0, []);
    }
  }

  // 4. 파라미터 타입을 CalendarApi로 정확히 명시
  Future<Set<DateTime>> _getPublicHolidays(CalendarApi api, DateTime start, DateTime end) async {
    final Set<DateTime> holidays = {};
    try {
      const holidayCalendarId = "ko.south_korea#holiday@group.v.calendar.google.com";
      final holidayEvents = await api.events.list(
        holidayCalendarId,
        timeMin: start,
        timeMax: end,
      );

      if (holidayEvents.items != null) {
        for (var holiday in holidayEvents.items!) {
          if (holiday.start?.date != null) {
            holidays.add(DateTime.parse(holiday.start!.date!.toString()));
          }
        }
      }
    } catch (e) {
      debugPrint("⚠️ 공휴일 정보를 가져오지 못했습니다: $e");
    }
    return holidays;
  }
}