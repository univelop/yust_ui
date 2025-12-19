import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../yust_ui.dart';

class YustTextField extends StatefulWidget {
  final String? label;
  final IconData? labelIcon;
  final String? value;
  final String? placeholder;
  final TextStyle? textStyle;
  final TextStyle? labelStyle;
  final TextStyle? placeholderTextStyle;
  final StringCallback? onChanged;

  /// if a validator is implemented, onEditingComplete gets only triggered, if validator is true (true = returns null) or shouldCompleteNotValidInput is true
  final StringCallback? onEditingComplete;
  final TextEditingController? controller;
  final FormFieldValidator<String>? validator;
  final TapCallback? onTap;
  final StringCallback? onFieldSubmitted;
  final DeleteCallback? onDelete;
  final int? maxLength;
  final int? maxLines;
  final int? minLines;
  final bool expands;
  final bool autocorrect;
  final bool readOnly;
  final bool enabled;
  final bool obscureText;
  final bool autofocus;
  final bool hideKeyboardOnAutofocus;
  final bool slimDesign;
  final bool notTrim;
  final FocusNode? focusNode;
  final YustInputStyle? style;
  final bool divider;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final TextCapitalization textCapitalization;
  final AutovalidateMode? autovalidateMode;
  final SmartQuotesType? smartQuotesType;
  final TextInputType? keyboardType;
  final List<TextInputFormatter> inputFormatters;
  final TextInputAction? textInputAction;
  final EdgeInsets contentPadding;
  final bool shouldCompleteNotValidInput;

  /// if false, [onEditingComplete] gets triggered only on
  /// enter or submit but not on unfocus
  final bool completeOnUnfocus;
  final Iterable<String>? autofillHints;

  /// Whether the text field should be automatically wrapped with a [DefaultTextEditingShortcuts] widget or not.
  /// Thus reserving the current platforms default text editing shortcuts and blocking them from being overridden by custom [Shortcuts] Widgets
  final bool reserveDefaultTextEditingShortcuts;

  /// When value is set, text field is in error state; and display this text
  final String? forceErrorText;

  // The Icon to be displayed in front of the label
  final IconData? prefixLabelIcon;

  /// The color of the prefix label icon
  final Color? prefixLabelIconColor;

  /// The optional helper text below the text field
  final String? helperText;

  /// Whether the TextField should use the decoration from [InputDecoration.filled] with [InputDecoration.fillColor] from the current Theme
  final bool useFilledInputDecoration;

  /// The color to be used for [InputDecoration.fillColor] if [useFilledInputDecoration] is true
  /// If null, the default color from the current Theme will be used
  final Color? filledInputDecorationColor;

  const YustTextField({
    super.key,
    this.label,
    this.labelIcon,
    this.value,
    this.helperText,
    this.placeholder,
    this.placeholderTextStyle,
    this.textStyle,
    this.onChanged,
    this.onEditingComplete,
    this.onFieldSubmitted,
    this.controller,
    this.validator,
    this.onTap,
    this.onDelete,
    this.maxLength,
    this.maxLines,
    this.labelStyle,
    this.minLines,
    this.expands = false,
    this.enabled = true,
    this.autocorrect = true,
    this.readOnly = false,
    this.slimDesign = false,
    this.obscureText = false,
    this.autofocus = false,
    this.notTrim = false,
    this.hideKeyboardOnAutofocus = false,
    this.focusNode,
    this.style = YustInputStyle.normal,
    this.divider = true,
    this.prefixIcon,
    this.suffixIcon,
    this.textCapitalization = TextCapitalization.sentences,
    this.autovalidateMode,
    this.inputFormatters = const [],
    this.smartQuotesType,
    this.keyboardType,
    this.textInputAction,
    this.contentPadding = const EdgeInsets.fromLTRB(16.0, 20.0, 20.0, 20.0),
    this.shouldCompleteNotValidInput = false,
    this.completeOnUnfocus = true,
    this.autofillHints,
    this.reserveDefaultTextEditingShortcuts = true,
    this.forceErrorText,
    this.prefixLabelIcon,
    this.prefixLabelIconColor,
  }) : useFilledInputDecoration = false,
       filledInputDecorationColor = null;

  const YustTextField.filled({
    super.key,
    this.label,
    this.labelIcon,
    this.value,
    this.helperText,
    this.placeholder,
    this.placeholderTextStyle,
    this.textStyle,
    this.onChanged,
    this.onEditingComplete,
    this.onFieldSubmitted,
    this.controller,
    this.validator,
    this.onTap,
    this.onDelete,
    this.maxLength,
    this.maxLines,
    this.labelStyle,
    this.minLines,
    this.expands = false,
    this.enabled = true,
    this.autocorrect = true,
    this.readOnly = false,
    this.slimDesign = false,
    this.obscureText = false,
    this.autofocus = false,
    this.notTrim = false,
    this.hideKeyboardOnAutofocus = false,
    this.focusNode,
    this.style = YustInputStyle.normal,
    this.divider = true,
    this.prefixIcon,
    this.suffixIcon,
    this.textCapitalization = TextCapitalization.sentences,
    this.autovalidateMode,
    this.inputFormatters = const [],
    this.smartQuotesType,
    this.keyboardType,
    this.textInputAction,
    this.contentPadding = const EdgeInsets.fromLTRB(12, 8, 12, 8),
    this.shouldCompleteNotValidInput = false,
    this.completeOnUnfocus = true,
    this.autofillHints,
    this.reserveDefaultTextEditingShortcuts = true,
    this.forceErrorText,
    this.prefixLabelIcon,
    this.prefixLabelIconColor,
    this.filledInputDecorationColor,
  }) : useFilledInputDecoration = true;

  @override
  State<YustTextField> createState() => _YustTextFieldState();
}

class _YustTextFieldState extends State<YustTextField>
    with AutomaticKeepAliveClientMixin {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  late String _initValue;
  late bool _valueDidChange;

  void onUnfocus() {
    if (_valueDidChange == false) return;
    if (widget.onEditingComplete == null) return;
    if (widget.readOnly) return;

    final textFieldText = widget.notTrim
        ? _controller.value.text
        : _controller.value.text.trim();
    final textFieldValue = textFieldText == '' ? null : textFieldText;

    if (widget.validator == null ||
        widget.validator!(textFieldValue) == null ||
        widget.shouldCompleteNotValidInput) {
      _initValue = textFieldText;
      widget.onEditingComplete!(textFieldValue);
      _valueDidChange = false;
    }
  }

  /// This Method resets/initializes the state of the widget
  void resetState() {
    if (widget.controller != null && widget.value != null) {
      widget.controller!.text = widget.value!;
    }
    _valueDidChange = false;
    _controller =
        widget.controller ?? TextEditingController(text: widget.value);
    _focusNode =
        widget.focusNode ??
        FocusNode(debugLabel: 'yust-text-field-${widget.label}');
    _initValue = widget.value ?? '';
    _focusNode.addListener(() {
      // if (!_focusNode.hasFocus) onUnfocus();
      if (!_focusNode.hasFocus && widget.completeOnUnfocus) {
        onComplete();
      }
    });
    if (widget.autofocus && widget.hideKeyboardOnAutofocus) {
      Future.delayed(
        const Duration(),
        () => SystemChannels.textInput.invokeMethod('TextInput.hide'),
      );
    }
    _controller.addListener(() {
      _valueDidChange = true;
      if (widget.maxLength != null) {
        setState(() {});
      }
    });
  }

  void onComplete() {
    if (widget.readOnly) return;
    if (widget.onEditingComplete != null) {
      final textFieldText = widget.notTrim
          ? _controller.value.text
          : _controller.value.text.trim();
      final textFieldValue = textFieldText == '' ? null : textFieldText;
      if (widget.validator == null ||
          widget.validator!(textFieldValue) == null ||
          widget.shouldCompleteNotValidInput) {
        _initValue = textFieldText;
        widget.onEditingComplete!(textFieldValue);
        _valueDidChange = false;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    resetState();
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => onUnfocus());

    super.dispose();
  }

  @override
  void didUpdateWidget(oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the Text-Fields Label changed, we can assume it's a new/different TextField
    // (Flutter "reuses" existing Widgets in the tree)

    // Also because "*" are often used to mark required fields, we remove them beforehand
    final oldLabel = oldWidget.label?.replaceAll(' *', '');
    final newLabel = widget.label?.replaceAll(' *', '');
    if (oldLabel != newLabel) {
      onUnfocus();
      resetState();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final textValue = widget.value ?? '';
    if (textValue != _initValue &&
        textValue != _controller.text &&
        widget.onChanged == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _controller.text = textValue;
          _initValue = textValue;
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
        }
      });
    }
    if (widget.slimDesign) return _buildTextField();

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildTextField()),
            if (widget.onDelete != null && widget.value != '')
              IconButton(
                onPressed: widget.onDelete!,
                icon: Icon(
                  Icons.delete,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            widget.suffixIcon ?? const SizedBox(),
          ],
        ),
        if (widget.style == YustInputStyle.normal && widget.divider)
          const Divider(height: 1.0, thickness: 1.0, color: Colors.grey),
      ],
    );
  }

  Widget _buildTextField() {
    final label = [
      if (widget.label?.isNotEmpty ?? false) widget.label!,
      if (widget.maxLength != null)
        '(${_controller.text.length}/${widget.maxLength})',
    ].join(' ').trim();

    final textField = TextFormField(
      decoration: InputDecoration(
        prefix: widget.prefixLabelIcon != null
            ? Padding(
                padding: const EdgeInsets.only(right: 4.0),
                child: Icon(
                  widget.prefixLabelIcon,
                  color:
                      widget.prefixLabelIconColor ??
                      Theme.of(context).textTheme.bodySmall?.color ??
                      Colors.black,
                  size: 12.0,
                ),
              )
            : null,
        counter: const SizedBox.shrink(),
        label: label.isEmpty && widget.labelIcon == null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                spacing: 4.0,
                children: [
                  if (widget.labelIcon != null)
                    Padding(
                      padding: EdgeInsets.only(bottom: 2.0),
                      child: Icon(
                        widget.labelIcon,
                        size: 16.0,
                        color: Theme.of(context).disabledColor,
                      ),
                    ),
                  if (label.isNotEmpty)
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style:
                            widget.labelStyle ??
                            (widget.readOnly
                                ? TextStyle(
                                    color:
                                        Theme.of(
                                          context,
                                        ).textTheme.bodySmall?.color ??
                                        Colors.black,
                                  )
                                : null),
                      ),
                    ),
                ],
              ),
        contentPadding: widget.contentPadding,
        border: widget.style == YustInputStyle.outlineBorder
            ? const OutlineInputBorder()
            : widget.style == YustInputStyle.underlineBorder
            ? const UnderlineInputBorder()
            : InputBorder.none,
        prefixIcon: widget.prefixIcon,
        prefixIconColor: widget.readOnly
            ? Theme.of(context).textTheme.bodySmall?.color ?? Colors.black
            : null,
        hintText: widget.placeholder,
        hintStyle: widget.placeholderTextStyle,
        errorMaxLines: 5,
        helperText: widget.helperText,
        helperMaxLines: 5,
        filled: widget.useFilledInputDecoration,
        fillColor: widget.filledInputDecorationColor,
      ),
      style: widget.textStyle,
      maxLength: widget.maxLength,
      maxLengthEnforcement: widget.maxLength != null
          ? MaxLengthEnforcement.enforced
          : null,
      maxLines: widget.expands
          ? null
          : widget.obscureText
          ? 1
          : widget.maxLines,
      minLines: widget.expands ? null : widget.minLines,
      expands: widget.expands,
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: widget.keyboardType,
      textInputAction:
          widget.textInputAction ??
          (widget.minLines != null
              ? TextInputAction.newline
              : TextInputAction.next),
      onChanged: widget.onChanged == null
          ? null
          : (value) => widget.onChanged!(
              value == '' ? null : (widget.notTrim ? value : value.trim()),
            ),
      onEditingComplete: widget.completeOnUnfocus ? null : onComplete,
      onTap: widget.onTap,
      onFieldSubmitted: widget.onFieldSubmitted,
      autocorrect: widget.autocorrect,
      readOnly: widget.readOnly,
      enabled: widget.enabled,
      obscureText: widget.obscureText,
      textCapitalization: widget.textCapitalization,
      inputFormatters: widget.inputFormatters,
      smartQuotesType: widget.smartQuotesType,
      autovalidateMode:
          widget.autovalidateMode ??
          (widget.validator != null
              ? AutovalidateMode.onUserInteraction
              : null),
      validator: widget.validator == null
          ? null
          : (value) => widget.validator!(value!.trim()),
      autofocus: widget.autofocus,
      autofillHints: widget.autofillHints,
      forceErrorText: widget.forceErrorText,
    );

    if (widget.reserveDefaultTextEditingShortcuts) {
      return DefaultTextEditingShortcuts(child: textField);
    }

    return textField;
  }

  @override
  bool get wantKeepAlive => true;
}
