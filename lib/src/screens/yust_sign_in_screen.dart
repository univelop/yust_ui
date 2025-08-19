import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yust/yust.dart';

import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';
import '../widgets/yust_focus_handler.dart';
import '../widgets/yust_progress_button.dart';
import '../yust_ui.dart';
import 'yust_reset_password_screen.dart';
import 'yust_sign_up_screen.dart';

class YustSignInScreen extends StatefulWidget {
  static const String routeName = '/signIn';
  static const bool signInRequired = false;

  final String? logoAssetName;

  const YustSignInScreen({
    super.key,
    this.logoAssetName,
  });

  @override
  State<YustSignInScreen> createState() => _YustSignInScreenState();
}

class _YustSignInScreenState extends State<YustSignInScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _email;
  String? _password;
  bool _waitingForSignIn = false;
  void Function()? _onSignedIn;

  final _emailController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  @override
  void initState() {
    SharedPreferences.getInstance().then((preferences) {
      _email = preferences.getString('email');
      if (_email != null) {
        _emailController.text = _email!;
      }
    });

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final arguments = ModalRoute.of(context)!.settings.arguments;
    if (arguments is Map) {
      _onSignedIn = arguments['onSignedIn'];
    }

    return YustFocusHandler(
      child: Scaffold(
        appBar: AppBar(
          title: Text(LocaleKeys.login.tr()),
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
                        horizontal: 20.0,
                        vertical: 10.0,
                      ),
                      child: TextFormField(
                        key: const Key('email'),
                        controller: _emailController,
                        decoration: InputDecoration(
                          labelText: LocaleKeys.email.tr(),
                          border: const OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.next,
                        keyboardType: TextInputType.emailAddress,
                        focusNode: _emailFocus,
                        onChanged: (value) => _email = value.trim(),
                        onFieldSubmitted: (value) {
                          _emailFocus.unfocus();
                          FocusScope.of(context).requestFocus(_passwordFocus);
                        },
                        validator: (value) {
                          if (value == null || value == '') {
                            return LocaleKeys.validationEmail.tr();
                          } else {
                            return null;
                          }
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20.0,
                        vertical: 10.0,
                      ),
                      child: TextFormField(
                        key: const Key('password'),
                        decoration: InputDecoration(
                          labelText: LocaleKeys.password.tr(),
                          border: const OutlineInputBorder(),
                        ),
                        obscureText: true,
                        textInputAction: TextInputAction.send,
                        focusNode: _passwordFocus,
                        onChanged: (value) => _password = value.trim(),
                        validator: (value) {
                          if (value == null || value == '') {
                            return LocaleKeys.validationPassword.tr();
                          }
                          return null;
                        },
                        onFieldSubmitted: (value) async {
                          _passwordFocus.unfocus();
                          setState(() {
                            _waitingForSignIn = true;
                          });
                          await _signIn(context);
                          setState(() {
                            _waitingForSignIn = false;
                          });
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20.0,
                        vertical: 10.0,
                      ),
                      child: YustProgressButton(
                        key: const Key('signInButton'),
                        color: Theme.of(context).colorScheme.secondary,
                        inProgress: _waitingForSignIn,
                        onPressed: () => _signIn(context),
                        child: Text(
                          LocaleKeys.signIn.tr(),
                          style: const TextStyle(
                            fontSize: 20.0,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 20.0,
                        top: 40.0,
                        right: 20.0,
                        bottom: 10.0,
                      ),
                      child: Text(
                        LocaleKeys.noAccount.tr(),
                        style: const TextStyle(fontSize: 16.0),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20.0,
                        vertical: 10.0,
                      ),
                      child: TextButton(
                        onPressed: () {
                          Navigator.pushNamed(
                            context,
                            YustSignUpScreen.routeName,
                            arguments: arguments,
                          );
                        },
                        child: Text(
                          LocaleKeys.registerNow.tr(),
                          style: TextStyle(
                            fontSize: 20.0,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20.0,
                        vertical: 10.0,
                      ),
                      child: TextButton(
                        onPressed: () {
                          Navigator.pushNamed(
                            context,
                            YustResetPasswordScreen.routeName,
                          );
                        },
                        child: Text(
                          LocaleKeys.forgotPassword.tr(),
                          style: TextStyle(
                            fontSize: 20.0,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
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

  Future<void> _signIn(BuildContext context) async {
    if (_formKey.currentState!.validate()) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('email', _email!);
      try {
        await Yust.authService
            .signIn(_email!, _password!)
            .timeout(const Duration(seconds: 10));
        if (_onSignedIn != null) _onSignedIn!();
      } on YustException catch (err) {
        await YustUi.alertService.showAlert(LocaleKeys.error.tr(), err.message);
      } on PlatformException catch (err) {
        await YustUi.alertService.showAlert(
          LocaleKeys.error.tr(),
          err.message!,
        );
      } on TimeoutException catch (_) {
        await YustUi.alertService.showAlert(
          LocaleKeys.error.tr(),
          LocaleKeys.timeout.tr(),
        );
      } catch (err) {
        await YustUi.alertService.showAlert(
          LocaleKeys.error.tr(),
          err.toString(),
        );
      }
    }
  }
}
