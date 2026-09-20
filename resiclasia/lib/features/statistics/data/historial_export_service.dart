import '../../classification/domain/clasificacion.dart';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'historial_xlsx.dart';

enum FormatoHistorial {
  texto('Texto plano', 'Fecha y clasificación · .txt', 'txt', 'text/plain'),
  excel(
      'Excel sin imágenes',
      'Datos completos, filtros y fechas · .xlsx',
      'xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
  excelImagenes(
      'Excel con imágenes',
      'Datos y miniaturas incrustadas · .xlsx',
      'xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
  imagenes('Solo imágenes', 'Fotografías originales disponibles · .zip', 'zip',
      'application/zip');

  const FormatoHistorial(
      this.titulo, this.descripcion, this.extension, this.mime);
  final String titulo, descripcion, extension, mime;
}

class ExportacionHistorial {
  const ExportacionHistorial(
      this.ruta, this.registros, this.imagenes, this.sinImagen);
  final String ruta;
  final int registros, imagenes, sinImagen;
}

class HistorialExportService {
  const HistorialExportService._();

  static String generarTexto(List<Clasificacion> historial) => [
        'VisionIA · Historial (hora local)',
        ...historial.map((c) =>
            '${DateFormat('dd/MM/yyyy HH:mm:ss').format(c.fecha.toLocal())} — ${c.label.replaceAll(RegExp(r'[\r\n]'), ' ')}')
      ].join('\n');

  /// Encoding and image decoding run off the UI isolate.
  static Future<ExportacionHistorial> exportar(List<Clasificacion> historial,
          FormatoHistorial formato, String directorio) =>
      compute(_crear, (historial, formato, directorio));

  static Future<ExportacionHistorial> _crear(
      (List<Clasificacion>, FormatoHistorial, String) args) async {
    final (historial, formato, directorio) = args;
    if (historial.isEmpty) {
      throw const FormatException('No hay registros para exportar.');
    }
    if (historial.length > 10000) {
      throw const FormatException(
          'Máximo 10.000 registros por archivo. Aplicá un filtro.');
    }
    final fotos = <int, Uint8List>{};
    final zip = Archive();
    var cantidad = 0, bytesTotales = 0;
    if (formato == FormatoHistorial.imagenes ||
        formato == FormatoHistorial.excelImagenes) {
      for (var i = 0; i < historial.length; i++) {
        final c = historial[i];
        if (c.rutaImagen.isEmpty) continue;
        final file = File(c.rutaImagen);
        if (!await file.exists()) continue;
        final length = await file.length();
        if (length > 32 * 1024 * 1024) {
          throw const FormatException(
              'Una imagen supera 32 MB. Usá Excel sin imágenes.');
        }
        Uint8List bytes;
        try {
          bytes = await file.readAsBytes();
        } on FileSystemException {
          continue;
        }
        if (formato == FormatoHistorial.excelImagenes) {
          final decoder = img.findDecoderForData(bytes);
          final info = decoder?.startDecode(bytes);
          if (info == null) continue;
          if (info.width * info.height > 24000000) {
            throw const FormatException(
                'Imagen demasiado grande para miniatura. Usá Excel sin imágenes.');
          }
          final decoded = decoder!.decodeFrame(0);
          if (decoded == null) continue;
          final thumbnail = img.copyResize(img.bakeOrientation(decoded),
              width: 180,
              height: 120,
              maintainAspect: true,
              backgroundColor: img.ColorRgb8(245, 247, 250));
          bytes = Uint8List.fromList(img.encodeJpg(thumbnail, quality: 78));
          fotos[i] = bytes;
        } else {
          final tipo = c.label.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
          final ext = p.extension(c.rutaImagen).toLowerCase();
          final seguro =
              ['.jpg', '.jpeg', '.png', '.webp'].contains(ext) ? ext : '.jpg';
          zip.addFile(ArchiveFile(
              '${DateFormat('yyyyMMdd_HHmmss').format(c.fecha)}_${i + 1}_$tipo$seguro',
              bytes.length,
              bytes));
        }
        bytesTotales += bytes.length;
        if (bytesTotales > 64 * 1024 * 1024) {
          throw const FormatException(
              'Las imágenes superan 64 MB. Aplicá un filtro o exportá sin imágenes.');
        }
        cantidad++;
      }
    }
    if (formato == FormatoHistorial.imagenes && cantidad == 0) {
      throw const FormatException(
          'No hay imágenes disponibles. En vivo no guarda fotos; la retención también puede eliminarlas.');
    }
    final bytes = switch (formato) {
      FormatoHistorial.texto => utf8.encode(generarTexto(historial)),
      FormatoHistorial.excel => HistorialXlsx.generar(historial),
      FormatoHistorial.excelImagenes =>
        HistorialXlsx.generar(historial, fotos: fotos, conImagenes: true),
      FormatoHistorial.imagenes => ZipEncoder().encode(zip),
    };
    await Directory(directorio).create(recursive: true);
    final ruta = p.join(directorio,
        'VisionIA_${formato.name}_${DateTime.now().microsecondsSinceEpoch}.${formato.extension}');
    await File(ruta).writeAsBytes(bytes, flush: true);
    return ExportacionHistorial(
        ruta,
        historial.length,
        cantidad,
        formato == FormatoHistorial.imagenes ||
                formato == FormatoHistorial.excelImagenes
            ? historial.length - cantidad
            : 0);
  }

  static String generarCsv(List<Clasificacion> historial) {
    final filas = <String>[
      'id,categoria,categoria_original,modo,confirmada,corregida,confianza_porcentaje,fecha_iso,ruta_imagen',
      for (final clasificacion in historial)
        [
          clasificacion.id?.toString() ?? '',
          clasificacion.label,
          clasificacion.labelOriginal,
          clasificacion.esEnVivo ? 'en_vivo' : 'foto',
          clasificacion.confirmada ? 'si' : 'no',
          clasificacion.corregida ? 'si' : 'no',
          clasificacion.confianza.toStringAsFixed(2),
          clasificacion.fecha.toIso8601String(),
          clasificacion.rutaImagen,
        ].map(_escapar).join(','),
    ];
    return filas.join('\r\n');
  }

  static String _escapar(String valor) {
    if (!valor.contains(RegExp('[,"\\r\\n]'))) return valor;
    return '"${valor.replaceAll('"', '""')}"';
  }
}
