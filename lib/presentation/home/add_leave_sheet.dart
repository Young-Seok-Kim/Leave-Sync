import 'package:flutter/material.dart';
import '../../data/services/google_calendar_service.dart';
import '../../data/services/naver_place_service.dart';
import 'drag_range_calendar.dart';
import 'place_search_sheet.dart';

/// 휴가 등록 입력 화면 (바텀 시트). 등록을 누르면 [LeaveRequest] 를 반환
Future<LeaveRequest?> showAddLeaveSheet(BuildContext context) {
  return showModalBottomSheet<LeaveRequest>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => const _AddLeaveSheet(),
  );
}

class _AddLeaveSheet extends StatefulWidget {
  const _AddLeaveSheet();

  @override
  State<_AddLeaveSheet> createState() => _AddLeaveSheetState();
}

class _AddLeaveSheetState extends State<_AddLeaveSheet> {
  static const _brand = Color(0xFF764BA2);

  LeaveType _type = LeaveType.full;
  late DateTime _start;
  late DateTime _end;

  final _titleController = TextEditingController(text: LeaveType.full.defaultTitle);
  final _locationController = TextEditingController();
  final _memoController = TextEditingController();

  // 사용자가 제목을 직접 고쳤는지 (고쳤으면 종류 변경 시 자동으로 덮어쓰지 않음)
  bool _titleEdited = false;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, now.day);
    _end = _start;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) =>
      "${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')} (${_weekday(d)})";

  String _weekday(DateTime d) => const ['월', '화', '수', '목', '금', '토', '일'][d.weekday - 1];

  int get _dayCount => _end.difference(_start).inDays + 1;

  void _selectType(LeaveType type) {
    setState(() {
      _type = type;
      if (!_titleEdited) {
        _titleController.text = type.defaultTitle;
      }
      _titleError = null;
    });
  }

  Future<void> _searchPlace() async {
    final picked = await showPlaceSearchSheet(context, initialQuery: _locationController.text);
    if (picked != null && picked.isNotEmpty && mounted) {
      setState(() => _locationController.text = picked);
    }
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = "제목을 입력하세요.");
      return;
    }
    if (!LeaveRequest.hasKeyword(title)) {
      setState(() => _titleError = "제목에 '연차', '반차', '반반차' 중 하나가 있어야 집계됩니다.");
      return;
    }
    Navigator.pop(
      context,
      LeaveRequest(
        type: _type,
        startDay: _start,
        endDay: _end,
        title: title,
        location: _locationController.text,
        description: _memoController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
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
            const Text("휴가 등록", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text("구글 캘린더에 바로 등록됩니다. 주말과 공휴일은 자동 제외됩니다.",
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 20),

            // 기간
            Row(
              children: [
                _label("기간"),
                const Spacer(),
                Text(
                  _dayCount == 1 ? _fmt(_start) : "${_fmt(_start)} ~ ${_fmt(_end)}  ·  $_dayCount일",
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _brand),
                ),
              ],
            ),
            const SizedBox(height: 4),
            DragRangeCalendar(
              start: _start,
              end: _end,
              onChanged: (s, e) => setState(() {
                _start = s;
                _end = e;
              }),
            ),
            const SizedBox(height: 16),

            // 종류
            _label("종류"),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: LeaveType.values.map((t) {
                final selected = t == _type;
                return ChoiceChip(
                  label: Text(t.isAllDay ? "${t.label} (종일)" : "${t.label} ${t.startHour}-${t.endHour}시"),
                  selected: selected,
                  selectedColor: const Color(0xFFF3E5F5),
                  labelStyle: TextStyle(
                    color: selected ? _brand : Colors.black87,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                  side: BorderSide(color: selected ? _brand : Colors.grey.shade300),
                  showCheckmark: false,
                  onSelected: (_) => _selectType(t),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // 제목
            _label("제목"),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              onChanged: (_) {
                _titleEdited = true;
                if (_titleError != null) setState(() => _titleError = null);
              },
              textInputAction: TextInputAction.next,
              decoration: _inputDecoration(
                hint: _type.defaultTitle,
                icon: Icons.title,
                errorText: _titleError,
                helper: "제목에 '연차/반차/반반차'가 있어야 집계됩니다",
              ),
            ),
            const SizedBox(height: 16),

            // 장소
            _label("장소 (선택)"),
            const SizedBox(height: 8),
            TextField(
              controller: _locationController,
              textInputAction: TextInputAction.next,
              decoration: _inputDecoration(
                hint: NaverPlaceService.isConfigured ? "직접 입력하거나 오른쪽 검색 버튼으로 찾기" : "예: 제주도",
                icon: Icons.place_outlined,
                suffix: NaverPlaceService.isConfigured
                    ? IconButton(
                        icon: const Icon(Icons.search, color: _brand),
                        tooltip: "네이버 장소 검색",
                        onPressed: _searchPlace,
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 16),

            // 메모
            _label("메모 (선택)"),
            const SizedBox(height: 8),
            TextField(
              controller: _memoController,
              minLines: 2,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              decoration: _inputDecoration(hint: "예: 가족 여행", icon: Icons.notes),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.check),
                label: const Text("캘린더에 등록", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brand,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blueGrey),
      );

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    String? errorText,
    String? helper,
    Widget? suffix,
  }) {
    return InputDecoration(
      suffixIcon: suffix,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 2,
      errorText: errorText,
      errorMaxLines: 2,
      prefixIcon: Icon(icon, size: 20, color: Colors.grey),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _brand, width: 1.5),
      ),
    );
  }
}
