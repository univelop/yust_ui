import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:yust/yust.dart';

import '../widgets/yust_doc_builder.dart';
import '../widgets/yust_focus_handler.dart';
import '../widgets/yust_select.dart';
import '../widgets/yust_text_field.dart';
import '../yust_ui.dart';

class YustAccountEditScreen extends StatelessWidget {
  static const String routeName = '/accountEdit';
  static const bool signInRequired = true;

  final bool askForGender;

  const YustAccountEditScreen({Key? key, this.askForGender = false})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return YustFocusHandler(
      child: Scaffold(
        appBar: AppBar(title: const Text('Persönliche Daten')),
        body: YustDocBuilder<YustUser>(
            modelSetup: Yust.userSetup,
            id: Yust.authService.getCurrentUserId(),
            builder: (user, insights, context) {
              if (user == null) {
                return const Center(
                  child: Text('In Arbeit...'),
                );
              }
              return ListView(
                padding: const EdgeInsets.only(top: 20.0),
                children: <Widget>[
                  _buildGender(context, user),
                  YustTextField(
                    label: 'Vorname',
                    value: user.firstName,
                    validator: (value) {
                      if (value == null || value == '') {
                        return 'Es muss ein Vorname angegeben werden.';
                      } else {
                        return null;
                      }
                    },
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    onEditingComplete: (value) async {
                      user.firstName = value!; // value was checked by validator
                      await Yust.databaseService
                          .saveDoc<YustUser>(Yust.userSetup, user);
                    },
                  ),
                  YustTextField(
                    label: 'Nachname',
                    value: user.lastName,
                    validator: (value) {
                      if (value == null || value == '') {
                        return 'Es muss ein Nachname angegeben werden.';
                      } else {
                        return null;
                      }
                    },
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    onEditingComplete: (value) async {
                      user.lastName = value!; // value was checked by validator
                      await Yust.databaseService
                          .saveDoc<YustUser>(Yust.userSetup, user);
                    },
                  ),
                  YustTextField(
                    label: 'E-Mail',
                    value: user.email,
                    readOnly: true,
                    onTap: () => _changeEmail(context),
                  ),
                  YustTextField(
                    label: 'Passwort',
                    value: '*****',
                    obscureText: true,
                    readOnly: true,
                    onTap: () => _changePassword(context),
                  ),
                ],
              );
            }),
      ),
    );
  }

  Widget _buildGender(BuildContext context, YustUser user) {
    if (!askForGender) {
      return const SizedBox.shrink();
    }
    return YustSelect(
      label: 'Anrede',
      value: user.gender,
      optionValues: const [YustGender.male, YustGender.female],
      optionLabels: const ['Herr', 'Frau'],
      onSelected: (dynamic value) {
        user.gender = value;
        Yust.databaseService.saveDoc<YustUser>(Yust.userSetup, user);
      },
    );
  }

  void _changeEmail(BuildContext context) {
    String? email;
    String? password;
    showDialog<List<String>>(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          title: const Text('E-Mail ändern'),
          children: [
            YustTextField(
              label: 'Neue E-Mail Adresse',
              value: email,
              onChanged: (value) => email = value,
            ),
            YustTextField(
              label: 'Passwort zur Bestätigung',
              value: password,
              onChanged: (value) => password = value,
              obscureText: true,
            ),
            const SizedBox(height: 20.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  child: const Text('Abbrechen'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: Text(
                    'Speichern',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.secondary),
                  ),
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    try {
                      if (email == null || password == null) {
                        throw Exception(
                            'E-Mail oder Passwort dürfen nicht leer sein');
                      }
                      await EasyLoading.show(status: 'E-Mail wird geändert...');
                      await Yust.authService.changeEmail(email!, password!);
                      unawaited(EasyLoading.dismiss());

                      navigator.pop();
                      await YustUi.alertService.showAlert('E-Mail geändert',
                          'Deine E-Mail wurde erfolgreich geändert.');
                    } on PlatformException catch (err) {
                      unawaited(EasyLoading.dismiss());
                      navigator.pop();
                      await YustUi.alertService
                          .showAlert('Fehler', err.message!);
                    } catch (err) {
                      unawaited(EasyLoading.dismiss());
                      Navigator.of(context).pop();
                      await YustUi.alertService
                          .showAlert('Fehler', err.toString());
                    }
                  },
                ),
              ],
            )
          ],
        );
      },
    );
  }

  void _changePassword(BuildContext context) {
    String? newPassword;
    String? oldPassword;
    showDialog<List<String>>(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          title: const Text('Passwort ändern'),
          children: [
            YustTextField(
              label: 'Neues Passwort',
              value: newPassword,
              onChanged: (value) => newPassword = value,
              obscureText: true,
            ),
            YustTextField(
              label: 'Altes Passwort zur Bestätigung',
              value: oldPassword,
              onChanged: (value) => oldPassword = value,
              obscureText: true,
            ),
            const SizedBox(height: 20.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  child: const Text('Abbrechen'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: Text(
                    'Speichern',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.secondary),
                  ),
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    try {
                      if (newPassword == null || oldPassword == null) {
                        throw Exception(
                            'Es muss sowohl das alte, als auch das neue Passwort eingegeben werden');
                      }
                      await EasyLoading.show(
                          status: 'Passwort wird geändert...');
                      await Yust.authService
                          .changePassword(newPassword!, oldPassword!);
                      unawaited(EasyLoading.dismiss());
                      navigator.pop();
                      await YustUi.alertService.showAlert('Passwort geändert',
                          'Dein Passwort wurde erfolgreich geändert.');
                    } on PlatformException catch (err) {
                      unawaited(EasyLoading.dismiss());
                      navigator.pop();
                      await YustUi.alertService
                          .showAlert('Fehler', err.message!);
                    } catch (err) {
                      unawaited(EasyLoading.dismiss());
                      navigator.pop();
                      await YustUi.alertService
                          .showAlert('Fehler', err.toString());
                    }
                  },
                ),
              ],
            )
          ],
        );
      },
    );
  }
}
