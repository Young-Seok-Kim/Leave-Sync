import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/leave_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = TextEditingController();
  DateTime _selectedDate = DateTime(DateTime.now().year, 12, 31);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("가이드 및 초기 설정")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Text("반갑습니다! 연차 동기화를 시작합니다.\n먼저 본인의 총 연차와 초기화 날짜를 입력해주세요."),
            TextField(controller: _controller, decoration: const InputDecoration(labelText: "총 연차 개수"), keyboardType: TextInputType.number),
            ListTile(
              title: const Text("초기화 날짜 선택"),
              subtitle: Text("${_selectedDate.toLocal()}".split(' ')[0]),
              onTap: () async {
                final picked = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime.now(), lastDate: DateTime(2030));
                if (picked != null) setState(() => _selectedDate = picked);
              },
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: () {
                final total = double.tryParse(_controller.text) ?? 15.0;
                ref.read(leaveStateProvider.notifier).saveSettings(total, _selectedDate);
              },
              child: const Text("설정 완료"),
            )
          ],
        ),
      ),
    );
  }
}