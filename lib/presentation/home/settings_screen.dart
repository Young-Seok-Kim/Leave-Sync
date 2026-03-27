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

  @override
  void initState() {
    super.initState();
    final currentSetting = ref.read(leaveStateProvider);
    _totalController = TextEditingController(text: currentSetting?.totalLeave.toString() ?? "15");
    _selectedDate = currentSetting?.resetDate ?? DateTime(DateTime.now().year, 12, 31);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("설정 수정")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(
              controller: _totalController,
              decoration: const InputDecoration(labelText: "총 연차 개수 수정"),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            ListTile(
              title: const Text("연차 초기화 날짜 수정"),
              subtitle: Text("${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}"),
              trailing: const Icon(Icons.calendar_today),
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
              child: ElevatedButton(
                onPressed: () async {
                  final total = double.tryParse(_totalController.text) ?? 15.0;
                  await ref.read(leaveStateProvider.notifier).saveSettings(total, _selectedDate);
                  if (mounted) Navigator.pop(context); // 수정 후 홈으로 돌아가기
                },
                child: const Text("저장하기"),
              ),
            )
          ],
        ),
      ),
    );
  }
}