import 'package:flutter/material.dart';
import '../widgets/responsive_layout.dart';

class FlightBookScreen extends StatelessWidget {
  const FlightBookScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ResponsiveContainer(
      child: Center(
        child: Text(
          'Flight Book Screen',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
    );
  }
}
