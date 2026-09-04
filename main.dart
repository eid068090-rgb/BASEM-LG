import 'package:flutter/material.dart';

void main() {
  runApp(const AlsamanApp());
}

class AlsamanApp extends StatelessWidget {
  const AlsamanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ALSAMAN',
      home: Scaffold(
        appBar: AppBar(title: const Text('ALSAMAN')),
        body: const Center(
          child: Text(
            'ALSAMAN\n'
            'Network discovery engine is implemented in the native Android module.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
