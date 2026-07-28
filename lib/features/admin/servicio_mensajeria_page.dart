import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ServicioMensajeriaPage extends StatefulWidget {
  const ServicioMensajeriaPage({super.key});

  @override
  State<ServicioMensajeriaPage> createState() => _ServicioMensajeriaPageState();
}

class _ServicioMensajeriaPageState extends State<ServicioMensajeriaPage> {
  bool _cargando = true;
  bool _conectado = false;
  String? _qrBase64;
  final String _backendUrl = 'http://localhost:3000';

  @override
  void initState() {
    super.initState();
    _consultarEstado();
  }

  Future<void> _consultarEstado() async {
    setState(() => _cargando = true);
    try {
      final res = await http.get(Uri.parse('$_backendUrl/status'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _conectado = data['connected'] ?? false;
          _qrBase64 = data['qr'];
        });
      } else {
        setState(() => _conectado = false);
      }
    } catch (e) {
      setState(() => _conectado = false);
    } finally {
      setState(() => _cargando = false);
    }
  }

  Future<void> _desvincularWhatsapp() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cerrar Sesión de WhatsApp?'),
        content: const Text('El servicio generará un nuevo QR para vincular otra cuenta.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desvincular'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _cargando = true);
    try {
      await http.post(Uri.parse('$_backendUrl/logout'));
      await Future.delayed(const Duration(seconds: 3));
      await _consultarEstado();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al desvincular: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Estado del Servidor de Mensajería'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _consultarEstado,
            tooltip: 'Actualizar Estado',
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tarjeta de Estado Principal
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Row(
                        children: [
                          Icon(
                            _conectado ? Icons.check_circle_rounded : Icons.error_rounded,
                            size: 48,
                            color: _conectado ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _conectado ? 'Servicio de WhatsApp Activo' : 'WhatsApp Desconectado',
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _conectado
                                      ? 'El sistema puede enviar mensajes automáticos a los socios.'
                                      : 'Requiere escanear el código QR para habilitar envíos.',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          if (_conectado)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                              icon: const Icon(Icons.logout_rounded),
                              label: const Text('Desvincular Cuenta'),
                              onPressed: _desvincularWhatsapp,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Visualizador de QR (Si está desconectado)
                  if (!_conectado)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
                          ],
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Vincular número de WhatsApp',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Abrí WhatsApp en tu celular > Dispositivos vinculados > Escanear QR',
                              style: TextStyle(fontSize: 13, color: Colors.grey),
                            ),
                            const SizedBox(height: 20),
                            if (_qrBase64 != null)
                              Image.memory(
                                base64Decode(_qrBase64!.split(',').last),
                                width: 260,
                                height: 260,
                              )
                            else
                              Column(
                                children: const [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 12),
                                  Text('Generando nuevo código QR...'),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}