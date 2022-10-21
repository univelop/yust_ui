import 'package:flutter/material.dart';

import '../widgets/yust_select.dart';
import '../widgets/yust_switch.dart';

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
    String initialText = '',

    /// if validator is set, action gets only triggered if the validator returns null (means true)
    FormFieldValidator<String>? validator,
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
            content: TextFormField(
              controller: controller,
              decoration: InputDecoration(hintText: placeholder),
              autovalidateMode:
                  validator == null ? null : AutovalidateMode.onUserInteraction,
              validator: validator == null
                  ? null
                  : (value) => validator(value!.trim()),
              autofocus: true,
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
                  onSelected: (value) =>
                      {setState(() => selected = value as String)},
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
  Future<List<String>> showCheckListDialog({
    required BuildContext context,
    required List<dynamic> choosableItems,
    required List<String> priorItemIds,
    required String? Function(dynamic) getItemLabel,
    required String? Function(dynamic) getItemId,
    String? title,
  }) async {
    final newItemIds = List<String>.from(priorItemIds);
    var isAborted = true;
    await showDialog<dynamic>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Text(title ?? 'Pflichtfelder'),
                content: SizedBox(
                  width: 300,
                  height: 500,
                  child: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () {
                                newItemIds.clear();
                                setState(() {
                                  newItemIds.addAll(choosableItems
                                      .map((item) => getItemId(item) ?? ''));
                                });
                              },
                              child: const Text('Alle auswählen'),
                            ),
                          ),
                          ...choosableItems
                              .map(
                                (item) => YustSwitch(
                                  label: getItemLabel(item ?? ''),
                                  value: newItemIds
                                      .contains(getItemId(item) ?? ''),
                                  onChanged: (value) {
                                    if (value) {
                                      setState(() {
                                        newItemIds.add(getItemId(item) ?? '');
                                      });
                                    } else {
                                      setState(() {
                                        newItemIds
                                            .remove(getItemId(item) ?? '');
                                      });
                                    }
                                  },
                                  switchRepresentation: 'checkbox',
                                ),
                              )
                              .toList(),
                        ]),
                  ),
                ),
                actions: [
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
              );
            },
          );
        });
    if (isAborted) {
      return priorItemIds;
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
}
