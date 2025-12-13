import 'package:flutter/material.dart';
import '../widgets/responsive_layout.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ResponsiveContainer(
      child: Center(
        child: Text(
          'Dashboard Screen',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
    );
  }
}
