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
  static const Color red = Color(0xFFFF0000);
  FocusNode textFocusNode = FocusNode();
  late PainterController controller;
  ui.Image? backgroundImage;
  Paint shapePaint = Paint()
    ..strokeWidth = 5
    ..color = Colors.red
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  bool showSettings = false;
  StrokeWidth strokeWidth = StrokeWidth.medium;
  StrokeColor strokeColor = StrokeColor.red;
  StyleMode styleMode = StyleMode.draw;

  @override
  void initState() {
    super.initState();
    controller = PainterController(
      settings: PainterSettings(
        text: TextSettings(
          focusNode: textFocusNode,
          textStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            color: red,
            fontSize: 18,
          ),
        ),
        freeStyle: const FreeStyleSettings(
          color: red,
          strokeWidth: 5,
        ),
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
    controller.freeStyleMode = FreeStyleMode.draw;
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
              Positioned.fill(
                child: Center(
                  child: AspectRatio(
                    aspectRatio:
                        backgroundImage!.width / backgroundImage!.height,
                    child: FlutterPainter(
                      controller: controller,
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
                      child: Container(
                        constraints: const BoxConstraints(
                          maxWidth: 400,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        decoration: const BoxDecoration(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(20)),
                          color: Colors.white54,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (showSettings == true) ...[
                              const Divider(),
                              const Text('Einstellungen'),
                              Row(
                                children: [
                                  const Expanded(
                                      flex: 2, child: Text('Strichstärke')),
                                  ...StrokeWidth.values
                                      .map((value) =>
                                          _buildStrokeWidthSetting(value))
                                      .toList(),
                                ],
                              ),
                              Row(
                                children: [
                                  const Expanded(flex: 2, child: Text('Farbe')),
                                  ...StrokeColor.values
                                      .map((value) =>
                                          _buildStrokeColorSetting(value))
                                      .toList(),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
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
              _buildSettings(context),
            ],
          ),
        ));
  }

  Widget _buildUndo() {
    return IconButton(
      icon: const Icon(
        Icons.undo_sharp,
      ),
      onPressed: controller.canUndo ? undo : null,
    );
  }

  Widget _buildRedo() {
    return IconButton(
      icon: const Icon(
        Icons.redo_sharp,
      ),
      onPressed: controller.canRedo ? redo : null,
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
        renderAndDisplayImage();
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

  Widget _buildFreeStyleEraser(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.auto_fix_high,
        color: styleMode == StyleMode.erase
            ? Theme.of(context).colorScheme.secondary
            : null,
      ),
      onPressed: toggleFreeStyleErase,
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
      onPressed: toggleFreeStyleDraw,
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
      onPressed: toggleText,
    );
  }

  Widget _buildAddShapes(BuildContext context) {
    if (controller.shapeFactory == null) {
      return PopupMenuButton<ShapeFactory?>(
        itemBuilder: (context) => <ShapeFactory, String>{
          LineFactory(): 'Linie',
          ArrowFactory(): 'Pfeil',
          DoubleArrowFactory(): 'Doppelpfeil',
          RectangleFactory(): 'Rechteck',
          OvalFactory(): 'Oval',
        }
            .entries
            .map((e) => PopupMenuItem(
                value: e.key,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Icon(
                      getShapeIcon(e.key),
                      color: Colors.black,
                    ),
                    Text(' ${e.value}')
                  ],
                )))
            .toList(),
        onSelected: selectShape,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(
            getShapeIcon(controller.shapeFactory),
            color: controller.shapeFactory != null
                ? Theme.of(context).colorScheme.secondary
                : null,
          ),
        ),
      );
    } else {
      return IconButton(
        icon: Icon(
          getShapeIcon(controller.shapeFactory),
          color: Theme.of(context).colorScheme.secondary,
        ),
        onPressed: () => selectShape(null),
      );
    }
  }

  Widget _buildSettings(BuildContext context) {
    return IconButton(
      icon: const Icon(
        Icons.settings,
      ),
      color: showSettings ? Theme.of(context).colorScheme.secondary : null,
      onPressed: toggleSettings,
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
        onPressed: () => setWidth(strokeWidthValue),
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
        color: _getStrokeColor(strokeColorValue),
        onPressed: () => setColor(strokeColorValue),
      ),
    );
  }

  Color _getStrokeColor(StrokeColor strokeColorValue) {
    switch (strokeColorValue) {
      case StrokeColor.black:
        return const Color.fromARGB(255, 0, 0, 0);
      case StrokeColor.red:
        return Colors.red;
      case StrokeColor.blue:
        return Colors.blue;
      case StrokeColor.yellow:
        return Colors.yellow;
      case StrokeColor.green:
        return Colors.green;
      default:
        return Colors.red;
    }
  }

  double _getStrokeWidth(StrokeWidth strokeWidthValue) {
    switch (strokeWidthValue) {
      case StrokeWidth.small:
        return 2;
      case StrokeWidth.medium:
        return 12;
      case StrokeWidth.large:
        return 25;
    }
  }

  double _getTextWidth(StrokeWidth strokeWidthValue) {
    switch (strokeWidthValue) {
      case StrokeWidth.small:
        return 11;
      case StrokeWidth.medium:
        return 20;
      case StrokeWidth.large:
        return 50;
    }
  }

  static IconData getShapeIcon(ShapeFactory? shapeFactory) {
    if (shapeFactory is LineFactory) return Icons.horizontal_rule;
    if (shapeFactory is ArrowFactory) return Icons.trending_flat;
    if (shapeFactory is DoubleArrowFactory) {
      return Icons.open_in_full;
    }
    if (shapeFactory is RectangleFactory) return Icons.rectangle;
    if (shapeFactory is OvalFactory) return Icons.circle;
    return Icons.square_foot;
  }

  void undo() {
    controller.undo();
  }

  void redo() {
    controller.redo();
  }

  void toggleFreeStyleDraw() {
    selectShape(null);
    styleMode = styleMode == StyleMode.draw ? StyleMode.none : StyleMode.draw;
    controller.freeStyleMode = styleModeToFreeStyleMode(styleMode);
  }

  void toggleFreeStyleErase() {
    selectShape(null);
    styleMode = styleMode == StyleMode.erase ? StyleMode.none : StyleMode.erase;
    controller.freeStyleMode = styleModeToFreeStyleMode(styleMode);
  }

  void toggleSettings() {
    setState(() {
      showSettings = !showSettings;
    });
  }

  void toggleText() {
    selectShape(null);
    styleMode = styleMode == StyleMode.draw ? StyleMode.none : StyleMode.draw;
    controller.freeStyleMode = styleModeToFreeStyleMode(styleMode);
    controller.addText();
  }

  void setWidth(StrokeWidth value) {
    setState(() {
      strokeWidth = value;
    });

    var width = _getStrokeWidth(value);
    controller.freeStyleStrokeWidth = width;
    setShapeFactoryPaint((controller.shapePaint ?? shapePaint).copyWith(
      strokeWidth: width,
    ));
    controller.textSettings = controller.textSettings.copyWith(
        textStyle: controller.textSettings.textStyle
            .copyWith(fontSize: _getTextWidth(value)));
  }

  void setColor(StrokeColor strokeColorValue) {
    setState(() {
      strokeColor = strokeColorValue;
    });

    var color = _getStrokeColor(strokeColorValue);
    controller.freeStyleColor = color;
    setShapeFactoryPaint((controller.shapePaint ?? shapePaint).copyWith(
      color: color,
    ));
    controller.textStyle = controller.textStyle.copyWith(color: color);
  }

  void setShapeFactoryPaint(Paint paint) {
    // Set state is just to update the current UI, the [FlutterPainter] UI updates without it
    setState(() {
      controller.shapePaint = paint;
    });
  }

  void selectShape(ShapeFactory? factory) {
    styleMode = styleMode == StyleMode.shape ? StyleMode.none : StyleMode.shape;
    controller.freeStyleMode = styleModeToFreeStyleMode(styleMode);

    controller.shapeFactory = factory;
  }

  StyleMode freeStyleModeToStyleMode(FreeStyleMode freeStyleMode) {
    switch (freeStyleMode) {
      case FreeStyleMode.draw:
        return StyleMode.draw;
      case FreeStyleMode.erase:
        return StyleMode.erase;
      case FreeStyleMode.none:
        return StyleMode.none;
    }
  }

  FreeStyleMode styleModeToFreeStyleMode(StyleMode styleMode) {
    switch (styleMode) {
      case StyleMode.draw:
        return FreeStyleMode.draw;
      case StyleMode.erase:
        return FreeStyleMode.erase;
      default:
        return FreeStyleMode.none;
    }
  }

  Future<void> renderAndDisplayImage() async {
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
  small,
  medium,
  large,
}

enum StrokeColor {
  black,
  red,
  blue,
  green,
  yellow,
}
