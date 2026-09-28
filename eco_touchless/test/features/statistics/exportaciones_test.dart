import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:eco_touchless/features/classification/domain/clasificacion.dart';
import 'package:eco_touchless/features/statistics/data/historial_export_service.dart';
import 'package:eco_touchless/features/statistics/data/historial_xlsx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Clasificacion registro(
          {String foto = '',
          String? aceptacion = 'automatica',
          bool? vinculada = true,
          String label = 'Metal'}) =>
      Clasificacion(
          label: label,
          confianza: 87.5,
          rutaImagen: foto,
          fecha: DateTime(2026, 9, 20, 12, 30),
          aceptacion: aceptacion,
          espVinculada: vinculada);
  String part(Archive zip, String path) =>
      utf8.decode(zip.findFile(path)!.content as List<int>);

  test('XLSX mantiene tipos, filtros y texto sin fórmulas ejecutables', () {
    final zip = ZipDecoder().decodeBytes(HistorialXlsx.generar([
      registro(label: '=HYPERLINK("https://example.com") & <Metal>'),
      registro(aceptacion: null, vinculada: null),
    ]));
    final sheet = part(zip, 'xl/worksheets/sheet1.xml');
    expect(sheet, contains('<v>0.875</v>'));
    expect(sheet, contains('s="2"><v>'));
    expect(sheet, contains('t="inlineStr"'));
    expect(sheet, contains('&amp; &lt;Metal&gt;'));
    expect(sheet, isNot(contains('<f>')));
    expect(sheet, contains('No registrado'));
    expect(sheet, contains('Autoaceptado'));
    expect(sheet, contains('autoFilter'));
    expect(sheet, contains('state="frozen"'));
    expect(zip.findFile('xl/media/image1.jpg'), isNull);
  });

  test('los cuatro formatos incluyen fotos reales y cuentan las ausentes',
      () async {
    final dir =
        await Directory.systemTemp.createTemp('eco_touchless-export-test-');
    addTearDown(() => dir.delete(recursive: true));
    final source = File('${dir.path}/foto.jpg');
    await source.writeAsBytes(img.encodeJpg(img.Image(width: 30, height: 20)));
    final rows = [
      registro(foto: source.path),
      registro(foto: '${dir.path}/no-existe.jpg')
    ];
    for (final format in FormatoHistorial.values) {
      final result =
          await HistorialExportService.exportar(rows, format, dir.path);
      final bytes = await File(result.ruta).readAsBytes();
      expect(result.registros, 2);
      if (format == FormatoHistorial.texto) {
        expect(utf8.decode(bytes), contains('20/09/2026 12:30:00 — Metal'));
      } else {
        final zip = ZipDecoder().decodeBytes(bytes);
        if (format == FormatoHistorial.imagenes) {
          expect(zip.files.length, 1);
          expect(zip.files.single.content, await source.readAsBytes());
        } else {
          expect(zip.findFile('xl/workbook.xml'), isNotNull);
          if (format == FormatoHistorial.excelImagenes) {
            expect(zip.findFile('xl/media/image1.jpg'), isNotNull);
            expect(part(zip, 'xl/drawings/drawing1.xml'),
                contains('<xdr:row>1</xdr:row>'));
            expect(part(zip, 'xl/drawings/_rels/drawing1.xml.rels'),
                contains('../media/image1.jpg'));
            expect(part(zip, 'xl/worksheets/sheet1.xml'),
                contains('Sin imagen disponible'));
          }
        }
      }
      if (format == FormatoHistorial.imagenes ||
          format == FormatoHistorial.excelImagenes) {
        expect(result.imagenes, 1);
        expect(result.sinImagen, 1);
      }
    }
    expect(
        await source.exists(), isTrue); // Export never removes history photos.
  });

  test(
      'exportación vacía y solo fotos inexistentes se explican, no generan ZIP vacío',
      () async {
    await expectLater(
        HistorialExportService.exportar([], FormatoHistorial.texto, 'unused'),
        throwsFormatException);
    await expectLater(
        HistorialExportService.exportar(
            [registro()], FormatoHistorial.imagenes, 'unused'),
        throwsFormatException);
  });

  test(
      'base anterior no inventa aceptación ni conexión; nuevos datos sobreviven ida y vuelta',
      () {
    final c = Clasificacion.fromMap(registro().toMap());
    expect(c.aceptacion, 'automatica');
    expect(c.espVinculada, isTrue);
    final old = registro().toMap()
      ..remove('aceptacion')
      ..remove('espVinculada');
    final legacy = Clasificacion.fromMap(old);
    expect(legacy.espVinculada, isNull);
    expect(HistorialXlsx.aceptacion(legacy), 'No registrado');
  });
  test('aceptación manual no se confunde con automática', () {
    expect(
        HistorialXlsx.aceptacion(registro(aceptacion: 'manual')), 'Confirmado');
    final corregida = Clasificacion(
        label: 'Metal',
        labelOriginal: 'Vidrio',
        aceptacion: 'manual',
        confianza: 70,
        rutaImagen: '',
        fecha: DateTime(2026));
    expect(HistorialXlsx.aceptacion(corregida), 'Corregido manualmente');
  });
}
