import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/jobs_provider.dart';
import 'package:core_erp/features/departments/presentation/providers/departments_provider.dart';
import 'package:core_erp/features/departments/domain/employee_definition.dart';
import '../../domain/freelancer_job.dart';

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<JobsProvider>().fetchJobs();
      context.read<DepartmentsProvider>().load();
    });
  }

  void _callFreelancer(BuildContext context, EmployeeDefinition freelancer, FreelancerJob job) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Call Freelancer'),
        content: Text('Please call ${freelancer.name} at ${freelancer.phone} to pick up ${job.count} items for assembly.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jobsProvider = context.watch<JobsProvider>();
    final deptProvider = context.watch<DepartmentsProvider>();

    if (jobsProvider.isLoading || deptProvider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final freelancers = deptProvider.employees.where((e) => e.employmentType == 'freelancer').toList();
    final jobs = jobsProvider.jobs;

    final unassignedJobs = jobs.where((j) => j.freelancerId == 0).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Freelancer Jobs Board'),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Unassigned Pool Column
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Unassigned Pool', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: unassignedJobs.length,
                      itemBuilder: (context, index) {
                        final job = unassignedJobs[index];
                        return Draggable<FreelancerJob>(
                          data: job,
                          feedback: Material(
                            elevation: 4,
                            child: _JobCard(job: job),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.5,
                            child: _JobCard(job: job),
                          ),
                          child: _JobCard(job: job),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Freelancers Columns (Assigned)
          ...freelancers.map((freelancer) {
            final assignedJobs = jobs.where((j) => j.freelancerId == freelancer.id).toList();
            return Expanded(
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: DragTarget<FreelancerJob>(
                  onAcceptWithDetails: (details) {
                    final job = details.data;
                    context.read<JobsProvider>().updateJob(job.id, freelancer.id, 'in-assembly');
                    _callFreelancer(context, freelancer, job);
                  },
                  builder: (context, candidateData, rejectedData) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(freelancer.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text(freelancer.phone, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: Container(
                            color: candidateData.isNotEmpty ? Colors.blue.withValues(alpha: 0.1) : null,
                            child: ListView.builder(
                              itemCount: assignedJobs.length,
                              itemBuilder: (context, index) {
                                final job = assignedJobs[index];
                                return _JobCard(job: job);
                              },
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});
  final FreelancerJob job;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Item #${job.itemId}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Count: ${job.count}'),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: job.status == 'pending' ? Colors.orange[100] : Colors.blue[100],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                job.status.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  color: job.status == 'pending' ? Colors.orange[900] : Colors.blue[900],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
