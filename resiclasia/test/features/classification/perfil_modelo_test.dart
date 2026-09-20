import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:resiclasia/features/classification/domain/perfil_modelo.dart';
import 'package:resiclasia/features/classification/domain/preparacion_imagen.dart';
import 'package:resiclasia/features/classification/domain/preprocesador_frame_yuv.dart';

void main() {
  test('perfil MobileNet por defecto coincide con pruebas del usuario', () {
    const perfil = PerfilModelo();
    expect(perfil.ancho, 160);
    expect(perfil.alto, 160);
    expect(perfil.bgr, isTrue);
    expect(perfil.letterbox, isFalse);
    expect(perfil.normalizacion, 'ceroUno');
    expect(PerfilModelo.fromJson(perfil.toJson()).resumen, perfil.resumen);
  });
  test('rechaza dimensiones fuera de límite y normalización desconocida', () {
    expect(() => PerfilModelo.fromJson({'ancho': 0}), throwsFormatException);
    expect(() => PerfilModelo.fromJson({'alto': 9999}), throwsFormatException);
    expect(() => PerfilModelo.fromJson({'normalizacion': 'unknown'}),
        throwsFormatException);
  });
  test('center-crop crea cuadrado estricto y letterbox conserva bandas negras',
      () {
    final original = img.Image(width: 200, height: 100);
    img.fill(original, color: img.ColorRgb8(255, 0, 0));
    final cropped =
        prepararImagen(original, const PerfilModelo(ancho: 96, alto: 96));
    expect([cropped.width, cropped.height], [96, 96]);
    expect(cropped.getPixel(0, 0).r, 255);
    final boxed = prepararImagen(
        original, const PerfilModelo(ancho: 96, alto: 96, letterbox: true));
    expect(boxed.getPixel(0, 0).r, 0);
    expect(boxed.getPixel(48, 48).r, 255);
  });
  test('captura rectangular respeta ancho y alto, insignia conserva bytes', () {
    final bytes =
        Uint8List.fromList(img.encodeJpg(img.Image(width: 200, height: 100)));
    final prepared = img.decodeImage(prepararCapturaPerfil(
        bytes, const PerfilModelo(ancho: 128, alto: 96)))!;
    expect([prepared.width, prepared.height], [128, 96]);
    expect(
        identical(prepararCapturaPerfil(bytes, PerfilModelo.insignia), bytes),
        isTrue);
  });
  test('probabilidades no reciben softmax por segunda vez', () {
    expect(probabilidades([0.05, 0.9, 0.05])[1], closeTo(0.9, 1e-6));
    expect(probabilidades([0, 2, 0])[1], closeTo(0.786986, 1e-5));
    expect(() => probabilidades([double.nan]), throwsFormatException);
  });
  test('stream intercambia BGR y agrega letterbox sin archivos', () {
    final planes = [
      PlanoFrameYuv(
          bytes: Uint8List.fromList(List.filled(8, 100)),
          bytesPorFila: 4,
          bytesPorPixel: 1),
      PlanoFrameYuv(
          bytes: Uint8List.fromList([90, 90]),
          bytesPorFila: 2,
          bytesPorPixel: 1),
      PlanoFrameYuv(
          bytes: Uint8List.fromList([200, 200]),
          bytesPorFila: 2,
          bytesPorPixel: 1),
    ];
    Float32List frame({bool bgr = false, bool letterbox = false}) =>
        preprocesarFrameYuv420(
            ancho: 4,
            alto: 2,
            planos: planes,
            rotacionGrados: 0,
            tamanoDestino: 4,
            mean: [0, 0, 0],
            std: [1, 1, 1],
            bgr: bgr,
            letterbox: letterbox,
            anchoMuestreo: 4,
            altoMuestreo: 4);
    final rgb = frame();
    final bgr = frame(bgr: true);
    expect(rgb[0], bgr[2]);
    expect(rgb[2], bgr[0]);
    expect(frame(letterbox: true).take(12), everyElement(0));
    expect(frame(letterbox: true)[12], greaterThan(0));
  });
}
