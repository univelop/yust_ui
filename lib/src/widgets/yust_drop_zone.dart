import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/yust_ui.dart';

class YustDropZone extends StatefulWidget {
  final Widget child;

  /// not displayed when dragging
  final Widget? suffixChild;
  final Future<void> Function(YustFile file) onDrop;
  final bool divider;
  final String? label;
  final String dropzoneText;
  final Widget? prefixIcon;

  const YustDropZone({
    Key? key,
    required this.onDrop,
    required this.child,
    this.dropzoneText = 'Datei(en) hierher ziehen',
    this.suffixChild,
    this.label,
    this.prefixIcon,
    this.divider = true,
  }) : super(key: key);

  @override
  YustDropZoneState createState() => YustDropZoneState();
}

class YustDropZoneState extends State<YustDropZone> {
  var isDragging = false;
  late DropzoneViewController controller;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: _buildDropzoneArea(context),
        ),
        YustListTile(
            suffixChild: isDragging ? null : widget.suffixChild,
            label: widget.label,
            prefixIcon: widget.prefixIcon,
            below: _buildDropzoneInterfaceAndFiles(),
            divider: widget.divider),
      ],
    );
  }

  /// This widget will accept files from a drag and drop interaction
  Widget _buildDropzoneArea(BuildContext context) => Builder(
        builder: (context) => DropzoneView(
          operation: DragOperation.copy,
          cursor: CursorType.grab,
          onCreated: (ctrl) => controller = ctrl,
          onLoaded: () {},
          onError: (ev) {},
          onHover: () {
            setState(() {
              isDragging = true;
            });
          },
          onLeave: () {
            setState(() {
              isDragging = false;
            });
          },
          onDrop: (ev) async {},
          onDropMultiple: (ev) async {
            setState(() {
              isDragging = false;
            });

            for (final file in ev ?? []) {
              final bytes = await controller.getFileData(file);
              final yustFile = YustFile(name: file.name, bytes: bytes);

              await widget.onDrop(yustFile);
            }
          },
        ),
      );

  Widget _buildDropzoneInterfaceAndFiles() => Column(
        children: [
          if (isDragging)
            Column(
              children: [
                _buildDropzoneInterface(),
                const SizedBox(
                  height: 10,
                )
              ],
            ),
          widget.child,
        ],
      );

  /// This Widget is a visual drag and drop indicator. It shows a dotted box, an icon as well as a button to manually upload files
  Widget _buildDropzoneInterface() {
    final dropZoneColor =
        isDragging ? Colors.blue : const Color.fromARGB(255, 116, 116, 116);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(100, 2, 2, 2),
        child: DottedBorder(
          borderType: BorderType.RRect,
          radius: const Radius.circular(12),
          padding: const EdgeInsets.all(6),
          dashPattern: const [6, 5],
          strokeWidth: 3,
          strokeCap: StrokeCap.round,
          color: dropZoneColor,
          child: ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            child: SizedBox(
              height: 200,
              width: 400,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Icon(Icons.cloud_upload_outlined,
                      size: 35, color: dropZoneColor),
                  Text(
                    widget.dropzoneText,
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
