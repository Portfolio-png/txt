import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/freelancer_job.dart';

class JobsData {
  JobsData({required this.batches, required this.jobs, required this.tasks});

  final List<FreelancerJobBatch> batches;
  final List<FreelancerJob> jobs;
  final List<FreelancerJobTask> tasks;
}

class JobsRepository {
  JobsRepository({http.Client? client, this.baseUrl = 'http://localhost:18080'})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<JobsData> getJobsData() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/freelancer-jobs'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final batchesList = data['batches'] as List;
      final jobsList = data['jobs'] as List;
      final tasksList = data['tasks'] as List;

      return JobsData(
        batches: batchesList
            .map((e) => FreelancerJobBatch.fromJson(e))
            .toList(),
        jobs: jobsList.map((e) => FreelancerJob.fromJson(e)).toList(),
        tasks: tasksList.map((e) => FreelancerJobTask.fromJson(e)).toList(),
      );
    } else {
      throw Exception('Failed to fetch jobs data: ${response.body}');
    }
  }

  Future<FreelancerJobBatch> createBatch(
    int freelancerId,
    List<int> jobIds,
  ) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/freelancer-jobs/batches'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'freelancer_id': freelancerId, 'job_ids': jobIds}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return FreelancerJobBatch.fromJson(data['batch']);
    } else {
      throw Exception('Failed to create batch: ${response.body}');
    }
  }

  Future<FreelancerJob> createJob(int itemId, int quantity) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/freelancer-jobs'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'item_id': itemId, 'quantity': quantity}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return FreelancerJob.fromJson(data['job']);
    } else {
      throw Exception('Failed to create job: ${response.body}');
    }
  }

  Future<FreelancerJob> updateJobStatus(int id, String status) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/api/freelancer-jobs/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'status': status}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return FreelancerJob.fromJson(data['job']);
    } else {
      throw Exception('Failed to update job status: ${response.body}');
    }
  }
}
