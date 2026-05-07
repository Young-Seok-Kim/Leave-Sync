import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/leave_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _totalController;
  late DateTime _selectedDate;
  DateTime? _entryDate; // 입사일 관리

  @override
  void initState() {
    super.initState();
    final currentSetting = ref.read(leaveStateProvider);
    _totalController = TextEditingController(text: currentSetting?.totalLeave.toString() ?? "15");
    _selectedDate = currentSetting?.resetDate ?? DateTime(DateTime.now().year, 12, 31);
    _entryDate = currentSetting?.entryDate;
  }

  Future<void> _pickEntryDate() async {
    // 현재 저장된 날짜가 미래일 경우를 대비해 initialDate를 안전하게 설정
    DateTime initial = _entryDate ?? DateTime.now();
    final DateTime upperLimit = DateTime(2100, 12, 31);

    // initialDate는 반드시 firstDate와 lastDate 사이에 있어야 합니다.
    if (initial.isAfter(upperLimit)) {
      initial = DateTime.now();
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: upperLimit, // ✅ 확실하게 미래 날짜로 박혀있는지 확인!
      helpText: "입사일을 선택하면 연차가 자동 계산됩니다",
    );

    if (picked != null) {
      setState(() {
        _entryDate = picked;
        final result = ref.read(leaveStateProvider.notifier).calculateByEntryDate(picked);
        _totalController.text = result.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text("설정", style: TextStyle(fontWeight: FontWeight.bold)), elevation: 0),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TextField(
              controller: _totalController,
              decoration: InputDecoration(
                labelText: "총 연차 개수",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.auto_awesome, color: Colors.deepPurpleAccent),
                  onPressed: _pickEntryDate,
                ),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 32),
            ListTile(
              title: const Text("연차 초기화 날짜"),
              subtitle: Text("${_selectedDate.year}.${_selectedDate.month}.${_selectedDate.day}"),
              trailing: const Icon(Icons.calendar_month),
              shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (picked != null) setState(() => _selectedDate = picked);
              },
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () async {
                  final total = double.tryParse(_totalController.text) ?? 15.0;
                  // ★ saveSettings 호출 시 _entryDate 전달
                  await ref.read(leaveStateProvider.notifier).saveSettings(total, _selectedDate, _entryDate);
                  if (mounted) Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF764BA2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text("저장하기", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }
}