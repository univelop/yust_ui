import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/extensions/string_translate_extension.dart';
import 'package:yust_ui/yust_ui.dart';

import '../dialogs/yust_location_dialog.dart';
import '../generated/locale_keys.g.dart';

/// Service to wrap calls to the geolocator and geocoding packages
///
/// Can be used to access the current devices position and more
///
/// Mostly works only on Android and iOS
class YustLocationService {
  final GlobalKey<NavigatorState> navStateKey;

  YustLocationService(this.navStateKey);

  /// Checks if the location services are enabled and if the app has the necessary permissions
  ///
  /// If not, asks the user to enable/give permissions to the location
  ///
  /// Returns true if the location services are enabled and the app has the necessary permissions, otherwise false
  Future<bool> checkPermissions() async {
    bool serviceEnabled;
    LocationPermission permission;
    YustAlertService alertService = YustAlertService(navStateKey);

    try {
      // Test if location services are enabled.
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await alertService.showAlert(
          LocaleKeys.locationServicesDisabled.tr(),
          LocaleKeys.pleaseEnableLocationServices.tr(),
        );

        return false;
      }

      // Check permissions of app
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          await alertService.showAlert(
            LocaleKeys.locationServicesDisabled.tr(),
            LocaleKeys.pleaseEnableLocationAccessForApp.tr(),
          );

          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        await alertService.showAlert(
          LocaleKeys.locationServicesDisabled.tr(),
          LocaleKeys.pleaseEnableLocationAccessForApp.tr(),
        );

        return false;
      }

      return true;
    } catch (e) {
      throw YustException(e.toString());
    }
  }

  /// Determine the current position of the device.
  ///
  /// When the location services are not enabled or permissions
  /// are denied the `Future` will return an error.
  Future<Position> getCurrentPosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled don't continue
      // accessing the position and request users of the
      // App to enable the location services.
      throw YustException('Location services are disabled');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied, next time you could try
        // requesting permissions again (this is also where
        // Android's shouldShowRequestPermissionRationale
        // returned true. According to Android guidelines
        // your App should show an explanatory UI now.
        throw YustException('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      throw YustException('Location permissions are permanently denied');
    }

    try {
      // When we reach here, permissions are granted and we can
      // continue accessing the position of the device.
      final position = await Geolocator.getCurrentPosition();

      return position;
    } catch (e) {
      throw YustException(e.toString());
    }
  }

  /// Determine the current location of the device.
  ///
  /// When the location services are not enabled or permissions
  /// are denied the `Future` will return an error.
  Future<YustGeoLocation> getCurrentLocation({bool loadAddress = true}) async {
    try {
      final position = await getCurrentPosition();

      YustAddress? address;
      if (loadAddress) {
        address = await getAddressFromCoordinates(
          position.latitude,
          position.longitude,
        );
      }

      return YustGeoLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        address: address,
      );
    } catch (e) {
      throw YustException(e.toString());
    }
  }

  /// According to the geocoding package, there are some rare cases in which the placemark lookup can return
  /// more than one result. If you need these additional results, you can use this method.
  ///
  /// Otherwise you should use [getAddressFromCoordinates] which returns only the first result.
  Future<List<YustAddress>> getAddressesFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      );

      return placemarks.map((placemark) {
        return YustAddress(
          city: placemark.locality,
          country: placemark.country,
          postcode: placemark.postalCode,
          street: placemark.thoroughfare,
          number: placemark.subThoroughfare,
        );
      }).toList();
    } catch (e) {
      throw YustException(e.toString());
    }
  }

  /// Returns the first address or null for the given coordinates.
  ///
  /// On rare occasions, there may be more than one placemark for the given coordinates.
  /// Use [getAddressesFromCoordinates] if you these.
  Future<YustAddress?> getAddressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    final addresses = await getAddressesFromCoordinates(latitude, longitude);
    return addresses.firstOrNull;
  }

  /// Returns true if there is a geocoder implementation present that may return results.
  /// If true, there is still no guarantee that any individual geocoding attempt will succeed.
  ///
  /// This method is only implemented on Android, calling this on iOS always
  /// returns [true].
  Future<bool> isGeocoderPresent() => isPresent();

  /// Opens a stream of the current device position and shows a dialog to the user.
  /// The user can then choose to accept the current position, wait for a better accuracy or cancel the dialog.
  /// The [locale] parameter can be used to set the locale of the dialog
  ///
  /// Returns the location the user accepted or null if the user canceled the dialog or no position was found
  ///
  /// Before calling this function, make sure to call [checkPermissions] to ensure that the location services are enabled and the app has the necessary permissions.
  Future<YustGeoLocation?> showLocationDialog({
    String? locale,
    bool loadAddress = true,
  }) async {
    try {
      final context = navStateKey.currentContext;
      if (context == null) {
        return Future.value();
      }

      final dialogResult = await showDialog<Position?>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return YustLocationDialog(
            locale: locale,
          );
        },
      );

      YustAddress? address;

      if (loadAddress && dialogResult != null) {
        address = await getAddressFromCoordinates(
          dialogResult.latitude,
          dialogResult.longitude,
        );
      }

      return YustGeoLocation(
        latitude: dialogResult?.latitude,
        longitude: dialogResult?.longitude,
        accuracy: dialogResult?.accuracy,
        address: address,
      );
    } catch (e) {
      throw YustException(e.toString());
    }
  }
}
