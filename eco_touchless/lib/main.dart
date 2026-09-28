import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app/eco_touchless_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  runApp(const EcoTouchlessApp());
}
