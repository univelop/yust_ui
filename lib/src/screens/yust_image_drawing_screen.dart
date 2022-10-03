import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_painter/flutter_painter.dart';

class YustImageDrawingScreen extends StatefulWidget {
  final ImageProvider image;
  final void Function(Uint8List? image) onSave;

  const YustImageDrawingScreen({
    Key? key,
    required this.image,
    required this.onSave,
  }) : super(key: key);

  @override
  YustImageDrawingScreenState createState() => YustImageDrawingScreenState();
}

class YustImageDrawingScreenState extends State<YustImageDrawingScreen> {
  FocusNode textFocusNode = FocusNode();
  late PainterController controller;
  ui.Image? backgroundImage;
  StrokeWidth strokeWidth = StrokeWidth.medium;
  StrokeColor strokeColor = StrokeColor.black;
  StyleMode styleMode = StyleMode.none;
  Shapes? shape;
  late Paint shapePaint;
  bool showSettings = false;

  @override
  void initState() {
    super.initState();
    shapePaint = Paint()
      ..strokeWidth = 5
      ..color = strokeColor.color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    controller = PainterController(
      settings: PainterSettings(
        text: TextSettings(
          focusNode: textFocusNode,
          textStyle: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        freeStyle: const FreeStyleSettings(),
        shape: ShapeSettings(
          paint: shapePaint,
          drawOnce: false,
        ),
        scale: const ScaleSettings(
          enabled: true,
          minScale: 1,
          maxScale: 5,
        ),
      ),
    );
    controller.freeStyleMode = _styleModeToFreeStyleMode(styleMode);
    _setColor(strokeColor);
    _setWidth(strokeWidth);
    textFocusNode.addListener(onFocus);
    initBackground();
  }

  /// Fetches image from an [ImageProvider] (in this example, [NetworkImage])
  /// to use it as a background
  void initBackground() async {
    // Extension getter (.image) to get [ui.Image] from [ImageProvider]
    ui.Image image = await (widget.image).image;
    setState(() {
      backgroundImage = image;
      controller.background = image.backgroundDrawable;
    });
  }

  /// Updates UI when the focus changes
  void onFocus() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size(double.infinity, kToolbarHeight),
          // Listen to the controller and update the UI when it updates.
          child: ValueListenableBuilder<PainterControllerValue>(
              valueListenable: controller,
              builder: (context, _, child) {
                return AppBar(
                  automaticallyImplyLeading: false,
                  title: Row(
                    children: [
                      _buildUndo(),
                      _buildRedo(),
                    ],
                  ),
                  actions: [
                    _buildSaveButton(context),
                    _buildDiscardButton(context),
                  ],
                );
              }),
        ),
        body: Stack(
          children: [
            if (backgroundImage != null)
              // Enforces constraints
              InteractiveViewer(
                child: Center(
                  child: AspectRatio(
                    aspectRatio:
                        backgroundImage!.width / backgroundImage!.height,
                    child: FlutterPainter(
                      controller: controller,
                      onDrawableCreated: ((drawable) => showSettings = false),
                    ),
                  ),
                ),
              ),
            Positioned(
              bottom: 0,
              right: 0,
              left: 0,
              child: ValueListenableBuilder(
                valueListenable: controller,
                builder: (context, _, __) => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: _buildSettings(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: ValueListenableBuilder(
          valueListenable: controller,
          builder: (context, _, __) => Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildFreeStyleEraser(context),
              _buildFreeStyleDrawing(context),
              _buildAddText(context),
              _buildAddShapes(context),
              _buildOpenSettings(context),
            ],
          ),
        ));
  }

  Widget _buildUndo() {
    return IconButton(
      icon: const Icon(
        Icons.undo_sharp,
      ),
      onPressed: controller.canUndo ? _undo : null,
    );
  }

  Widget _buildRedo() {
    return IconButton(
      icon: const Icon(
        Icons.redo_sharp,
      ),
      onPressed: controller.canRedo ? _redo : null,
    );
  }

  Widget _buildSaveButton(BuildContext context) {
    return TextButton.icon(
      icon: const Icon(Icons.check),
      label: const Text('Speichern'),
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).primaryColor,
      ),
      onPressed: () {
        Navigator.of(context).pop();
        _renderAndDisplayImage();
      },
    );
  }

  Widget _buildDiscardButton(BuildContext context) {
    return TextButton.icon(
      icon: const Icon(Icons.cancel),
      label: const Text('Abbrechen'),
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).primaryColor,
      ),
      onPressed: () async {
        Navigator.of(context).pop();
      },
    );
  }

  Widget _buildSettings() {
    return Container(
      constraints: const BoxConstraints(
        maxWidth: 400,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        color: _isDarkMode(context) ? Colors.grey[900] : Colors.grey[100],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSettings == true) ...[
            Row(
              children: [
                const Expanded(flex: 2, child: Text('Strichstärke')),
                ...StrokeWidth.values
                    .map((value) => _buildStrokeWidthSetting(value))
                    .toList(),
              ],
            ),
            Row(
              children: [
                const Expanded(flex: 2, child: Text('Farbe')),
                ...StrokeColor.values
                    .map((value) => _buildStrokeColorSetting(value))
                    .toList(),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFreeStyleEraser(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.auto_fix_high,
        color: styleMode == StyleMode.erase
            ? Theme.of(context).colorScheme.secondary
            : null,
      ),
      onPressed: _toggleFreeStyleErase,
    );
  }

  Widget _buildFreeStyleDrawing(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.brush,
        color: styleMode == StyleMode.draw
            ? Theme.of(context).colorScheme.secondary
            : null,
      ),
      onPressed: _toggleFreeStyleDraw,
    );
  }

  Widget _buildAddText(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.abc,
        color: textFocusNode.hasFocus
            ? Theme.of(context).colorScheme.secondary
            : null,
      ),
      onPressed: _toggleText,
    );
  }

  Widget _buildAddShapes(BuildContext context) {
    return PopupMenuButton<Shapes>(
      itemBuilder: (context) => Shapes.values
          .map((e) => PopupMenuItem(
              value: e,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Icon(
                    e.icon,
                    color: Colors.black,
                  ),
                  Text(' ${e.title}')
                ],
              )))
          .toList(),
      onSelected: _selectShape,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Icon(
          shape != null ? shape!.icon : Icons.square_foot,
          color: shape != null ? Theme.of(context).colorScheme.secondary : null,
        ),
      ),
    );
  }

  Widget _buildOpenSettings(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.lens),
      color: strokeColor.color,
      iconSize: 35,
      onPressed: _toggleSettings,
    );
  }

  Widget _buildStrokeWidthSetting(StrokeWidth strokeWidthValue) {
    var iconSize = 35.0;

    switch (strokeWidthValue) {
      case StrokeWidth.small:
        iconSize = 20.0;
        break;
      case StrokeWidth.medium:
        iconSize = 35.0;
        break;
      case StrokeWidth.large:
        iconSize = 50.0;
        break;
    }
    return Expanded(
      flex: 2,
      child: IconButton(
        icon: const Icon(Icons.lens),
        iconSize: iconSize,
        color: strokeWidthValue == strokeWidth
            ? Theme.of(context).colorScheme.secondary
            : null,
        onPressed: () => _setWidth(strokeWidthValue),
      ),
    );
  }

  Widget _buildStrokeColorSetting(StrokeColor strokeColorValue) {
    return Expanded(
      flex: 1,
      child: IconButton(
        icon: strokeColorValue == strokeColor
            ? const Icon(Icons.check_circle)
            : const Icon(Icons.lens),
        iconSize: 35,
        color: strokeColorValue.color,
        onPressed: () => _setColor(strokeColorValue),
      ),
    );
  }

  void _undo() {
    controller.undo();
  }

  void _redo() {
    controller.redo();
  }

  bool _isDarkMode(BuildContext context) {
    var brightness = MediaQuery.of(context).platformBrightness;
    return brightness == Brightness.dark;
  }

  void _toggleFreeStyleDraw() {
    _selectShape(null);
    styleMode = styleMode == StyleMode.draw ? StyleMode.none : StyleMode.draw;
    controller.freeStyleMode = _styleModeToFreeStyleMode(styleMode);
  }

  void _toggleFreeStyleErase() {
    _selectShape(null);
    styleMode = styleMode == StyleMode.erase ? StyleMode.none : StyleMode.erase;
    controller.freeStyleMode = _styleModeToFreeStyleMode(styleMode);
  }

  void _toggleSettings() {
    setState(() {
      showSettings = !showSettings;
    });
  }

  void _toggleText() {
    _selectShape(null);
    showSettings = false;
    styleMode = styleMode == StyleMode.text ? StyleMode.none : StyleMode.text;
    controller.freeStyleMode = _styleModeToFreeStyleMode(styleMode);
    controller.addText();
  }

  void _setWidth(StrokeWidth value) {
    setState(() {
      strokeWidth = value;
    });

    controller.freeStyleStrokeWidth = value.width;
    _setShapeFactoryPaint((controller.shapePaint ?? shapePaint).copyWith(
      strokeWidth: value.width,
    ));
    controller.textSettings = controller.textSettings.copyWith(
        textStyle: controller.textSettings.textStyle
            .copyWith(fontSize: value.textWidth));
  }

  void _setColor(StrokeColor strokeColorValue) {
    setState(() {
      strokeColor = strokeColorValue;
    });

    controller.freeStyleColor = strokeColor.color;
    _setShapeFactoryPaint((controller.shapePaint ?? shapePaint).copyWith(
      color: strokeColor.color,
    ));
    controller.textStyle =
        controller.textStyle.copyWith(color: strokeColor.color);
  }

  void _setShapeFactoryPaint(Paint paint) {
    // Set state is just to update the current UI, the [FlutterPainter] UI updates without it
    setState(() {
      controller.shapePaint = paint;
    });
  }

  void _selectShape(Shapes? selectedShape) {
    shape = selectedShape;
    if (shape != null) {
      styleMode =
          styleMode == StyleMode.shape ? StyleMode.none : StyleMode.shape;
      controller.freeStyleMode = _styleModeToFreeStyleMode(styleMode);
    }
    controller.shapeFactory = _getFactory(selectedShape);
  }

  ShapeFactory? _getFactory(Shapes? shape) {
    switch (shape) {
      case Shapes.line:
        return LineFactory();
      case Shapes.arrow:
        return ArrowFactory();
      case Shapes.doubleArrow:
        return DoubleArrowFactory();
      case Shapes.rectangle:
        return RectangleFactory();
      case Shapes.oval:
        return OvalFactory();
      default:
        return null;
    }
  }

  FreeStyleMode _styleModeToFreeStyleMode(StyleMode styleMode) {
    switch (styleMode) {
      case StyleMode.draw:
        return FreeStyleMode.draw;
      case StyleMode.erase:
        return FreeStyleMode.erase;
      default:
        return FreeStyleMode.none;
    }
  }

  Future<void> _renderAndDisplayImage() async {
    if (backgroundImage == null) return;
    final backgroundImageSize = Size(
        backgroundImage!.width.toDouble(), backgroundImage!.height.toDouble());

    final image = await controller
        .renderImage(backgroundImageSize)
        .then<Uint8List?>((ui.Image image) => image.pngBytes);

    widget.onSave(image);
  }
}

enum StyleMode {
  none,
  erase,
  draw,
  text,
  shape,
}

enum StrokeWidth {
  small(width: 2, textWidth: 11),
  medium(width: 12, textWidth: 20),
  large(width: 25, textWidth: 50);

  const StrokeWidth({
    required this.width,
    required this.textWidth,
  });

  final double width;
  final double textWidth;
}

enum StrokeColor {
  black(Color.fromARGB(255, 0, 0, 0)),
  red(Colors.red),
  blue(Colors.blue),
  green(Colors.green),
  yellow(Colors.yellow);

  const StrokeColor(
    this.color,
  );

  final Color color;
}

enum Shapes {
  line(title: 'Linie', icon: Icons.horizontal_rule),
  arrow(title: 'Pfeil', icon: Icons.trending_flat),
  doubleArrow(title: 'Doppelpfeil', icon: Icons.open_in_full),
  rectangle(title: 'Rechteck', icon: Icons.rectangle),
  oval(title: 'Oval', icon: Icons.circle);

  const Shapes({required this.title, required this.icon});

  final String title;
  final IconData icon;
}
