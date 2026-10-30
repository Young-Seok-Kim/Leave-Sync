import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 한 번 탭하면 하루, 누른 채 끌면 기간이 선택되는 월 달력
class DragRangeCalendar extends StatefulWidget {
  final DateTime start;
  final DateTime end;
  final void Function(DateTime start, DateTime end) onChanged;

  const DragRangeCalendar({
    super.key,
    required this.start,
    required this.end,
    required this.onChanged,
  });

  @override
  State<DragRangeCalendar> createState() => _DragRangeCalendarState();
}

class _DragRangeCalendarState extends State<DragRangeCalendar> {
  static const _brand = Color(0xFF764BA2);
  static const _brandLight = Color(0xFFEDE4F5);
  static const double _cellHeight = 42;
  static const int _rows = 6;

  late DateTime _visibleMonth;
  DateTime? _dragAnchor;

  @override
  void initState() {
    super.initState();
    _visibleMonth = DateTime(widget.start.year, widget.start.month);
  }

  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 그리드 셀 index → 날짜 (이번 달 밖이면 null)
  DateTime? _dateAt(int index) {
    final first = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final leading = first.weekday % 7; // 일요일 시작 (일=0)
    final dayNum = index - leading + 1;
    final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    if (dayNum < 1 || dayNum > daysInMonth) return null;
    return DateTime(_visibleMonth.year, _visibleMonth.month, dayNum);
  }

  DateTime? _dateAtPosition(Offset local, double width) {
    final cellWidth = width / 7;
    final col = (local.dx / cellWidth).floor().clamp(0, 6);
    final row = (local.dy / _cellHeight).floor();
    if (row < 0 || row >= _rows) return null;
    return _dateAt(row * 7 + col);
  }

  void _select(DateTime a, DateTime b) {
    final s = a.isBefore(b) ? a : b;
    final e = a.isBefore(b) ? b : a;
    widget.onChanged(s, e);
  }

  void _changeMonth(int delta) {
    setState(() => _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final start = _day(widget.start);
    final end = _day(widget.end);
    final today = _day(DateTime.now());

    return Column(
      children: [
        // 월 이동 헤더
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _changeMonth(-1),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Text(
                "${_visibleMonth.year}년 ${_visibleMonth.month}월",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _changeMonth(1),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        // 요일
        Row(
          children: List.generate(7, (i) {
            const names = ['일', '월', '화', '수', '목', '금', '토'];
            final color = i == 0 ? Colors.redAccent : (i == 6 ? Colors.blueAccent : Colors.grey);
            return Expanded(
              child: Center(
                child: Text(names[i], style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
              ),
            );
          }),
        ),
        const SizedBox(height: 4),
        // 날짜 그리드 (탭 = 하루, 짧게 누른 뒤 끌기 = 기간)
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              gestures: <Type, GestureRecognizerFactory>{
                TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  () => TapGestureRecognizer(),
                  (r) => r.onTapUp = (details) {
                    final d = _dateAtPosition(details.localPosition, width);
                    if (d != null) _select(d, d);
                  },
                ),
                LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                  // 스크롤과 충돌하지 않도록 아주 짧게 누른 뒤 끌면 기간 선택
                  () => LongPressGestureRecognizer(duration: const Duration(milliseconds: 150)),
                  (r) => r
                    ..onLongPressStart = (details) {
                      final d = _dateAtPosition(details.localPosition, width);
                      if (d == null) return;
                      HapticFeedback.selectionClick();
                      _dragAnchor = d;
                      _select(d, d);
                    }
                    ..onLongPressMoveUpdate = (details) {
                      final anchor = _dragAnchor;
                      if (anchor == null) return;
                      final d = _dateAtPosition(details.localPosition, width);
                      if (d == null) return;
                      if (d != start && d != end) HapticFeedback.selectionClick();
                      _select(anchor, d);
                    }
                    ..onLongPressEnd = (_) {
                      _dragAnchor = null;
                    }
                    ..onLongPressCancel = () {
                      _dragAnchor = null;
                    },
                ),
              },
              child: SizedBox(
                height: _cellHeight * _rows,
                child: Column(
                  children: List.generate(_rows, (row) {
                    return SizedBox(
                      height: _cellHeight,
                      child: Row(
                        children: List.generate(7, (col) {
                          final date = _dateAt(row * 7 + col);
                          return Expanded(child: _cell(date, col, start, end, today));
                        }),
                      ),
                    );
                  }),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        const Text(
          "탭: 하루 선택 · 누른 채 끌기: 기간 선택",
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _cell(DateTime? date, int col, DateTime start, DateTime end, DateTime today) {
    if (date == null) return const SizedBox.shrink();

    final bool isStart = date == start;
    final bool isEnd = date == end;
    final bool inRange = !date.isBefore(start) && !date.isAfter(end);
    final bool isToday = date == today;
    final bool single = start == end;

    Color textColor;
    if (isStart || isEnd) {
      textColor = Colors.white;
    } else if (col == 0) {
      textColor = Colors.redAccent;
    } else if (col == 6) {
      textColor = Colors.blueAccent;
    } else {
      textColor = Colors.black87;
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        // 기간 배경 띠 (시작·끝은 반만 칠해 둥근 끝 모양)
        if (inRange && !single)
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(child: Container(color: isStart ? Colors.transparent : _brandLight)),
                  Expanded(child: Container(color: isEnd ? Colors.transparent : _brandLight)),
                ],
              ),
            ),
          ),
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: (isStart || isEnd) ? _brand : Colors.transparent,
            shape: BoxShape.circle,
            border: isToday && !(isStart || isEnd) ? Border.all(color: _brand, width: 1.5) : null,
          ),
          alignment: Alignment.center,
          child: Text(
            "${date.day}",
            style: TextStyle(
              fontSize: 14,
              color: textColor,
              fontWeight: (isStart || isEnd || isToday) ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}
