import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:yust_ui/src/widgets/yust_pulsating_icon.dart';
import 'package:yust_ui/src/extensions/string_translate_extension.dart';

import '../generated/locale_keys.g.dart';

class YustLocationDialog extends StatefulWidget {
  final String? locale;

  const YustLocationDialog({super.key, this.locale});

  @override
  YustLocationDialogState createState() => YustLocationDialogState();
}

class YustLocationDialogState extends State<YustLocationDialog> {
  StreamSubscription<Position>? _positionStreamSubscription;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _positionStreamSubscription =
        Geolocator.getPositionStream().handleError((error) {
      _positionStreamSubscription?.cancel();
      _positionStreamSubscription = null;
    }).listen((position) {
      setState(() {
        _currentPosition = position;
      });
    });
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _currentPosition = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(30.0),
              child: Text(
                _currentPosition == null
                    ? LocaleKeys.loadingLocation.tr()
                    : LocaleKeys.locationFound.tr(),
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ),
          ),
          const YustPulsatingIcon(
            iconData: Icons.location_on,
          ),
          const SizedBox(height: 5),
          _currentPosition == null
              ? Transform.scale(
                  scale: 0.7,
                  child: const CircularProgressIndicator(),
                )
              : Column(
                  children: [
                    Text(LocaleKeys.accuracy.tr()),
                    Text(
                        '${NumberFormat('0.##', widget.locale).format(_currentPosition?.accuracy)} ${LocaleKeys.meters.tr()}')
                  ],
                ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          child: Text(LocaleKeys.cancel.tr()),
          onPressed: () {
            Navigator.of(context).pop(null);
          },
        ),
        TextButton(
          onPressed: _currentPosition == null
              ? null
              : () {
                  Navigator.of(context).pop(_currentPosition);
                },
          child: Text(LocaleKeys.ok.tr()),
        ),
      ],
    );
  }
}
