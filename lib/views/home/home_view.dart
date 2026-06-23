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
  // Controllers para capturar o texto dos inputs
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
    // Escuta o estado do bluetooth para saber se está conectado ou não
    final bluetoothService = context.watch<BluetoothPrinterService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Label Creator'),
        actions: [
          // Exibe o status ao lado do botão, se estiver conectado
          if (bluetoothService.isConnected)
            const Padding(
              padding: EdgeInsets.only(right: 8.0),
              child: Text(
                'Connected',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          // Botão pequeno no topo direito para abrir a tela de Bluetooth
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
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
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Informação fixa do tamanho da etiqueta
              const Center(
                child: Chip(
                  label: Text('Label Size: 50mm x 60mm'),
                  backgroundColor: Colors.blue, // Corrigido para Colors.blue
                  labelStyle: TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(height: 20),

              // Campo Texto
              TextFormField(
                controller: _textController,
                decoration: const InputDecoration(
                  labelText: 'Texto',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty)
                    return 'Please enter some text';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Campo Comprimento
              TextFormField(
                controller: _lengthController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Comprimento (mm)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty)
                    return 'Please enter length';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Campo Largura
              TextFormField(
                controller: _widthController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Largura (mm)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty)
                    return 'Please enter width';
                  return null;
                },
              ),

              const Spacer(), // Empurra o botão para a parte inferior da tela
              // Botão Imprimir no canto inferior direito
              Align(
                alignment: Alignment.bottomRight,
                child: FloatingActionButton.extended(
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      if (!bluetoothService.isConnected) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please connect to a printer first!'),
                          ),
                        );
                        return;
                      }

                      // Lógica de impressão será chamada aqui na próxima etapa
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Processing label layout...'),
                        ),
                      );
                    }
                  },
                  label: const Text('Print'),
                  icon: const Icon(Icons.print),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
