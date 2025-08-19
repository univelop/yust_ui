import 'package:flutter/material.dart';
import 'package:yust/yust.dart';

import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';
import '../widgets/yust_doc_builder.dart';
import 'yust_account_edit_screen.dart';

class YustAccountScreen extends StatelessWidget {
  const YustAccountScreen({super.key});

  static const String routeName = '/account';
  static const bool signInRequired = true;

  @override
  Widget build(BuildContext context) {
    return YustDocBuilder<YustUser>(
      modelSetup: Yust.userSetup,
      id: Yust.authService.getCurrentUserId(),
      builder: (user, insights, context) {
        if (user == null) {
          return Scaffold(
            body: Center(
              child: Text(LocaleKeys.inProgress.tr()),
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(LocaleKeys.account.tr())),
          body: ListView(
            padding: const EdgeInsets.only(top: 20.0),
            children: <Widget>[
              Container(
                padding: const EdgeInsets.only(bottom: 20.0),
                child: Column(
                  children: <Widget>[
                    Icon(
                      Icons.person,
                      color: Theme.of(context).colorScheme.secondary,
                      size: 100.0,
                    ),
                    Text(
                      '${user.firstName} ${user.lastName}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.secondary,
                        fontSize: 20.0,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(thickness: 1.0),
              ListTile(
                leading: Icon(
                  Icons.person,
                  color: Theme.of(context).colorScheme.secondary,
                  size: 40.0,
                ),
                title: Text(
                  LocaleKeys.personalData.tr(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
                onTap: () {
                  Navigator.pushNamed(context, YustAccountEditScreen.routeName);
                },
              ),
              const Divider(thickness: 1.0),
              ListTile(
                leading: Icon(
                  Icons.power_settings_new,
                  color: Theme.of(context).colorScheme.secondary,
                  size: 40.0,
                ),
                title: Text(
                  LocaleKeys.signOut.tr(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
                onTap: () {
                  Yust.authService.signOut();
                },
              ),
              const Divider(thickness: 1.0),
            ],
          ),
        );
      },
    );
  }
}
