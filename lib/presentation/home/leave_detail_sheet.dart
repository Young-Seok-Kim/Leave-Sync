import 'package:flutter/material.dart';

/// 상세 사용 내역 항목을 탭했을 때 보여주는 상세 정보 시트
Future<void> showLeaveDetailSheet(
  BuildContext context, {
  required Map<String, dynamic> event,
  required VoidCallback onOpenCalendar,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _LeaveDetailSheet(event: event, onOpenCalendar: onOpenCalendar),
  );
}

class _LeaveDetailSheet extends StatelessWidget {
  static const _brand = Color(0xFF764BA2);

  final Map<String, dynamic> event;
  final VoidCallback onOpenCalendar;

  const _LeaveDetailSheet({required this.event, required this.onOpenCalendar});

  DateTime _toDate(dynamic v) => v is DateTime ? v : DateTime.parse(v.toString());

  String _fmt(DateTime d) =>
      "${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')} (${_weekday(d)})";

  String _weekday(DateTime d) => const ['월', '화', '수', '목', '금', '토', '일'][d.weekday - 1];

  String _fmtNum(double n) =>
      n == n.toInt() ? n.toInt().toString() : n.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');

  @override
  Widget build(BuildContext context) {
    final start = _toDate(event['date']).toLocal();
    DateTime end = event['endDate'] != null ? _toDate(event['endDate']).toLocal() : start;
    if (end.isBefore(start)) end = start;

    final bool sameDay = DateUtils.isSameDay(start, end);
    final bool allDay = event['allDay'] == true;
    final int dayCount = DateTime(end.year, end.month, end.day)
            .difference(DateTime(start.year, start.month, start.day))
            .inDays +
        1;

    String period;
    if (sameDay) {
      period = _fmt(start);
      if (!allDay) {
        period += "  ${_time(start)} ~ ${_time(end)}";
      }
    } else {
      period = "${_fmt(start)} ~ ${_fmt(end)}";
    }

    final deduction = (event['deduction'] ?? 0.0) as double;
    final String location = (event['location'] ?? '').toString().trim();
    final String memo = (event['description'] ?? '').toString().trim();
    final String calendarName = (event['calendarName'] ?? '').toString().trim();

    final now = DateTime.now();
    final bool isPast = DateTime(start.year, start.month, start.day)
        .isBefore(DateTime(now.year, now.month, now.day));

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                backgroundColor: isPast ? Colors.grey[300] : const Color(0xFFF3E5F5),
                child: Icon(Icons.beach_access, color: isPast ? Colors.grey[600] : _brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  (event['title'] ?? '').toString(),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "-${_fmtNum(deduction)}개",
                  style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _row(Icons.date_range, "기간", dayCount > 1 ? "$period\n총 $dayCount일 (주말·공휴일 제외 ${_fmtNum(deduction)}개 차감)" : period),
          if (location.isNotEmpty) _row(Icons.place_outlined, "장소", location),
          if (memo.isNotEmpty) _row(Icons.notes, "메모", memo),
          if (calendarName.isNotEmpty) _row(Icons.calendar_month, "캘린더", calendarName),
          if (location.isEmpty && memo.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4, left: 32),
              child: Text("장소와 메모가 없는 일정입니다.", style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onOpenCalendar();
              },
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text("구글 캘린더에서 열기 (수정/삭제)"),
              style: OutlinedButton.styleFrom(
                foregroundColor: _brand,
                side: const BorderSide(color: _brand),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _time(DateTime d) => "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey),
          const SizedBox(width: 12),
          SizedBox(
            width: 44,
            child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87)),
          ),
        ],
      ),
    );
  }
}
