import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yust/yust.dart';

import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';
import '../widgets/yust_focus_handler.dart';
import '../widgets/yust_progress_button.dart';
import '../widgets/yust_select.dart';
import '../yust_ui.dart';
import 'yust_sign_in_screen.dart';

class YustSignUpScreen extends StatefulWidget {
  static const String routeName = '/signUp';
  static const bool signInRequired = false;

  final String homeRouteName;
  final String? logoAssetName;
  final bool askForGender;

  const YustSignUpScreen({
    super.key,
    this.homeRouteName = '/',
    this.logoAssetName,
    this.askForGender = false,
  });

  @override
  State<YustSignUpScreen> createState() => _YustSignUpScreenState();
}

class _YustSignUpScreenState extends State<YustSignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  YustGender? _gender;
  String? _firstName;
  String? _lastName;
  String? _email;
  String? _password;
  bool _waitingForSignUp = false;
  void Function()? _onSignedIn;

  final _firstNameFocus = FocusNode();
  final _lastNameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _passwordConfirmationFocus = FocusNode();

  final ScrollController _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    final arguments = ModalRoute.of(context)!.settings.arguments;
    if (arguments is Map) {
      _onSignedIn = arguments['onSignedIn'];
    }

    return YustFocusHandler(
      child: Scaffold(
        appBar: AppBar(
          title: Text(LocaleKeys.registration.tr()),
        ),
        body: SingleChildScrollView(
          controller: _scrollController,
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
              padding: const EdgeInsets.only(top: 40.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: <Widget>[
                    _buildLogo(context),
                    _buildGender(context),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20.0, vertical: 10.0),
                      child: TextFormField(
                        decoration: InputDecoration(
                          labelText: LocaleKeys.firstName.tr(),
                          border: const OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.words,
                        focusNode: _firstNameFocus,
                        onChanged: (value) => _firstName = value.trim(),
                        validator: (value) {
                          if (value == null || value == '') {
                            return LocaleKeys.validationFirstName.tr();
                          }
                          return null;
                        },
                        onFieldSubmitted: (value) {
                          _firstNameFocus.unfocus();
                          FocusScope.of(context).requestFocus(_lastNameFocus);
                          _scrollController.animateTo(
                              _scrollController.offset + 80,
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.ease);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20.0, vertical: 10.0),
                      child: TextFormField(
                        decoration: InputDecoration(
                          labelText: LocaleKeys.lastName.tr(),
                          border: const OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.words,
                        focusNode: _lastNameFocus,
                        onChanged: (value) => _lastName = value.trim(),
                        validator: (value) {
                          if (value == null || value == '') {
                            return LocaleKeys.validationLastName.tr();
                          }
                          return null;
                        },
                        onFieldSubmitted: (value) {
                          _firstNameFocus.unfocus();
                          FocusScope.of(context).requestFocus(_emailFocus);
                          _scrollController.animateTo(
                              _scrollController.offset + 80,
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.ease);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20.0, vertical: 10.0),
                      child: TextFormField(
                        decoration: InputDecoration(
                          labelText: LocaleKeys.email.tr(),
                          border: const OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.next,
                        keyboardType: TextInputType.emailAddress,
                        textCapitalization: TextCapitalization.none,
                        focusNode: _emailFocus,
                        onChanged: (value) => _email = value.trim(),
                        validator: (value) {
                          if (value == null || value == '') {
                            return LocaleKeys.validationEmail.tr();
                          }
                          return null;
                        },
                        onFieldSubmitted: (value) {
                          _emailFocus.unfocus();
                          FocusScope.of(context).requestFocus(_passwordFocus);
                          _scrollController.animateTo(
                              _scrollController.offset + 80,
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.ease);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20.0, vertical: 10.0),
                      child: TextFormField(
                        decoration: InputDecoration(
                          labelText: LocaleKeys.password.tr(),
                          border: const OutlineInputBorder(),
                        ),
                        obscureText: true,
                        textInputAction: TextInputAction.next,
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
                          FocusScope.of(context)
                              .requestFocus(_passwordConfirmationFocus);
                          await _scrollController.animateTo(
                              _scrollController.offset + 80,
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.ease);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20.0, vertical: 10.0),
                      child: TextFormField(
                        decoration: InputDecoration(
                          labelText: LocaleKeys.confirmPassword.tr(),
                          border: const OutlineInputBorder(),
                        ),
                        obscureText: true,
                        textInputAction: TextInputAction.send,
                        focusNode: _passwordConfirmationFocus,
                        validator: (value) {
                          if (value == null || value == '') {
                            return LocaleKeys.validationPasswordConfirmation
                                .tr();
                          }
                          if (_password != value) {
                            return LocaleKeys
                                .validationPasswordConfirmationWrong
                                .tr();
                          }
                          return null;
                        },
                        onFieldSubmitted: (value) async {
                          _passwordConfirmationFocus.unfocus();
                          setState(() {
                            _waitingForSignUp = true;
                          });
                          await _signUp(context);
                          setState(() {
                            _waitingForSignUp = false;
                          });
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20.0, vertical: 10.0),
                      child: YustProgressButton(
                        color: Theme.of(context).colorScheme.secondary,
                        inProgress: _waitingForSignUp,
                        onPressed: () => _signUp(context),
                        child: Text(LocaleKeys.register.tr(),
                            style: const TextStyle(
                                fontSize: 20.0, color: Colors.white)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                          left: 20.0, top: 40.0, right: 20.0, bottom: 10.0),
                      child: Text(LocaleKeys.alreadyRegistered.tr(),
                          style: const TextStyle(fontSize: 16.0)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20.0, vertical: 10.0),
                      child: TextButton(
                        onPressed: () {
                          Navigator.pushNamed(
                              context, YustSignInScreen.routeName,
                              arguments: arguments);
                        },
                        child: Text(LocaleKeys.signIn.tr(),
                            style: TextStyle(
                                fontSize: 20.0,
                                color: Theme.of(context).primaryColor)),
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

  Widget _buildGender(BuildContext context) {
    if (!widget.askForGender) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
      child: YustSelect(
        label: LocaleKeys.salutation.tr(),
        value: _gender,
        optionValues: const [YustGender.male, YustGender.female],
        optionLabels: [
          LocaleKeys.salutationMale.tr(),
          LocaleKeys.salutationFemale.tr()
        ],
        onSelected: (dynamic value) {
          setState(() {
            _gender = value;
          });
        },
        style: YustInputStyle.outlineBorder,
      ),
    );
  }

  Future<void> _signUp(BuildContext context) async {
    if (_formKey.currentState!.validate()) {
      try {
        await Yust.authService
            .signUp(
              _firstName!,
              _lastName!,
              _email!,
              _password!,
              gender: _gender,
            )
            .timeout(const Duration(seconds: 10));
        if (_onSignedIn != null) _onSignedIn!();
      } on YustException catch (err) {
        await YustUi.alertService.showAlert(LocaleKeys.error.tr(), err.message);
      } on PlatformException catch (err) {
        await YustUi.alertService
            .showAlert(LocaleKeys.error.tr(), err.message!);
      } on TimeoutException catch (_) {
        await YustUi.alertService.showAlert(
          LocaleKeys.error.tr(),
          LocaleKeys.timeout.tr(),
        );
      } catch (err) {
        await YustUi.alertService
            .showAlert(LocaleKeys.error.tr(), err.toString());
      }
    }
  }
}
