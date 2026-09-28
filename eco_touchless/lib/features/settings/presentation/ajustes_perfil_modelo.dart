import 'package:flutter/material.dart';
import '../../classification/domain/modelo_ia.dart';
import '../../classification/domain/perfil_modelo.dart';
import '../data/config_service.dart';

class AjustesPerfilModelo extends StatefulWidget {
  const AjustesPerfilModelo({super.key, required this.modelo});
  final ModeloIa modelo;
  @override
  State<AjustesPerfilModelo> createState() => _AjustesPerfilModeloState();
}

class _AjustesPerfilModeloState extends State<AjustesPerfilModelo> {
  final _width = TextEditingController();
  final _height = TextEditingController();
  final _form = GlobalKey<FormState>();
  PerfilModelo? _perfil;
  bool _letterbox = false, _bgr = true;
  String _norm = 'ceroUno';
  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final perfil =
        await ConfigService.instancia.getPerfilModelo(widget.modelo.assetPath);
    if (!mounted) return;
    setState(() {
      _perfil = perfil;
      _width.text = '${perfil.ancho}';
      _height.text = '${perfil.alto}';
      _norm = perfil.normalizacion;
      _letterbox = perfil.letterbox;
      _bgr = perfil.bgr;
    });
  }

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  String? _validar(String? value) {
    final number = int.tryParse(value ?? '');
    return number == null || number < 16 || number > 1024
        ? 'Entero de 16 a 1024'
        : null;
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    await ConfigService.instancia.setPerfilModelo(
        widget.modelo.assetPath,
        PerfilModelo(
          ancho: int.parse(_width.text),
          alto: int.parse(_height.text),
          normalizacion: _norm,
          letterbox: _letterbox,
          bgr: _bgr,
        ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Perfil guardado para este modelo. Se aplica a Foto, En vivo, comparación y Bench.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (PerfilModelo.esInsignia(widget.modelo.assetPath)) {
      return const ListTile(
          leading: Icon(Icons.verified),
          title: Text('Modelo insignia · preparación protegida'),
          subtitle: Text(
              '224×224 · Center-crop · RGB · media/desviación ImageNet. Los ajustes experimentales aparecen al activar otro modelo.'));
    }
    if (_perfil == null) return const LinearProgressIndicator();
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
                key: _form,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Entrada experimental · ${widget.modelo.nombre}',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      const Text(
                          'Elegí la resolución de captura. 96 × 96 produce un cuadrado estricto. Luego se adapta al tensor fijo del archivo TFLite (los MobileNet incluidos exigen 160 × 160). No cambia la arquitectura del modelo.'),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                            child: TextFormField(
                                controller: _width,
                                keyboardType: TextInputType.number,
                                validator: _validar,
                                decoration: const InputDecoration(
                                    labelText: 'Input X · ancho'))),
                        const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text('×')),
                        Expanded(
                            child: TextFormField(
                                controller: _height,
                                keyboardType: TextInputType.number,
                                validator: _validar,
                                decoration: const InputDecoration(
                                    labelText: 'Input Y · alto'))),
                      ]),
                      Wrap(spacing: 8, children: [
                        for (final size in [96, 160, 224])
                          ActionChip(
                              label: Text('$size×$size'),
                              onPressed: () {
                                _width.text = '$size';
                                _height.text = '$size';
                              })
                      ]),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _norm,
                        decoration:
                            const InputDecoration(labelText: 'Normalización'),
                        items: const [
                          DropdownMenuItem(
                              value: 'ceroUno', child: Text('0 … 1')),
                          DropdownMenuItem(
                              value: 'menosUnoUno', child: Text('−1 … 1')),
                          DropdownMenuItem(
                              value: 'imagenet',
                              child: Text('Media / desviación ImageNet'))
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _norm = v);
                        },
                      ),
                      SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Letterbox'),
                          subtitle: Text(_letterbox
                              ? 'Conserva toda la imagen con bandas negras.'
                              : 'Center-crop: recorta el centro para llenar el encuadre.'),
                          value: _letterbox,
                          onChanged: (v) => setState(() => _letterbox = v)),
                      SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Intercambiar canales RGB → BGR'),
                          subtitle: Text(_bgr
                              ? 'Orden: azul, verde, rojo'
                              : 'Orden: rojo, verde, azul'),
                          value: _bgr,
                          onChanged: (v) => setState(() => _bgr = v)),
                      const Text(
                          'Debe coincidir con el entrenamiento. Una configuración incorrecta puede producir alta confianza y poca precisión.'),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                          onPressed: _guardar,
                          icon: const Icon(Icons.save),
                          label: const Text('Guardar perfil de este modelo')),
                    ]))));
  }
}
