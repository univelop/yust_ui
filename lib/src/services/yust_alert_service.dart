import 'package:flutter/material.dart';
import 'package:yust_ui/src/widgets/yust_multi_select_component.dart';

import '../widgets/yust_select.dart';

class YustAlertService {
  final GlobalKey<NavigatorState> navStateKey;

  YustAlertService(this.navStateKey);

  Future<void> showAlert(String title, String message) {
    final context = navStateKey.currentContext;
    if (context == null) return Future.value();
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> showCustomAlert(
      {required Widget Function(BuildContext) content,
      bool dismissible = true}) async {
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
    String cancelText = 'Abbrechen',
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
              child: Text(cancelText),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            TextButton(
              key: Key(action),
              child: Text(action),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );
  }

  Future<String?> showTextFieldDialog(
    String title,
    String? placeholder,
    String action, {
    String? message,
    String? warning,
    String initialText = '',
    AutovalidateMode validateMode = AutovalidateMode.onUserInteraction,

    /// if validator is set, action gets only triggered if the validator returns null (means true)
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
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message != null) Text(message),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: controller,
                        decoration: InputDecoration(hintText: placeholder),
                        autovalidateMode:
                            validator == null ? null : validateMode,
                        validator: validator == null
                            ? null
                            : (value) => validator(value!.trim()),
                        autofocus: true,
                      ),
                    ),
                    if (suffixIcon != null) suffixIcon(controller: controller),
                  ],
                ),
                if (warning != null)
                  const SizedBox(height: 5),
                if (warning != null)
                  Row(
                  children: [
                    const Icon(
                      size: 15,
                      Icons.info,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      warning,
                      style: const TextStyle(
                        fontSize: 11,
                      ),
                    ),
                ],),
              ],
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Abbrechen'),
                onPressed: () {
                  Navigator.of(context).pop(null);
                },
              ),
              TextButton(
                child: Text(action),
                onPressed: () {
                  if (validator == null) {
                    Navigator.of(context).pop(controller.text);
                  } else if (yustServiceValidationKey.currentState!
                      .validate()) {
                    //if ( validator(controller.text.trim()) == null
                    Navigator.of(context).pop(controller.text);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String?> showPickerDialog(
    String title,
    String action, {
    required List<String> optionLabels,
    required List<String> optionValues,
    String initialText = '',
  }) {
    final context = navStateKey.currentContext;
    if (context == null) return Future.value();
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        var selected = '';
        return AlertDialog(
          title: Text(title),
          content: StatefulBuilder(
            builder: (context, setState) {
              return SizedBox(
                height: 100,
                child: YustSelect(
                  value: selected,
                  optionLabels: optionLabels,
                  optionValues: optionValues,
                  onSelected: (value) => {setState(() => selected = value)},
                ),
              );
            },
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Abbrechen'),
              onPressed: () {
                Navigator.of(context).pop(null);
              },
            ),
            TextButton(
              child: Text(action),
              onPressed: () {
                Navigator.of(context).pop(selected);
              },
            ),
          ],
        );
      },
    );
  }

  Future<T?> showCustomDialog<T>({
    required String title,
    String? actionName,
    required Widget Function({required void Function(T?) onChanged}) buildInner,
  }) {
    final context = navStateKey.currentContext;
    if (context == null) return Future.value();
    return showDialog<T?>(
      context: context,
      builder: (BuildContext context) {
        dynamic returnValue;
        return AlertDialog(
          scrollable: true,
          title: Text(title),
          content: StatefulBuilder(
            builder: (context, setState) {
              return buildInner(
                onChanged: (T? value) => returnValue = value,
              );
            },
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Abbrechen'),
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
    final newItemIds = List<String>.from(priorOptionValues);
    var isAborted = true;
    await showDialog<List<String>>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: ((context, setState) {
              return SimpleDialog(
                title: Text(title ?? 'Pflichtfelder'),
                children: [
                  subTitle != null
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Text(subTitle))
                      : const SizedBox(),
                  Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () {
                          newItemIds.clear();
                          setState(() {
                            newItemIds.addAll(optionValues);
                          });
                        },
                        child: const Text('Alle auswählen'),
                      ),
                    ),
                  ),
                  YustMultiSelectComponent<String>(
                    optionValues: optionValues,
                    optionLabels: optionLabels,
                    selectedValues: newItemIds,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          isAborted = false;
                          Navigator.of(context).pop();
                        },
                        child: const Text('OK'),
                      ),
                      TextButton(
                        onPressed: () {
                          isAborted = true;
                          Navigator.of(context).pop();
                        },
                        child: const Text('Abbrechen'),
                      ),
                    ],
                  )
                ],
              );
            }),
          );
        });

    if (isAborted) {
      if (returnPriorItems) {
        return priorOptionValues;
      } else {
        return [];
      }
    } else {
      return newItemIds;
    }
  }

  void showToast(String message) {
    final context = navStateKey.currentContext;
    if (context == null) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
    ));
  }

  Future<T?> showSearchWithoutContext<T>(SearchDelegate<T> delegate) {
    final context = navStateKey.currentContext;
    if (context == null) return Future.value();
    return showSearch<T>(context: context, delegate: delegate);
  }
}
