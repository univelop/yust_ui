import 'package:flutter/material.dart';
import 'package:yust_ui/src/services/yust_alert_result.dart';
import 'package:yust_ui/src/widgets/yust_select_form.dart';

import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';
import '../widgets/yust_select.dart';

class YustAlertService {
  final GlobalKey<NavigatorState> navStateKey;

  YustAlertService(this.navStateKey);

  Future<void> showAlert(String title, String message) {
    return showAlertWithCustomActions(
      title: title,
      message: message,
      actionBuilder: (context) => [
        TextButton(
          autofocus: true,
          child: Text(LocaleKeys.ok.tr()),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  Future<void> showAlertWithCustomActions({
    required String title,
    required String message,
    required List<Widget> Function(BuildContext) actionBuilder,
  }) {
    final context = navStateKey.currentContext;
    if (context == null) return Future.value();
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: actionBuilder(context),
        );
      },
    );
  }

  Future<void> showCustomAlert({
    required Widget Function(BuildContext) content,
    bool dismissible = true,
  }) async {
    final context = navStateKey.currentContext;
    if (context == null) return Future.value();
    return showDialog<void>(
      context: context,
      barrierDismissible: dismissible,
      builder: (BuildContext context) {
        return content.call(context);
      },
    );
  }

  Future<bool?> showConfirmation(
    String title,
    String action, {
    String? cancelText,
    String? description,
  }) {
    final context = navStateKey.currentContext;
    if (context == null) return Future.value();
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: description != null ? Text(description) : null,
          actions: <Widget>[
            TextButton(
              child: Text(cancelText ?? LocaleKeys.cancel.tr()),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            TextButton(
              key: Key(action),
              autofocus: true,
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: Text(action),
            ),
          ],
        );
      },
    );
  }

  Future<T?> showSelectDialog<T>({
    required List<T> optionValues,
    required List<String> optionLabels,
    String? label,
    List<Widget> prefixWidgets = const [],
  }) {
    final context = navStateKey.currentContext;
    if (context == null) return Future.value();
    final selectedValues = <T>[];
    return showDialog<T?>(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: const EdgeInsets.only(top: 16, bottom: 24),
        title: label == null
            ? null
            : Text(
                LocaleKeys.selectValue.tr(namedArgs: {'label': label}),
              ),
        content: YustSelectForm(
          selectedValues: selectedValues,
          optionValues: optionValues,
          optionLabels: optionLabels,
          prefixWidgets: prefixWidgets,
          formType: YustSelectFormType.singleWithoutIndicator,
          onChanged: () {
            final value = selectedValues.firstOrNull;
            Navigator.pop(context, value);
          },
          optionListConstraints: const BoxConstraints(
            maxHeight: 400.0,
            maxWidth: 400.0,
          ),
          divider: false,
          autofocus: true,
        ),
      ),
    );
  }

  /// Shows a text field dialog
  /// if validator is set, action gets only triggered if the validator returns null (means true)
  Future<String?> showTextFieldDialog(
    String title,
    String? placeholder,
    String action, {
    String? message,
    String? warning,
    String initialText = '',
    bool obscureText = false,
    AutovalidateMode validateMode = AutovalidateMode.onUserInteraction,
    FormFieldValidator<String>? validator,
    Widget Function({required TextEditingController controller})? suffixIcon,
  }) {
    final controller = TextEditingController(text: initialText);
    final yustServiceValidationKey = GlobalKey<FormState>();

    final context = navStateKey.currentContext;
    if (context == null) return Future.value();
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return Form(
          key: yustServiceValidationKey,
          child: AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message != null) Text(message),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: controller,
                          decoration: InputDecoration(
                            hintText: placeholder,
                            errorMaxLines: 5,
                          ),
                          autovalidateMode: validator == null
                              ? null
                              : validateMode,
                          validator: validator == null
                              ? null
                              : (value) => validator(value),
                          autofocus: true,
                          obscureText: obscureText,
                          onFieldSubmitted: (value) {
                            _submitTextFieldDialog(
                              validator,
                              context,
                              controller,
                              yustServiceValidationKey,
                            );
                          },
                        ),
                      ),
                      if (suffixIcon != null)
                        suffixIcon(controller: controller),
                    ],
                  ),
                  if (warning != null) const SizedBox(height: 5),
                  if (warning != null)
                    Row(
                      children: [
                        const Icon(size: 15, Icons.info),
                        const SizedBox(width: 5),
                        Text(warning, style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: Text(LocaleKeys.cancel.tr()),
                onPressed: () {
                  Navigator.of(context).pop(null);
                },
              ),
              TextButton(
                child: Text(action),
                onPressed: () {
                  _submitTextFieldDialog(
                    validator,
                    context,
                    controller,
                    yustServiceValidationKey,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _submitTextFieldDialog(
    FormFieldValidator<String>? validator,
    BuildContext context,
    TextEditingController controller,
    GlobalKey<FormState> yustServiceValidationKey,
  ) {
    if (validator == null) {
      Navigator.of(context).pop(controller.text);
    } else if (yustServiceValidationKey.currentState!.validate()) {
      Navigator.of(context).pop(controller.text);
    }
  }

  ///
  /// initialSelectedValue: Initial selected value
  /// canClear: Shows a button to empty the selected value
  Future<String?> showPickerDialog(
    String title,
    String action, {
    String? subTitle,
    required List<String> optionLabels,
    required List<String> optionValues,
    String? initialValue,
    bool checkForEmptySelection = false,
  }) {
    return showClearablePickerDialog(
      title,
      action,
      optionLabels: optionLabels,
      optionValues: optionValues,
      subTitle: subTitle,
      canClear: false,
      initialValue: initialValue,
      checkForEmptySelection: checkForEmptySelection,
    ).then((v) => v?.result);
  }

  ///
  /// initialSelectedValue: Initial selected value
  /// canClear: Shows a button to empty the selected value

  Future<AlertResult?> showClearablePickerDialog(
    String title,
    String action, {
    required List<String> optionLabels,
    required List<String> optionValues,
    String? initialValue,
    String? subTitle = '',
    bool canClear = true,
    bool checkForEmptySelection = false,
  }) {
    final context = navStateKey.currentContext;
    if (context == null) return Future.value();
    var selected = initialValue;
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    return showDialog<AlertResult>(
      context: context,
      builder: (BuildContext context) {
        return Form(
          key: formKey,
          child: StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Text(title),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.topLeft,
                      child: subTitle != null
                          ? Text(subTitle)
                          : const SizedBox.shrink(),
                    ),
                    SizedBox(
                      height: 100,
                      child: YustSelect(
                        value: selected,
                        optionLabels: optionLabels,
                        optionValues: optionValues,
                        onDelete: canClear
                            ? () async {
                                setState(() => selected = null);
                              }
                            : null,
                        onSelected: (value) => {
                          setState(() => selected = value),
                        },
                        validator: (value) =>
                            checkForEmptySelection && selected == null
                            ? LocaleKeys.valueMustNotBeEmpty.tr()
                            : null,
                        autovalidateMode: checkForEmptySelection
                            ? AutovalidateMode.onUserInteraction
                            : null,
                      ),
                    ),
                  ],
                ),
                actions: <Widget>[
                  TextButton(
                    child: Text(LocaleKeys.cancel.tr()),
                    onPressed: () {
                      Navigator.of(context).pop(AlertResult(false, null));
                    },
                  ),
                  TextButton(
                    child: Text(action),
                    onPressed: () {
                      if (checkForEmptySelection &&
                          !(formKey.currentState?.validate() ?? true)) {
                        return;
                      }
                      Navigator.of(context).pop(AlertResult(true, selected));
                    },
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<T?> showCustomDialog<T>({
    required String title,
    String? actionName,
    T? initialValue,
    required Widget Function(void Function(T?) onChanged, T? currentValue)
    buildInner,
  }) {
    final context = navStateKey.currentContext;
    if (context == null) return Future.value();
    dynamic returnValue;
    return showDialog<T?>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          scrollable: true,
          title: Text(title),
          content: StatefulBuilder(
            builder: (context, setState) {
              return buildInner(
                (T? value) => setState(() => returnValue = value),
                returnValue,
              );
            },
          ),
          actions: <Widget>[
            TextButton(
              child: Text(LocaleKeys.cancel.tr()),
              onPressed: () {
                Navigator.of(context).pop(null);
              },
            ),
            if (actionName != null)
              TextButton(
                child: Text(actionName),
                onPressed: () {
                  Navigator.of(context).pop(returnValue);
                },
              ),
          ],
        );
      },
    );
  }

  /// Returns newly selected items (only) after confirmation.
  /// If popup has been canceled callable method get an empty list.
  /// If you need to track the cancel click use [showCancelableCheckListDialog]
  /// [returnPriorItems] decides whether priorItemIds or an empty list should be returned
  Future<List<String>> showCheckListDialog({
    required BuildContext context,
    required List<String> optionValues,
    required List<String> priorOptionValues,
    required List<String> optionLabels,

    bool returnPriorItems = true,
    String? title,
    String? subTitle,
  }) async {
    final result = await showCancelableCheckListDialog(
      context: context,
      optionValues: optionValues,
      priorOptionValues: priorOptionValues,
      optionLabels: optionLabels,
      returnPriorItems: returnPriorItems,
      title: title,
      subTitle: subTitle,
    );

    if (result.confirmed) {
      return result.result;
    } else {
      return [];
    }
  }

  /// Returns newly selected items (only) after confirmation.
  /// If popup has been canceled callable method get a result object.
  /// [returnPriorItems] decides whether priorItemIds or an empty list should be returned
  Future<AlertCheckListResult> showCancelableCheckListDialog({
    required BuildContext context,
    required List<String> optionValues,
    required List<String> priorOptionValues,
    required List<String> optionLabels,
    List<Widget>? prefixWidgets,
    bool returnPriorItems = true,
    String? title,
    String? subTitle,
  }) async {
    final newItemIds = List<String>.from(priorOptionValues);
    var isAborted = true;
    await showDialog<List<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: ((context, setState) {
            var selectAll = newItemIds.length != optionValues.length;
            return SimpleDialog(
              title: Text(title ?? LocaleKeys.mandatoryFields.tr()),
              children: [
                subTitle != null
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Text(subTitle),
                      )
                    : const SizedBox.shrink(),
                Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          newItemIds.clear();
                          if (selectAll) {
                            newItemIds.addAll(optionValues);
                          }
                        });
                      },
                      child: selectAll
                          ? Text(LocaleKeys.selectAll.tr())
                          : Text(LocaleKeys.deselectAll.tr()),
                    ),
                  ),
                ),
                YustSelectForm<String>(
                  optionValues: optionValues,
                  optionLabels: optionLabels,
                  selectedValues: newItemIds,
                  prefixWidgets: prefixWidgets,
                  onChanged: () {
                    setState(() {});
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        isAborted = false;
                        Navigator.of(context).pop();
                      },
                      child: Text(LocaleKeys.ok.tr()),
                    ),
                    TextButton(
                      onPressed: () {
                        isAborted = true;
                        Navigator.of(context).pop();
                      },
                      child: Text(LocaleKeys.cancel.tr()),
                    ),
                  ],
                ),
              ],
            );
          }),
        );
      },
    );

    if (isAborted) {
      if (returnPriorItems) {
        return AlertCheckListResult(false, priorOptionValues);
      } else {
        return AlertCheckListResult(false, []);
      }
    } else {
      return AlertCheckListResult(true, newItemIds);
    }
  }

  void showToast(String message) {
    final context = navStateKey.currentContext;
    if (context == null) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<T?> showSearchWithoutContext<T>(SearchDelegate<T> delegate) {
    final context = navStateKey.currentContext;
    if (context == null) return Future.value();
    return showSearch<T>(context: context, delegate: delegate);
  }
}
