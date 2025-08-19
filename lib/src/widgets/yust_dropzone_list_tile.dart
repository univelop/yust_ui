import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';
import 'package:yust_ui/src/extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';
import 'yust_list_tile.dart';

class YustDropzoneListTile extends StatefulWidget {
  final String? label;
  final Widget? prefixIcon;
  final Widget? suffixChild;
  final Widget? below;
  final bool divider;
  final Function(DropzoneViewController, DropzoneFileInterface)? onDrop;
  final Function(DropzoneViewController, List<DropzoneFileInterface>?)?
  onDropMultiple;
  final bool wrapSuffixChild;

  const YustDropzoneListTile({
    super.key,
    this.label,
    this.prefixIcon,
    this.suffixChild,
    this.below,
    this.divider = true,
    this.onDrop,
    this.onDropMultiple,
    this.wrapSuffixChild = false,
  });

  @override
  State<YustDropzoneListTile> createState() => _YustDropzoneListTileState();
}

class _YustDropzoneListTileState extends State<YustDropzoneListTile> {
  late DropzoneViewController _controller;
  var _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: _buildDropzoneArea(context),
        ),
        YustListTile(
          label: widget.label,
          suffixChild: _isDragging ? null : widget.suffixChild,
          prefixIcon: widget.prefixIcon,
          below: _buildDropzoneInterfaceAndFiles(),
          divider: widget.divider,
          wrapSuffixChild: widget.wrapSuffixChild,
        ),
      ],
    );
  }

  /// This widget will accept files from a drag and drop interaction
  Widget _buildDropzoneArea(BuildContext context) => Builder(
    builder: (context) => DropzoneView(
      operation: DragOperation.copy,
      cursor: _isDragging ? CursorType.grab : CursorType.Default,
      onCreated: (ctrl) => _controller = ctrl,
      onLoaded: () {},
      onError: (ev) {},
      onHover: () {
        setState(() {
          _isDragging = true;
        });
      },
      onLeave: () {
        setState(() {
          _isDragging = false;
        });
      },
      onDropFile: (ev) {
        setState(() {
          _isDragging = false;
        });
        widget.onDrop?.call(_controller, ev);
      },
      onDropFiles: (ev) {
        setState(() {
          _isDragging = false;
        });
        widget.onDropMultiple?.call(_controller, ev);
      },
    ),
  );

  Widget _buildDropzoneInterfaceAndFiles() => Column(
    children: [
      if (_isDragging) _buildDropzoneInterface(),
      widget.below ?? const SizedBox(),
    ],
  );

  /// This Widget is a visual drag and drop indicator. It shows a dotted box, an icon as well as a button to manually upload files
  Widget _buildDropzoneInterface() {
    final dropZoneColor = _isDragging
        ? Colors.blue
        : const Color.fromARGB(255, 116, 116, 116);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(100, 2, 2, 2),
        child: DottedBorder(
          options: RoundedRectDottedBorderOptions(
            color: dropZoneColor,
            strokeWidth: 3,
            dashPattern: const [6, 5],
            radius: const Radius.circular(12),
            padding: const EdgeInsets.all(6),
            strokeCap: StrokeCap.round,
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            child: SizedBox(
              height: 200,
              width: 400,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Icon(
                    Icons.cloud_upload_outlined,
                    size: 35,
                    color: dropZoneColor,
                  ),
                  Text(
                    LocaleKeys.dragFilesHere.tr(),
                    style: TextStyle(fontSize: 20, color: dropZoneColor),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
