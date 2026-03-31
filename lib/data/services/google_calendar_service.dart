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

    final calendarApi = CalendarApi(httpClient);
    final now = DateTime.now();

    // [주기 계산 로직] 설정된 날짜가 미래라면 작년부터 검색하도록 조정
    DateTime periodStart = DateTime(now.year, resetDate.month, resetDate.day);
    if (periodStart.isAfter(now)) {
      periodStart = DateTime(now.year - 1, resetDate.month, resetDate.day);
    }
    final periodEnd = periodStart.add(const Duration(days: 365));

    final timeMin = periodStart.toUtc();
    final timeMax = periodEnd.toUtc();

    debugPrint("🔎 검색 주기: $timeMin ~ $timeMax");

    try {
      final events = await calendarApi.events.list(
        'primary',
        timeMin: timeMin,
        timeMax: timeMax,
        singleEvents: true,
        orderBy: 'startTime',
        maxResults: 2500,
      );

      double used = 0.0;
      List<Map<String, dynamic>> detectedEvents = [];

      if (events.items != null) {
        for (var event in events.items!) {
          if (event.status == 'cancelled') continue;
          final title = event.summary ?? "";
          final cleanTitle = title.replaceAll(' ', '');
          double deduction = 0.0;

          debugPrint("📌 캘린더에서 읽은 제목: '${event.summary}' | 시작시간: ${event.start?.dateTime ?? event.start?.date}");

          if (cleanTitle.contains('연차')) {
            deduction = 1.0;
          } else if (cleanTitle.contains('반차')) {
            deduction = 0.5;
          } else if (cleanTitle.contains('반반차')) {
            deduction = 0.25;
          }

          if (deduction > 0) {
            used += deduction;
            detectedEvents.add({
              'id': event.id,
              'title': title,
              'date': event.start?.dateTime ?? event.start?.date,
              'deduction': deduction,
            });
          }
        }
      }
      return LeaveResult(used, detectedEvents);
    } catch (e) {
      debugPrint("❌ API 에러: $e");
      return LeaveResult(0.0, []);
    }
  }
}