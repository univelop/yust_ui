import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:yust_ui/src/util/yust_web_helpers/yust_web_helpers_interface.dart';
import 'package:web/web.dart' as web;
import 'dart:js_interop' as js;

class YustWebHelpersWeb implements YustWebHelpersInterface {
  @override
  void replaceUrl(String path) {
    web.window.history.replaceState(null, '', path);
  }

  @override
  void downloadData(String name, Uint8List? data) {
    if (data == null) return;
    final base64data = base64Encode(data);
    final a = web.HTMLAnchorElement();
    a.href = 'data:application/octet-stream;base64,$base64data';
    a.download = name;
    a.click();
  }

  @override
  Future<Uint8List> resizeImage(
      {required String name,
      required Uint8List bytes,
      required int maxWidth,
      required int quality}) async {
    var base64 = base64Encode(bytes);
    var newImg = web.HTMLImageElement();
    var mimeType =
        'image/${name.split('.').last.toLowerCase()}'.replaceAll('jpg', 'jpeg');
    newImg.src = 'data:$mimeType;base64,$base64';

    await newImg.onLoad.first;

    int width = newImg.width;
    int height = newImg.height;

    if (newImg.width >= newImg.height && newImg.width >= maxWidth) {
      width = maxWidth;
      height = (width * newImg.height / newImg.width).round();
    } else if (newImg.height > newImg.width && newImg.height > maxWidth) {
      height = maxWidth;
      width = (height * newImg.width / newImg.height).round();
    }

    var canvas = web.HTMLCanvasElement();
    canvas.width = width;
    canvas.height = height;
    var ctx = canvas.context2D;

    ctx.drawImage(newImg, 0, 0, width, height);
    final blobCompleter = Completer<web.Blob>();
    canvas.toBlob(
        blobCompleter.complete.toJS, 'image/jpeg', (quality / 100).toJS);
    final blob = await blobCompleter.future;

    return await _getBlobData(blob);
  }

  Future<Uint8List> _getBlobData(web.Blob blob) {
    final completer = Completer<Uint8List>();
    final reader = web.FileReader();
    reader.readAsArrayBuffer(blob);
    reader.onload = ((_) {
      if (reader.result.isA<js.JSArrayBuffer>()) {
        final buffer = (reader.result as js.JSArrayBuffer).toDart;
        completer.complete(buffer.asUint8List());
      } else {
        completer.complete(Uint8List(0));
      }
    }).toJS;
    return completer.future;
  }
}
