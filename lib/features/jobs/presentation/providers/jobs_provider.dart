import 'package:flutter/foundation.dart';
import '../../data/jobs_repository.dart';
import '../../domain/freelancer_job.dart';

class JobsProvider extends ChangeNotifier {
  JobsProvider({required this.repository});
  final JobsRepository repository;

  List<FreelancerJob> _jobs = [];
  bool _isLoading = false;
  String? _error;

  List<FreelancerJob> get jobs => _jobs;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchJobs() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _jobs = await repository.getJobs();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateJob(int id, int freelancerId, String status) async {
    try {
      final updatedJob = await repository.updateJob(id, freelancerId, status);
      final index = _jobs.indexWhere((j) => j.id == id);
      if (index != -1) {
        _jobs[index] = updatedJob;
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }
}
