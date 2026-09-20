import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app/resiclasia_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  runApp(const ResiClasIAApp());
}
