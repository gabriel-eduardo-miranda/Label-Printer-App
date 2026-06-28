import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/bluetooth_printer_service.dart';
import 'views/home/home_view.dart';

void main() {
  runApp(
    // O MultiProvider injeta nosso serviço para que as telas possam escutá-lo
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BluetoothPrinterService()),
      ],
      child: const LabelPrinterApp(),
    ),
  );
}

class LabelPrinterApp extends StatelessWidget {
  const LabelPrinterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Impressora de Etiquetas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: Colors.black,
              brightness: Brightness.light,
            ).copyWith(
              primary: Colors.black,
              secondary: Colors.black,
              surface: Colors.white,
            ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Colors.black,
          contentTextStyle: TextStyle(color: Colors.white),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Colors.black,
        ),
      ),
      // A tela inicial do aplicativo
      home: const HomeView(),
    );
  }
}
