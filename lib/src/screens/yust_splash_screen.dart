import 'package:flutter/material.dart';

class YustSplashScreen extends StatelessWidget {
  static const String routeName = '/splash';
  static const bool signInRequired = false;

  const YustSplashScreen({super.key, this.appName});

  final String? appName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(appName ?? '')),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}
