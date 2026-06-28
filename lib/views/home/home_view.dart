import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/bluetooth_printer_service.dart';
import '../bluetooth/bluetooth_connection_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _lengthController = TextEditingController();
  final TextEditingController _widthController = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _textController.dispose();
    _lengthController.dispose();
    _widthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bluetoothService = context.watch<BluetoothPrinterService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Menta e hortelã'),
        actions: [
          if (bluetoothService.isConnected)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  'Conectada',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: 'Bluetooth',
              icon: Icon(
                bluetoothService.isConnected
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth,
                color: Colors.black,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BluetoothConnectionView(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Chip(
                  label: Text('Tamanho da etiqueta: 50mm x 60mm'),
                  backgroundColor: Colors.white,
                  side: BorderSide(color: Colors.black),
                  labelStyle: TextStyle(color: Colors.black),
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _textController,
                decoration: const InputDecoration(
                  labelText: 'Texto',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Digite um texto';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _lengthController,
                decoration: const InputDecoration(
                  labelText: 'Comprimento',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Digite o comprimento';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _widthController,
                decoration: const InputDecoration(
                  labelText: 'Largura',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Digite a largura';
                  }
                  return null;
                },
              ),
              const Spacer(),
              Align(
                alignment: Alignment.bottomRight,
                child: FloatingActionButton.extended(
                  onPressed: () => _printLabel(context, bluetoothService),
                  label: const Text('Imprimir'),
                  icon: const Icon(Icons.print),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _printLabel(
    BuildContext context,
    BluetoothPrinterService bluetoothService,
  ) async {
    if (!_formKey.currentState!.validate()) return;

    if (!bluetoothService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conecte uma impressora primeiro')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Enviando etiqueta para a impressora...')),
    );

    final success = await bluetoothService.printLabel(
      text: _textController.text,
      lengthText: _lengthController.text,
      widthText: _widthController.text,
    );

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Etiqueta enviada para a impressora'
              : 'Falha ao enviar. Verifique o log do Bluetooth',
        ),
      ),
    );
  }
}
