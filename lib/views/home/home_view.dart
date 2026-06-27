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
        title: const Text('Criador de etiquetas'),
        actions: [
          if (bluetoothService.isConnected)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  'Conectada',
                  style: TextStyle(
                    color: Colors.green,
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
                color: bluetoothService.isConnected ? Colors.blue : Colors.grey,
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
                  backgroundColor: Colors.blue,
                  labelStyle: TextStyle(color: Colors.white),
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
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Comprimento (mm)',
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
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Largura (mm)',
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

    final length = double.tryParse(_lengthController.text.replaceAll(',', '.'));
    final width = double.tryParse(_widthController.text.replaceAll(',', '.'));

    if (length == null || width == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Digite medidas validas')));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Enviando etiqueta para a impressora...')),
    );

    final success = await bluetoothService.printLabel(
      text: _textController.text,
      widthMm: width,
      heightMm: length,
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
