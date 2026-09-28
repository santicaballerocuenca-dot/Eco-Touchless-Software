import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../classification/domain/clasificacion.dart';

/// Maneja toda la persistencia del historial de clasificaciones en SQLite.
/// Es un singleton: una sola conexión abierta durante toda la vida de la app.
class DatabaseService extends ChangeNotifier {
  DatabaseService._interno();
  static final DatabaseService instancia = DatabaseService._interno();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _inicializarDB();
    return _db!;
  }

  Future<Database> _inicializarDB() async {
    final rutaBD = await getDatabasesPath();
    final ruta = p.join(rutaBD, 'eco_touchless.db');

    return openDatabase(
      ruta,
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE clasificaciones (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            label TEXT NOT NULL,
            labelOriginal TEXT,
            confirmada INTEGER NOT NULL DEFAULT 0,
            esEnVivo INTEGER NOT NULL DEFAULT 0,
            espVinculada INTEGER,
            aceptacion TEXT,
            confianza REAL NOT NULL,
            rutaImagen TEXT NOT NULL,
            fecha INTEGER NOT NULL
          )
        ''');
        // Índice para que las consultas de estadísticas por fecha sean rápidas
        // incluso con miles de registros acumulados.
        await db.execute('CREATE INDEX idx_fecha ON clasificaciones(fecha)');
      },
      onUpgrade: (db, versionAnterior, versionNueva) async {
        if (versionAnterior < 2) {
          await db.execute(
            'ALTER TABLE clasificaciones ADD COLUMN labelOriginal TEXT',
          );
          await db.execute(
            'ALTER TABLE clasificaciones ADD COLUMN confirmada INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'UPDATE clasificaciones SET labelOriginal = label '
            'WHERE labelOriginal IS NULL',
          );
        }
        if (versionAnterior < 3) {
          await db.execute(
            'ALTER TABLE clasificaciones ADD COLUMN esEnVivo INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (versionAnterior < 4) {
          await db.execute(
              'ALTER TABLE clasificaciones ADD COLUMN espVinculada INTEGER');
          await db.execute(
              'ALTER TABLE clasificaciones ADD COLUMN aceptacion TEXT');
        }
      },
    );
  }

  /// Guarda una nueva clasificación y devuelve su id generado.
  Future<int> insertar(Clasificacion c) async {
    final db = await database;
    final id = await db.insert('clasificaciones', c.toMap()..remove('id'));
    notifyListeners();
    return id;
  }

  /// Devuelve el historial completo, más reciente primero.
  Future<List<Clasificacion>> obtenerHistorial({
    int? limite,
    int offset = 0,
    String? label,
  }) async {
    final db = await database;
    final filas = await db.query(
      'clasificaciones',
      where: label == null ? null : 'label = ?',
      whereArgs: label == null ? null : [label],
      orderBy: 'fecha DESC',
      limit: limite,
      offset: limite == null ? null : offset,
    );
    return filas.map((f) => Clasificacion.fromMap(f)).toList();
  }

  /// Total de clasificaciones registradas.
  Future<int> contarTotal({String? label}) async {
    final db = await database;
    final res = await db.rawQuery(
      'SELECT COUNT(*) as total FROM clasificaciones'
      '${label == null ? '' : ' WHERE label = ?'}',
      label == null ? null : [label],
    );
    return Sqflite.firstIntValue(res) ?? 0;
  }

  /// Cantidad de clasificaciones agrupadas por label (para el gráfico de tipos).
  Future<List<ConteoPorLabel>> contarPorLabel() async {
    final db = await database;
    final filas = await db.rawQuery('''
      SELECT label, COUNT(*) as cantidad
      FROM clasificaciones
      GROUP BY label
      ORDER BY cantidad DESC
    ''');
    return filas
        .map((f) => ConteoPorLabel(
              label: f['label'] as String,
              cantidad: f['cantidad'] as int,
            ))
        .toList();
  }

  /// Cantidad de clasificaciones agrupadas por día (para ver qué día se
  /// clasificó más). Se calcula truncando el timestamp a medianoche local.
  Future<List<ConteoPorDia>> contarPorDia({int diasAtras = 14}) async {
    final db = await database;
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final cantidadDias = diasAtras < 1 ? 1 : diasAtras;
    final desdeDia = hoy.subtract(Duration(days: cantidadDias - 1));
    final desde = desdeDia.millisecondsSinceEpoch;

    final filas = await db.rawQuery('''
      SELECT fecha FROM clasificaciones WHERE fecha >= ?
    ''', [desde]);

    // Agrupamos en Dart (más simple y portable que fecha con SQLite puro,
    // que no tiene funciones de fecha nativas confiables entre plataformas).
    final Map<String, int> conteo = {};
    for (final fila in filas) {
      final fecha = DateTime.fromMillisecondsSinceEpoch(fila['fecha'] as int);
      final diaTruncado = DateTime(fecha.year, fecha.month, fecha.day);
      final clave = diaTruncado.toIso8601String();
      conteo[clave] = (conteo[clave] ?? 0) + 1;
    }

    // Incluye explícitamente los días con cero actividad para que el eje X
    // represente tiempo real y no comprima huecos entre clasificaciones.
    return List.generate(cantidadDias, (indice) {
      final dia = desdeDia.add(Duration(days: indice));
      return ConteoPorDia(
        dia: dia,
        cantidad: conteo[dia.toIso8601String()] ?? 0,
      );
    });
  }

  /// Borra una clasificación puntual y su fotografía asociada.
  Future<void> eliminar(int id) async {
    final db = await database;
    final filas = await db.query(
      'clasificaciones',
      columns: ['rutaImagen'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    await db.delete('clasificaciones', where: 'id = ?', whereArgs: [id]);
    if (filas.isNotEmpty) {
      await _borrarArchivo(filas.first['rutaImagen'] as String);
    }
    notifyListeners();
  }

  /// Borra TODO el historial y todas las fotografías vinculadas.
  Future<void> borrarTodo() async {
    final db = await database;
    final filas = await db.query('clasificaciones', columns: ['rutaImagen']);
    await db.delete('clasificaciones');
    for (final fila in filas) {
      await _borrarArchivo(fila['rutaImagen'] as String);
    }
    // La carpeta es exclusiva del historial. Eliminarla también limpia fotos
    // huérfanas creadas por versiones anteriores de la app.
    await _borrarCarpetaDeFotos();
    notifyListeners();
  }

  /// Elimina solo las fotografías vencidas y conserva los datos estadísticos.
  /// [dias] igual a 0 desactiva la caducidad automática.
  Future<int> aplicarRetencionImagenes(int dias) async {
    if (dias <= 0) return 0;
    final db = await database;
    final limite =
        DateTime.now().subtract(Duration(days: dias)).millisecondsSinceEpoch;
    final filas = await db.query(
      'clasificaciones',
      columns: ['id', 'rutaImagen'],
      where: "fecha < ? AND rutaImagen <> ''",
      whereArgs: [limite],
    );
    for (final fila in filas) {
      await _borrarArchivo(fila['rutaImagen'] as String);
    }
    if (filas.isNotEmpty) {
      final ids = filas.map((fila) => fila['id'] as int).toList();
      final marcadores = List.filled(ids.length, '?').join(',');
      await db.rawUpdate(
        "UPDATE clasificaciones SET rutaImagen = '' WHERE id IN ($marcadores)",
        ids,
      );
      notifyListeners();
    }
    return filas.length;
  }

  Future<void> _borrarCarpetaDeFotos() async {
    try {
      final documentos = await getApplicationDocumentsDirectory();
      final carpeta = Directory(p.join(documentos.path, 'fotos_clasificadas'));
      if (await carpeta.exists()) await carpeta.delete(recursive: true);
    } catch (e) {
      debugPrint('No se pudo limpiar la carpeta de fotografías: $e');
    }
  }

  Future<void> _borrarArchivo(String ruta) async {
    try {
      final archivo = File(ruta);
      if (await archivo.exists()) await archivo.delete();
    } catch (e) {
      debugPrint('No se pudo borrar la imagen $ruta: $e');
    }
  }
}
