import 'package:flutter/material.dart';

class AttendanceLog extends StatelessWidget {
  const AttendanceLog({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Log'),
        actions: [
          IconButton(icon: const Icon(Icons.file_upload), onPressed: () {}),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.calendar_month, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No attendance records found.',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {},
              child: const Text('Import Biometric Data'),
            ),
          ],
        ),
      ),
    );
  }
}
