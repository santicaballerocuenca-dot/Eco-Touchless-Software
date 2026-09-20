import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'perfil_modelo.dart';

img.Image prepararImagen(img.Image source, PerfilModelo perfil) {
  final image = img.bakeOrientation(source);
  final width = perfil.ancho, height = perfil.alto;
  if (perfil.letterbox) {
    final scale = min(width / image.width, height / image.height);
    final resized = img.copyResize(image,
        width: max(1, (image.width * scale).round()),
        height: max(1, (image.height * scale).round()),
        interpolation: img.Interpolation.linear);
    return img.compositeImage(img.Image(width: width, height: height), resized,
        dstX: (width - resized.width) ~/ 2,
        dstY: (height - resized.height) ~/ 2);
  }
  final ratio = width / height;
  final cropWidth = min(image.width, (image.height * ratio).round());
  final cropHeight = min(image.height, (image.width / ratio).round());
  return img.copyResize(
      img.copyCrop(image,
          x: (image.width - cropWidth) ~/ 2,
          y: (image.height - cropHeight) ~/ 2,
          width: cropWidth,
          height: cropHeight),
      width: width,
      height: height,
      interpolation: img.Interpolation.linear);
}

Uint8List prepararCapturaPerfil(Uint8List bytes, PerfilModelo perfil) {
  if (!perfil.redimensionar) return bytes;
  final image = img.decodeImage(bytes);
  if (image == null) throw const FormatException('Imagen no decodificable');
  return Uint8List.fromList(
      img.encodeJpg(prepararImagen(image, perfil), quality: 95));
}

List<double> probabilidades(List<double> output) {
  if (output.isEmpty || output.any((v) => !v.isFinite)) {
    throw const FormatException('Salida del modelo no válida');
  }
  final sum = output.fold<double>(0, (a, b) => a + b);
  if (output.every((v) => v >= 0 && v <= 1) && (sum - 1).abs() < 0.001) {
    return output.map((v) => v / sum).toList();
  }
  final maximum = output.reduce(max);
  final exps = output.map((v) => exp(v - maximum)).toList();
  final total = exps.reduce((a, b) => a + b);
  return exps.map((v) => v / total).toList();
}
