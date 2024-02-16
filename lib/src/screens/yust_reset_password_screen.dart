import 'package:flutter/material.dart';
import 'package:yust/yust.dart';

import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';
import '../widgets/yust_focus_handler.dart';
import '../widgets/yust_progress_button.dart';
import '../yust_ui.dart';

class YustResetPasswordScreen extends StatefulWidget {
  static const String routeName = '/resetPassword';
  static const bool signInRequired = false;

  final String? logoAssetName;

  const YustResetPasswordScreen({super.key, this.logoAssetName});

  @override
  State<YustResetPasswordScreen> createState() =>
      _YustResetPasswordScreenState();
}

class _YustResetPasswordScreenState extends State<YustResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _email;

  @override
  Widget build(BuildContext context) {
    return YustFocusHandler(
      child: Scaffold(
        appBar: AppBar(
          title: Text(LocaleKeys.forgotPassword.tr()),
        ),
        body: SingleChildScrollView(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
              padding: const EdgeInsets.only(top: 40.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: <Widget>[
                    _buildLogo(context),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20.0, vertical: 10.0),
                      child: TextFormField(
                        decoration: InputDecoration(
                          labelText: LocaleKeys.email.tr(),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value == '') {
                            return LocaleKeys.validationEmail.tr();
                          }
                          return null;
                        },
                        onChanged: (value) => _email = value.trim(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20.0, vertical: 10.0),
                      child: YustProgressButton(
                        color: Theme.of(context).colorScheme.secondary,
                        onPressed: () async {
                          if (_formKey.currentState!.validate()) {
                            final navigator = Navigator.of(context);
                            try {
                              await Yust.authService
                                  .sendPasswordResetEmail(_email!);
                              navigator.pop();
                              await YustUi.alertService.showAlert(
                                  LocaleKeys.sentResetEmail.tr(),
                                  LocaleKeys.alertSentResetEmail.tr());
                            } catch (err) {
                              await YustUi.alertService.showAlert(
                                  LocaleKeys.error.tr(), err.toString());
                            }
                          }
                        },
                        child: Text(LocaleKeys.forgotPassword.tr(),
                            style: const TextStyle(
                                fontSize: 20.0, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo(BuildContext context) {
    if (widget.logoAssetName == null) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 200,
      child: Center(
        child: Image.asset(widget.logoAssetName!),
      ),
    );
  }
}
