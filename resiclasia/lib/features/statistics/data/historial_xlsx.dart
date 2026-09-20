import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../../classification/domain/clasificacion.dart';

/// Small, self-contained OOXML workbook. Text uses inline strings, never
/// formulas; dates/confidence are typed numbers. Pictures are embedded parts.
class HistorialXlsx {
  static const _ns =
      'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  static const _rels =
      'http://schemas.openxmlformats.org/package/2006/relationships';
  static const _office =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

  static String xml(String value) => value
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static Uint8List generar(List<Clasificacion> filas,
      {Map<int, Uint8List> fotos = const {}, bool conImagenes = false}) {
    final zip = Archive();
    void part(String name, String content) {
      final bytes = utf8.encode(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>$content');
      zip.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    String relation(String id, String type, String target) =>
        '<Relationship Id="$id" Type="$_office/$type" Target="$target"/>';
    part('_rels/.rels',
        '<Relationships xmlns="$_rels">${relation('rId1', 'officeDocument', 'xl/workbook.xml')}</Relationships>');
    part('xl/workbook.xml',
        '<workbook xmlns="$_ns" xmlns:r="$_office"><sheets><sheet name="Historial" sheetId="1" r:id="rId1"/></sheets></workbook>');
    part('xl/_rels/workbook.xml.rels',
        '<Relationships xmlns="$_rels">${relation('rId1', 'worksheet', 'worksheets/sheet1.xml')}${relation('rId2', 'styles', 'styles.xml')}</Relationships>');
    part('xl/styles.xml', '''<styleSheet xmlns="$_ns">
<numFmts count="2"><numFmt numFmtId="164" formatCode="dd/mm/yyyy hh:mm:ss"/><numFmt numFmtId="165" formatCode="0.0%"/></numFmts>
<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><color rgb="FFFFFFFF"/><sz val="11"/><name val="Calibri"/></font></fonts>
<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF163C4A"/><bgColor indexed="64"/></patternFill></fill></fills>
<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"><alignment vertical="center" wrapText="1"/></xf><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFill="1" applyFont="1"><alignment vertical="center" wrapText="1"/></xf><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"><alignment vertical="center"/></xf><xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"><alignment vertical="center"/></xf></cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>''');
    String text(String ref, String value, [int style = 0]) =>
        '<c r="$ref" s="$style" t="inlineStr"><is><t xml:space="preserve">${xml(value)}</t></is></c>';
    final headers = [
      'Fecha (hora local)',
      'Tipo clasificado',
      'Aceptación',
      'ESP32 vinculada',
      'Modo',
      'Confianza IA',
      if (conImagenes) 'Imagen'
    ];
    final rows = StringBuffer('<row r="1" ht="32" customHeight="1">');
    for (var i = 0; i < headers.length; i++) {
      rows.write(text('${String.fromCharCode(65 + i)}1', headers[i], 1));
    }
    rows.write('</row>');
    for (var i = 0; i < filas.length; i++) {
      final c = filas[i], r = i + 2;
      final d = c.fecha.toLocal();
      final serial =
          DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second)
                  .difference(DateTime.utc(1899, 12, 30))
                  .inSeconds /
              86400;
      rows.write('<row r="$r" ht="${conImagenes ? 96 : 30}" customHeight="1">');
      rows.write('<c r="A$r" s="2"><v>$serial</v></c>');
      rows.write(text('B$r', c.label));
      rows.write(text('C$r', aceptacion(c)));
      rows.write(text(
          'D$r',
          c.espVinculada == null
              ? 'No registrado'
              : c.espVinculada!
                  ? 'Sí'
                  : 'No'));
      rows.write(text('E$r', c.esEnVivo ? 'En vivo' : 'Cámara'));
      rows.write(c.confianza.isFinite
          ? '<c r="F$r" s="3"><v>${c.confianza / 100}</v></c>'
          : text('F$r', 'No registrado'));
      if (conImagenes && !fotos.containsKey(i)) {
        rows.write(text('G$r', 'Sin imagen disponible'));
      }
      rows.write('</row>');
    }
    final lastCol = conImagenes ? 'G' : 'F';
    part('xl/worksheets/sheet1.xml',
        '<worksheet xmlns="$_ns" xmlns:r="$_office"><dimension ref="A1:$lastCol${filas.length + 1}"/><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols><col min="1" max="1" width="24" customWidth="1"/><col min="2" max="5" width="23" customWidth="1"/><col min="6" max="6" width="18" customWidth="1"/><col min="7" max="7" width="28" customWidth="1"/></cols><sheetData>$rows</sheetData><autoFilter ref="A1:$lastCol${filas.length + 1}"/>${fotos.isEmpty ? '' : '<drawing r:id="rId1"/>'}</worksheet>');
    if (fotos.isNotEmpty) {
      part('xl/worksheets/_rels/sheet1.xml.rels',
          '<Relationships xmlns="$_rels">${relation('rId1', 'drawing', '../drawings/drawing1.xml')}</Relationships>');
      final drawing = StringBuffer(), links = StringBuffer();
      var id = 0;
      for (final entry in fotos.entries) {
        id++;
        zip.addFile(ArchiveFile(
            'xl/media/image$id.jpg', entry.value.length, entry.value));
        links.write(relation('rId$id', 'image', '../media/image$id.jpg'));
        drawing.write(
            '''<xdr:oneCellAnchor><xdr:from><xdr:col>6</xdr:col><xdr:colOff>38100</xdr:colOff><xdr:row>${entry.key + 1}</xdr:row><xdr:rowOff>38100</xdr:rowOff></xdr:from><xdr:ext cx="1714500" cy="1143000"/><xdr:pic><xdr:nvPicPr><xdr:cNvPr id="$id" name="Imagen $id"/><xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr><xdr:blipFill><a:blip r:embed="rId$id"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill><xdr:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="1714500" cy="1143000"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic><xdr:clientData/></xdr:oneCellAnchor>''');
      }
      part('xl/drawings/drawing1.xml',
          '<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="$_office">$drawing</xdr:wsDr>');
      part('xl/drawings/_rels/drawing1.xml.rels',
          '<Relationships xmlns="$_rels">$links</Relationships>');
    }
    part('[Content_Types].xml',
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="jpg" ContentType="image/jpeg"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>${fotos.isEmpty ? '' : '<Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>'}</Types>');
    return Uint8List.fromList(ZipEncoder().encode(zip));
  }

  static String aceptacion(Clasificacion c) => switch (c.aceptacion) {
        'manual' => c.corregida ? 'Corregido manualmente' : 'Confirmado',
        'automatica' => 'Autoaceptado',
        _ => 'No registrado',
      };
}
