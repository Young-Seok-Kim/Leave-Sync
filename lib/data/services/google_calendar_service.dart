import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart';
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

    final api = CalendarApi(httpClient);
    final now = DateTime.now();

    // 1. 검색 주기 설정 (연차 초기화 날짜 기준)
    DateTime periodStart = DateTime(now.year, resetDate.month, resetDate.day);
    if (periodStart.isAfter(now)) {
      periodStart = DateTime(now.year - 1, resetDate.month, resetDate.day);
    }
    // 넉넉하게 1년치 범위를 잡음 (다음 초기화 전날까지)
    final periodEnd = periodStart.add(const Duration(days: 366));

    final timeMin = periodStart.toUtc();
    final timeMax = periodEnd.toUtc();

    debugPrint("🔎 검색 주기(UTC): $timeMin ~ $timeMax");

    try {
      // 2. 공휴일 정보 미리 가져오기 (차감 계산 시 제외 목적)
      final Set<DateTime> publicHolidays = await _getPublicHolidays(api, timeMin, timeMax);

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

          double weight = 0.0;

          if (cleanTitle.contains('반반차')) {
            weight = 0.25;
          } else if (cleanTitle.contains('반차')) {
            weight = 0.5;
          } else if (cleanTitle.contains('연차')) {
            weight = 1.0;
          }

          // 제목에 키워드가 포함된 경우만 계산 시작
          if (weight > 0) {
            // 1. 날짜 데이터 추출 (시간 정보 제거하고 날짜만 남김)
            DateTime start = (event.start?.date ?? event.start?.dateTime ?? now).toLocal();
            DateTime end = (event.end?.date ?? event.end?.dateTime ?? now).toLocal();

            DateTime tempDate = DateTime(start.year, start.month, start.day);
            DateTime endDate = DateTime(end.year, end.month, end.day);

            // 구글 종일 일정(All-day)은 종료일이 다음날 00:00으로 오므로 하루를 빼줌
            if (event.start?.date != null) {
              endDate = endDate.subtract(const Duration(days: 1));
            }

            double eventDeduction = 0.0;

            // 2. 시작일부터 종료일까지 '날짜' 단위로 루프
            while (!tempDate.isAfter(endDate)) {
              bool isWeekend = tempDate.weekday == DateTime.saturday || tempDate.weekday == DateTime.sunday;
              bool isPublicHoliday = publicHolidays.any((h) =>
              h.year == tempDate.year && h.month == tempDate.month && h.day == tempDate.day);

              // 주말/공휴일이 아닐 때만 가중치(0.25, 0.5 등) 누적
              if (!isWeekend && !isPublicHoliday) {
                eventDeduction += weight;
              }

              // 다음날로 이동
              tempDate = tempDate.add(const Duration(days: 1));
            }

            if (eventDeduction > 0) {
              totalUsed += eventDeduction;

              final DateTime finalDate = (event.start?.date != null)
                  ? DateTime.parse(event.start!.date!.toString())
                  : (event.start?.dateTime ?? now);

              detectedEvents.add({
                'id': event.id,
                'title': title,
                'date': finalDate,
                'endDate': (event.end?.date != null)
                    ? DateTime.parse(event.end!.date!.toString()).subtract(const Duration(days: 1))
                    : (event.end?.dateTime ?? now),
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

  // 공휴일 캘린더에서 데이터 가져오는 헬퍼 함수
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
            // "2026-05-05" 형태의 문자열을 DateTime으로 파싱
            DateTime holidayDate = DateTime.parse(holiday.start!.date!.toString());
            holidays.add(DateTime(holidayDate.year, holidayDate.month, holidayDate.day));
          }
        }
      }
    } catch (e) {
      debugPrint("⚠️ 공휴일 정보를 가져오지 못했습니다: $e");
    }
    return holidays;
  }
}