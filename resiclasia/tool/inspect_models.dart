import 'dart:io';
import 'dart:typed_data';

// Read-only inspection of the public TFLite FlatBuffer tensor contract.
void main() {
  for (final file in Directory('assets/modelos').listSync().whereType<File>()) {
    if (!file.path.endsWith('.tflite')) continue;
    final b = ByteData.sublistView(file.readAsBytesSync());
    int u32(int p) => b.getUint32(p, Endian.little);
    int field(int t, int i) {
      final v = t - b.getInt32(t, Endian.little);
      final p = v + 4 + 2 * i;
      if (p >= v + b.getUint16(v, Endian.little)) return 0;
      final offset = b.getUint16(p, Endian.little);
      return offset == 0 ? 0 : t + offset;
    }

    int ref(int p) => p + u32(p);
    List<int> vector(int t, int f, {bool tables = false}) {
      final p = field(t, f);
      if (p == 0) return [];
      final v = ref(p);
      return List.generate(
          u32(v), (i) => tables ? ref(v + 4 + i * 4) : u32(v + 4 + i * 4));
    }

    final model = u32(0);
    final graph = vector(model, 2, tables: true).first;
    final tensors = vector(graph, 0, tables: true);
    String tensor(int index) {
      final t = tensors[index];
      final type = field(t, 1);
      return 'shape=${vector(t, 0)}, type=${type == 0 ? 0 : b.getUint8(type)}';
    }

    final codes = vector(model, 1, tables: true);
    final ops = vector(graph, 3, tables: true);
    final opIndex = field(ops.last, 0);
    final code = codes[opIndex == 0 ? 0 : u32(opIndex)];
    final builtin = field(code, 3);
    final legacy = field(code, 0);
    stdout.writeln(
        '${file.path}\n input: ${vector(graph, 1).map(tensor).join()}\n output: ${vector(graph, 2).map(tensor).join()}\n last operator: ${builtin != 0 ? u32(builtin) : legacy == 0 ? 0 : b.getInt8(legacy)} (25 = SOFTMAX)');
  }
}
