import 'dart:convert';

void main() {
  String data = '{"record_id": 42}';
  final parsedData = jsonDecode(data);
  final recordId = parsedData['record_id'];
  
  final payload = {'id': recordId};
  
  print('Payload type: ${payload.runtimeType}');
  print('Is Map<String, dynamic>: ${payload is Map<String, dynamic>}');
}
