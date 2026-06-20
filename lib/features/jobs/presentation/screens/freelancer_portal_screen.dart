import 'package:flutter/material.dart';

class FreelancerPortalScreen extends StatefulWidget {
  const FreelancerPortalScreen({super.key, required this.token});
  final String token;

  @override
  State<FreelancerPortalScreen> createState() => _FreelancerPortalScreenState();
}

class _FreelancerPortalScreenState extends State<FreelancerPortalScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Freelancer Portal'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.account_balance_wallet, size: 64, color: Colors.blue),
              const SizedBox(height: 16),
              const Text(
                'Your Balance: ₹ 4,500',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Recent Jobs',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: const [
                    ListTile(
                      leading: Icon(Icons.check_circle, color: Colors.green),
                      title: Text('Item #12 - Assembled 50 units'),
                      subtitle: Text('Paid: ₹ 500'),
                    ),
                    ListTile(
                      leading: Icon(Icons.check_circle, color: Colors.green),
                      title: Text('Item #8 - Assembled 100 units'),
                      subtitle: Text('Paid: ₹ 1000'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
