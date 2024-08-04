import 'package:flutter/material.dart';

class LocationLoadingIcon extends StatefulWidget {
  const LocationLoadingIcon({super.key});

  @override
  LocationLoadingIconState createState() => LocationLoadingIconState();
}

class LocationLoadingIconState extends State<LocationLoadingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: Icon(Icons.location_on,
          size: 50.0, color: Theme.of(context).primaryColor),
    );
  }
}
