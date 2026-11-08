import 'package:flutter/material.dart';

import 'app.dart';
import 'services/foreground_keep_alive.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ForegroundKeepAlive.initCommunicationPort();
  runApp(const AppRoot());
}
