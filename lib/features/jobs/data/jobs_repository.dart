import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/freelancer_job.dart';

class JobsRepository {
  JobsRepository({
    http.Client? client,
    this.baseUrl = 'http://localhost:8080',
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<List<FreelancerJob>> getJobs() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/freelancer-jobs'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final list = data['jobs'] as List;
      return list.map((e) => FreelancerJob.fromJson(e)).toList();
    } else {
      throw Exception('Failed to fetch jobs: ${response.body}');
    }
  }

  Future<FreelancerJob> updateJob(int id, int freelancerId, String status) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/api/freelancer-jobs/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'freelancer_id': freelancerId,
        'status': status,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return FreelancerJob.fromJson(data['job']);
    } else {
      throw Exception('Failed to update job: ${response.body}');
    }
  }
}
