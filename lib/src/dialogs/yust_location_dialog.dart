import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:yust_ui/src/dialogs/location_loading_icon.dart';
import 'package:yust_ui/src/extensions/string_translate_extension.dart';

import '../generated/locale_keys.g.dart';

class YustLocationDialog extends StatefulWidget {
  final Stream<Position> positionStream;
  final String? locale;

  const YustLocationDialog(
      {super.key, required this.positionStream, this.locale});

  @override
  YustLocationDialogState createState() => YustLocationDialogState();
}

class YustLocationDialogState extends State<YustLocationDialog> {
  late StreamSubscription<Position>? _positionStreamSubscription;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _positionStreamSubscription = widget.positionStream.handleError((error) {
      _positionStreamSubscription?.cancel();
      _positionStreamSubscription = null;
    }).listen((position) {
      // Don't update if the new position is less accurate than the current one
      if (_currentPosition != null &&
          position.accuracy >= _currentPosition!.accuracy) return;

      setState(() {
        _currentPosition = position;
      });
    });
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
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
          const LocationLoadingIcon(),
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
          child: Text(LocaleKeys.ok.tr()),
          onPressed: () {
            Navigator.of(context).pop(_currentPosition);
          },
        ),
      ],
    );
  }
}
