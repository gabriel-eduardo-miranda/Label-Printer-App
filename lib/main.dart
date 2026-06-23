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
      title: 'Label Printer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, primarySwatch: Colors.blue),
      // A tela inicial do aplicativo
      home: const HomeView(),
    );
  }
}
