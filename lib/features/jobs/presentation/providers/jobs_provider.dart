import 'package:flutter/foundation.dart';
import '../../data/jobs_repository.dart';
import '../../domain/freelancer_job.dart';

class JobsProvider extends ChangeNotifier {
  JobsProvider({required this.repository});
  final JobsRepository repository;

  List<FreelancerJobBatch> _batches = [];
  List<FreelancerJob> _jobs = [];
  List<FreelancerJobTask> _tasks = [];
  bool _isLoading = false;
  String? _error;

  List<FreelancerJobBatch> get batches => _batches;
  List<FreelancerJob> get jobs => _jobs;
  List<FreelancerJobTask> get tasks => _tasks;

  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchJobsData() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await repository.getJobsData();
      _batches = data.batches;
      _jobs = data.jobs;
      _tasks = data.tasks;
    } catch (e) {
      _error = e.toString().replaceAll(RegExp(r'^(Exception:\s*)+'), '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createBatchAndAssign(int freelancerId, List<int> jobIds) async {
    try {
      final batch = await repository.createBatch(freelancerId, jobIds);
      _batches.add(batch);
      for (final id in jobIds) {
        final index = _jobs.indexWhere((j) => j.id == id);
        if (index != -1) {
          _jobs[index] = _jobs[index].copyWith(batchId: batch.id);
        }
      }
      notifyListeners();
    } catch (e) {
      _error = e.toString().replaceAll(RegExp(r'^(Exception:\s*)+'), '');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> createJob(int itemId, int quantity) async {
    try {
      final job = await repository.createJob(itemId, quantity);
      _jobs.add(job);
      notifyListeners();
    } catch (e) {
      _error = e.toString().replaceAll(RegExp(r'^(Exception:\s*)+'), '');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateJobStatus(int id, String status) async {
    try {
      final updatedJob = await repository.updateJobStatus(id, status);
      final index = _jobs.indexWhere((j) => j.id == id);
      if (index != -1) {
        _jobs[index] = updatedJob;
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString().replaceAll(RegExp(r'^(Exception:\s*)+'), '');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteJob(int id) async {
    try {
      await repository.deleteJob(id);
      _jobs.removeWhere((j) => j.id == id);
      notifyListeners();
    } catch (e) {
      _error = e.toString().replaceAll(RegExp(r'^(Exception:\s*)+'), '');
      notifyListeners();
      rethrow;
    }
  }
}
