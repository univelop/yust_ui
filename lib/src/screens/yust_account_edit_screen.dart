import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:yust/yust.dart';

import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';
import '../widgets/yust_doc_builder.dart';
import '../widgets/yust_focus_handler.dart';
import '../widgets/yust_select.dart';
import '../widgets/yust_text_field.dart';
import '../yust_ui.dart';

class YustAccountEditScreen extends StatelessWidget {
  static const String routeName = '/accountEdit';
  static const bool signInRequired = true;

  final bool askForGender;

  const YustAccountEditScreen({super.key, this.askForGender = false});

  @override
  Widget build(BuildContext context) {
    return YustFocusHandler(
      child: Scaffold(
        appBar: AppBar(title: Text(LocaleKeys.personalData.tr())),
        body: YustDocBuilder<YustUser>(
            modelSetup: Yust.userSetup,
            id: Yust.authService.getCurrentUserId(),
            builder: (user, insights, context) {
              if (user == null) {
                return Center(
                  child: Text(LocaleKeys.inProgress.tr()),
                );
              }
              return ListView(
                padding: const EdgeInsets.only(top: 20.0),
                children: <Widget>[
                  _buildGender(context, user),
                  YustTextField(
                    label: LocaleKeys.firstName.tr(),
                    value: user.firstName,
                    validator: (value) {
                      if (value == null || value == '') {
                        return LocaleKeys.validationFirstName.tr();
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
                    label: LocaleKeys.lastName.tr(),
                    value: user.lastName,
                    validator: (value) {
                      if (value == null || value == '') {
                        return LocaleKeys.validationLastName.tr();
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
                  ..._buildAuthenticationMethod(user, context),
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
      label: LocaleKeys.salutation.tr(),
      value: user.gender,
      optionValues: const [YustGender.male, YustGender.female],
      optionLabels: [
        LocaleKeys.salutationMale.tr(),
        LocaleKeys.salutationFemale.tr()
      ],
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
          title: Text(LocaleKeys.changeEmail.tr()),
          children: [
            YustTextField(
              label: LocaleKeys.newEmailAddress.tr(),
              value: email,
              onChanged: (value) => email = value,
            ),
            YustTextField(
              label: LocaleKeys.confirmedPassword.tr(),
              value: password,
              onChanged: (value) => password = value,
              obscureText: true,
            ),
            const SizedBox(height: 20.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  child: Text(LocaleKeys.cancel.tr()),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: Text(
                    LocaleKeys.save.tr(),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.secondary),
                  ),
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    try {
                      if (email == null || password == null) {
                        throw Exception(
                            LocaleKeys.exceptionMissingEmailOrPassword.tr());
                      }
                      await EasyLoading.show(
                          status: LocaleKeys.changingEmail.tr());
                      await Yust.authService.changeEmail(email!, password!);
                      unawaited(EasyLoading.dismiss());

                      navigator.pop();
                      await YustUi.alertService.showAlert(
                          LocaleKeys.changedEmail.tr(),
                          LocaleKeys.alertChangedEmail.tr());
                    } on PlatformException catch (err) {
                      unawaited(EasyLoading.dismiss());
                      navigator.pop();
                      await YustUi.alertService
                          .showAlert(LocaleKeys.error.tr(), err.message!);
                    } catch (err) {
                      unawaited(EasyLoading.dismiss());
                      navigator.pop();
                      await YustUi.alertService
                          .showAlert(LocaleKeys.error.tr(), err.toString());
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

  List<Widget> _buildAuthenticationMethod(YustUser user, BuildContext context) {
    final authMethod = user.authenticationMethod;
    if (authMethod == null || authMethod == YustAuthenticationMethod.mail) {
      return [
        YustTextField(
          label: LocaleKeys.email.tr(),
          value: user.email,
          readOnly: true,
          onTap: () => _changeEmail(context),
        ),
        YustTextField(
          label: LocaleKeys.password.tr(),
          value: '*****',
          obscureText: true,
          readOnly: true,
          onTap: () => _changePassword(context),
        )
      ];
    }
    return [
      YustTextField(
        label: LocaleKeys.signInVia.tr(),
        value: authMethod.label,
        readOnly: true,
      )
    ];
  }

  void _changePassword(BuildContext context) {
    String? newPassword;
    String? oldPassword;
    showDialog<List<String>>(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          title: Text(LocaleKeys.changePassword.tr()),
          children: [
            YustTextField(
              label: LocaleKeys.newPassword.tr(),
              value: newPassword,
              onChanged: (value) => newPassword = value,
              obscureText: true,
            ),
            YustTextField(
              label: LocaleKeys.oldPassword.tr(),
              value: oldPassword,
              onChanged: (value) => oldPassword = value,
              obscureText: true,
            ),
            const SizedBox(height: 20.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  child: Text(LocaleKeys.cancel.tr()),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: Text(
                    LocaleKeys.save.tr(),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.secondary),
                  ),
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    try {
                      if (newPassword == null || oldPassword == null) {
                        throw Exception(
                            LocaleKeys.exceptionMissingNewOrOldPassword.tr());
                      }
                      await EasyLoading.show(
                          status: LocaleKeys.changingPassword.tr());
                      await Yust.authService
                          .changePassword(newPassword!, oldPassword!);
                      unawaited(EasyLoading.dismiss());
                      navigator.pop();
                      await YustUi.alertService.showAlert(
                          LocaleKeys.changedPassword.tr(),
                          LocaleKeys.alertChangedPassword.tr());
                    } on PlatformException catch (err) {
                      unawaited(EasyLoading.dismiss());
                      navigator.pop();
                      await YustUi.alertService
                          .showAlert(LocaleKeys.error.tr(), err.message!);
                    } catch (err) {
                      unawaited(EasyLoading.dismiss());
                      navigator.pop();
                      await YustUi.alertService
                          .showAlert(LocaleKeys.error.tr(), err.toString());
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
