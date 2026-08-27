import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ServicioMensajeriaPage extends StatefulWidget {
  final String rolUsuario;

  const ServicioMensajeriaPage({super.key, this.rolUsuario = 'ADMIN'});

  @override
  State<ServicioMensajeriaPage> createState() => _ServicioMensajeriaPageState();
}

class _ServicioMensajeriaPageState extends State<ServicioMensajeriaPage> {
  bool _cargando = true;
  bool _conectado = false;
  String? _qrBase64;
  Timer? _timerPolling;

  // 📌 URL de producción en Render
  final String _backendUrl = 'https://servicio-whatsapp-oqua.onrender.com';

  // Permisos para funciones administrativas (ver/generar QR y desvincular)
  bool get _esAdmin {
    final rol = widget.rolUsuario.toUpperCase();
    return rol.contains('ADMIN') ||
        rol.contains('DIRECTOR') ||
        rol == 'SUPERUSER';
  }

  @override
  void initState() {
    super.initState();
    _consultarEstado();
    _iniciarPollingAutorefresco();
  }

  @override
  void dispose() {
    _timerPolling?.cancel();
    super.dispose();
  }

  /// Consulta silenciosa cada 5 segundos para detectar el momento en que se escanea el QR
  void _iniciarPollingAutorefresco() {
    _timerPolling = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_conectado && !_cargando) {
        _consultarEstado(silencioso: true);
      }
    });
  }

  Future<void> _consultarEstado({bool silencioso = false}) async {
    if (!silencioso) setState(() => _cargando = true);
    try {
      final res = await http
          .get(Uri.parse('$_backendUrl/status'))
          .timeout(const Duration(seconds: 60));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final nuevoConectado = data['connected'] ?? false;
        final nuevoQr = data['qr'];

        if (mounted) {
          setState(() {
            _conectado = nuevoConectado;
            _qrBase64 = nuevoQr;
          });
        }
      } else {
        if (mounted) setState(() => _conectado = false);
      }
    } catch (e) {
      if (mounted) setState(() => _conectado = false);
    } finally {
      if (!silencioso && mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  /// Solicita un nuevo código QR o fuerza la reconexión (Exclusivo Admin)
  Future<void> _solicitarNuevoQR() async {
    if (!_esAdmin) return;

    setState(() => _cargando = true);
    try {
      final res = await http
          .post(Uri.parse('$_backendUrl/qr'))
          .timeout(const Duration(seconds: 60));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _qrBase64 = data['qr'];
          _conectado = data['connected'] ?? false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nuevo código QR solicitado correctamente.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        await _consultarEstado();
      }
    } catch (e) {
      await _consultarEstado();
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _desvincularWhatsapp() async {
    if (!_esAdmin) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cerrar Sesión de WhatsApp?'),
        content: const Text(
          'El servicio desvinculará la cuenta actual y generará un nuevo código QR para enlazar otra cuenta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desvincular'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _cargando = true);
    try {
      await http
          .post(Uri.parse('$_backendUrl/logout'))
          .timeout(const Duration(seconds: 30));
      await Future.delayed(const Duration(seconds: 3));
      await _consultarEstado();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al desvincular: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Estado & Vinculación WhatsApp'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          if (_esAdmin)
            IconButton(
              icon: const Icon(Icons.qr_code_scanner_rounded),
              tooltip: 'Generar / Forzar QR',
              onPressed: _cargando ? null : _solicitarNuevoQR,
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _consultarEstado(),
            tooltip: 'Actualizar Estado',
          ),
        ],
      ),
      body: _cargando
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Conectando con el servidor en Render...'),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(32.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_esAdmin)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.amber),
                            SizedBox(width: 8),
                            Text(
                              'Modo de solo lectura. Solo usuarios Administradores pueden generar QR o desvincular.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Tarjeta de Estado
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Row(
                          children: [
                            Icon(
                              _conectado
                                  ? Icons.check_circle_rounded
                                  : Icons.error_rounded,
                              size: 48,
                              color: _conectado ? Colors.green : Colors.orange,
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _conectado
                                        ? 'Servicio de WhatsApp Activo'
                                        : 'WhatsApp Desconectado',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _conectado
                                        ? 'El sistema está listo para enviar comunicados y notificaciones a los socios.'
                                        : 'Escaneá el código QR a continuación para habilitar la cuenta.',
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            if (_conectado && _esAdmin)
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                                icon: const Icon(Icons.logout_rounded),
                                label: const Text('Desvincular Cuenta'),
                                onPressed: _desvincularWhatsapp,
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Panel QR
                    if (!_conectado)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'Vincular número de WhatsApp',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '1. Abrí WhatsApp en el celular corporativo/admin.\n'
                                '2. Menú (3 puntos o Ajustes) > Dispositivos vinculados.\n'
                                '3. Toca "Vincular un dispositivo" y escaneá este código QR.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 24),

                              if (_qrBase64 != null) ...[
                                Image.memory(
                                  base64Decode(_qrBase64!.split(',').last),
                                  width: 280,
                                  height: 280,
                                ),
                                const SizedBox(height: 12),
                                const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Esperando escaneo... (Actualización automática)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.teal,
                                      ),
                                    ),
                                  ],
                                ),
                              ] else
                                Column(
                                  children: [
                                    const CircularProgressIndicator(),
                                    const SizedBox(height: 16),
                                    const Text('Generando código QR...'),
                                    if (_esAdmin) ...[
                                      const SizedBox(height: 12),
                                      ElevatedButton.icon(
                                        onPressed: _solicitarNuevoQR,
                                        icon: const Icon(Icons.qr_code_2),
                                        label: const Text('Solicitar QR Ahora'),
                                      ),
                                    ],
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
