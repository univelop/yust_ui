import 'package:flutter/material.dart';

import '../yust_ui.dart';
import 'yust_list_tile.dart';

class YustSwitch extends StatelessWidget {
  final String? label;
  final bool value;
  final Color? activeColor;
  final Widget? prefixIcon;
  final void Function(bool)? onChanged;
  final bool readOnly;
  final bool slimDesign;
  //switchRepresentation could be: 'yesNo', 'checkbox', 'label',
  final String switchRepresentation;
  final bool divider;
  final Widget? suffixIcon;

  const YustSwitch({
    super.key,
    this.label,
    required this.value,
    this.activeColor,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.readOnly = false,
    this.slimDesign = false,
    this.switchRepresentation = 'yesNo',
    this.divider = true,
  });

  @override
  Widget build(BuildContext context) {
    final checkboxOrSwitchBuilder =
        switchRepresentation == 'checkbox' ? _buildCheckbox : _buildSwitch;
    if (slimDesign) return checkboxOrSwitchBuilder(context);
    return YustListTile(
      label: label,
      suffixChild: Row(
        children: [
          checkboxOrSwitchBuilder(context),
          if (suffixIcon != null) suffixIcon!
        ],
      ),
      onTap: readOnly || onChanged == null
          ? null
          : () {
              YustUi.helpers.unfocusCurrent();
              onChanged!(!value);
            },
      prefixIcon: prefixIcon,
      divider: divider,
    );
  }

  Widget _buildCheckbox(BuildContext context) {
    return Checkbox(
      checkColor: activeColor,
      value: value,
      onChanged: (bool? value) {
        YustUi.helpers.unfocusCurrent();
        readOnly || value == null || onChanged == null
            ? null
            : onChanged!(value);
      },
    );
  }

  Widget _buildSwitch(BuildContext context) {
    return Switch(
      value: value,
      activeColor: activeColor ?? Theme.of(context).primaryColor,
      onChanged: (value) {
        YustUi.helpers.unfocusCurrent();
        readOnly || onChanged == null ? null : onChanged!(value);
      },
    );
  }
}
