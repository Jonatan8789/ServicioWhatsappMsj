import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../admin/servicio_mensajeria_page.dart';

class MensajeriaPage extends StatefulWidget {
  final String rolUsuario;

  const MensajeriaPage({super.key, required this.rolUsuario});

  @override
  State<MensajeriaPage> createState() => _MensajeriaPageState();
}

class _MensajeriaPageState extends State<MensajeriaPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _tituloController = TextEditingController();
  final TextEditingController _mensajeController = TextEditingController();
  final TextEditingController _busquedaSocioController =
      TextEditingController();

  final String baseUrl = 'https://servicio-whatsapp-oqua.onrender.com';

  String _filtroDestino = 'TODOS';
  String _canalSeleccionado = 'INTERNO';
  String? _deporteSeleccionado;
  bool _enviando = false;

  List<String> _listaDeportes = [];
  final List<Map<String, dynamic>> _sociosSeleccionadosManualmente = [];

  @override
  void initState() {
    super.initState();
    _cargarDeportes();
  }

  Future<void> _cargarDeportes() async {
    try {
      final doc = await _firestore
          .collection('configuracion')
          .doc('deportes')
          .get();
      if (doc.exists && doc.data() != null) {
        setState(() {
          _listaDeportes = List<String>.from(doc.data()!['lista'] ?? []);
        });
      }
    } catch (_) {}
  }

  /// Despierta/Verifica el servidor de Render antes de iniciar los envíos
  Future<bool> _asegurarServidorActivo() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/status'))
          .timeout(const Duration(seconds: 60));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Servidor Render dormido o tardando en responder: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Mensajería Multicanal & Notificaciones',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_2_rounded),
            tooltip: 'Estado / Escanear QR WhatsApp',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ServicioMensajeriaPage(rolUsuario: widget.rolUsuario),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // PANEL IZQUIERDO: REDACCION
            Expanded(
              flex: 5,
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.campaign_rounded,
                              color: Colors.blueAccent,
                              size: 28,
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Nuevo Comunicado Multicanal',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        const Text(
                          'Canal de Envío:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'INTERNO',
                              label: Text('App Interna'),
                              icon: Icon(Icons.phonelink_ring_rounded),
                            ),
                            ButtonSegment(
                              value: 'WHATSAPP',
                              label: Text('WhatsApp'),
                              icon: Icon(Icons.chat_bubble_rounded),
                            ),
                            ButtonSegment(
                              value: 'EMAIL',
                              label: Text('Email'),
                              icon: Icon(Icons.email_rounded),
                            ),
                            ButtonSegment(
                              value: 'TODOS_CANALES',
                              label: Text('Todos'),
                              icon: Icon(Icons.all_inclusive_rounded),
                            ),
                          ],
                          selected: {_canalSeleccionado},
                          onSelectionChanged: (Set<String> newSelection) {
                            setState(() {
                              _canalSeleccionado = newSelection.first;
                            });
                          },
                        ),
                        const SizedBox(height: 20),

                        const Text(
                          'Audiencia / Destinatarios:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _filtroDestino,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.people_alt_rounded),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'TODOS',
                              child: Text('Todos los Socios Activos'),
                            ),
                            DropdownMenuItem(
                              value: 'DEPORTE',
                              child: Text('Filtrar por Deporte / Actividad'),
                            ),
                            DropdownMenuItem(
                              value: 'CON_DEUDA',
                              child: Text(
                                'Socios con Cuenta Corriente Deudora',
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'APTO_VENCIDO',
                              child: Text('Socios con Apto Médico Vencido'),
                            ),
                            DropdownMenuItem(
                              value: 'MANUAL',
                              child: Text(
                                '🎯 Seleccionar Socio(s) Especifico(s)',
                              ),
                            ),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _filtroDestino = val!;
                              if (_filtroDestino != 'DEPORTE') {
                                _deporteSeleccionado = null;
                              }
                              if (_filtroDestino != 'MANUAL') {
                                _sociosSeleccionadosManualmente.clear();
                              }
                            });
                          },
                        ),

                        if (_filtroDestino == 'DEPORTE') ...[
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _deporteSeleccionado,
                            hint: const Text('Seleccionar Deporte...'),
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.sports_rounded),
                            ),
                            items: _listaDeportes
                                .map(
                                  (d) => DropdownMenuItem(
                                    value: d,
                                    child: Text(d),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) =>
                                setState(() => _deporteSeleccionado = val),
                            validator: (v) =>
                                v == null ? 'Seleccioná un deporte' : null,
                          ),
                        ],

                        if (_filtroDestino == 'MANUAL') ...[
                          const SizedBox(height: 16),
                          Autocomplete<Map<String, dynamic>>(
                            displayStringForOption: (socio) =>
                                '${socio['nombre']} (DNI: ${socio['dni']})',
                            optionsBuilder:
                                (TextEditingValue textEditingValue) async {
                                  if (textEditingValue.text.trim().isEmpty) {
                                    return const Iterable<
                                      Map<String, dynamic>
                                    >.empty();
                                  }
                                  final query = textEditingValue.text
                                      .toLowerCase();
                                  final snap = await _firestore
                                      .collection('socios')
                                      .get();
                                  return snap.docs
                                      .map(
                                        (doc) => {'id': doc.id, ...doc.data()},
                                      )
                                      .where((socio) {
                                        final nombre = (socio['nombre'] ?? '')
                                            .toString()
                                            .toLowerCase();
                                        final dni = (socio['dni'] ?? '')
                                            .toString();
                                        return nombre.contains(query) ||
                                            dni.contains(query);
                                      });
                                },
                            onSelected: (Map<String, dynamic> socioElegido) {
                              if (!_sociosSeleccionadosManualmente.any(
                                (s) => s['id'] == socioElegido['id'],
                              )) {
                                setState(() {
                                  _sociosSeleccionadosManualmente.add(
                                    socioElegido,
                                  );
                                  _busquedaSocioController.clear();
                                });
                              }
                            },
                            fieldViewBuilder:
                                (
                                  context,
                                  controller,
                                  focusNode,
                                  onEditingComplete,
                                ) {
                                  return TextField(
                                    controller: controller,
                                    focusNode: focusNode,
                                    decoration: const InputDecoration(
                                      labelText:
                                          'Buscar y agregar socio por Nombre o DNI...',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(
                                        Icons.person_search_rounded,
                                        color: Colors.teal,
                                      ),
                                    ),
                                  );
                                },
                          ),
                          const SizedBox(height: 12),

                          if (_sociosSeleccionadosManualmente.isNotEmpty)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _sociosSeleccionadosManualmente.map((
                                socio,
                              ) {
                                return Chip(
                                  avatar: const Icon(
                                    Icons.person,
                                    size: 16,
                                    color: Colors.teal,
                                  ),
                                  label: Text(
                                    '${socio['nombre']} (${socio['dni']})',
                                  ),
                                  backgroundColor: Colors.teal.shade50,
                                  deleteIcon: const Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                  ),
                                  onDeleted: () {
                                    setState(() {
                                      _sociosSeleccionadosManualmente
                                          .removeWhere(
                                            (s) => s['id'] == socio['id'],
                                          );
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                        ],

                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _tituloController,
                          decoration: const InputDecoration(
                            labelText: 'Título del Mensaje / Asunto',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.title_rounded),
                          ),
                          validator: (v) =>
                              v!.trim().isEmpty ? 'Requerido' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _mensajeController,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            labelText: 'Cuerpo del Mensaje',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) =>
                              v!.trim().isEmpty ? 'Requerido' : null,
                        ),
                        const SizedBox(height: 24),

                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F172A),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 18,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: _enviando
                                    ? null
                                    : _procesarEnvioMulticanal,
                                icon: _enviando
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.send_rounded),
                                label: Text(
                                  'Procesar Envíos ($_canalSeleccionado)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 32),

            // PANEL DERECHO: HISTORIAL
            Expanded(
              flex: 4,
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Historial de Avisos Emitidos',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: _firestore
                            .collection('mensajeria_notificaciones')
                            .orderBy('fechaEnvio', descending: true)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final docs = snapshot.data!.docs;

                          if (docs.isEmpty) {
                            return const Center(
                              child: Text('No hay mensajes emitidos.'),
                            );
                          }

                          return ListView.separated(
                            itemCount: docs.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 20),
                            itemBuilder: (context, idx) {
                              final data =
                                  docs[idx].data() as Map<String, dynamic>;
                              final DateTime fecha =
                                  (data['fechaEnvio'] as Timestamp).toDate();

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: Colors.blue.shade50,
                                  child: Icon(
                                    data['canal'] == 'WHATSAPP'
                                        ? Icons.chat_rounded
                                        : data['canal'] == 'EMAIL'
                                        ? Icons.email_rounded
                                        : Icons.mark_email_read_rounded,
                                    color: Colors.blueAccent,
                                  ),
                                ),
                                title: Text(
                                  data['titulo'] ?? 'Sin título',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      data['mensaje'] ?? '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Chip(
                                          label: Text(
                                            '${data['canal']} • ${data['audiencia']}',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          padding: EdgeInsets.zero,
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          DateFormat(
                                            'dd/MM/yyyy HH:mm',
                                          ).format(fecha),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
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

  Future<void> _procesarEnvioMulticanal() async {
    if (!_formKey.currentState!.validate()) return;

    if (_filtroDestino == 'MANUAL' && _sociosSeleccionadosManualmente.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agregá al menos un socio para enviar el comunicado.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _enviando = true);

    if (_canalSeleccionado != 'INTERNO') {
      final listo = await _asegurarServidorActivo();
      if (!listo && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'El servidor de envíos está despertando o no responde. Intenta nuevamente en 30 segundos.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => _enviando = false);
        return;
      }
    }

    try {
      List<Map<String, dynamic>> destinatarios = [];

      if (_filtroDestino == 'MANUAL') {
        destinatarios = List.from(_sociosSeleccionadosManualmente);
      } else {
        final QuerySnapshot snap = await _firestore.collection('socios').get();
        for (var doc in snap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          data['id'] = doc.id;

          if (_filtroDestino == 'TODOS') {
            destinatarios.add(data);
          } else if (_filtroDestino == 'DEPORTE' &&
              data['deporte'] == _deporteSeleccionado) {
            destinatarios.add(data);
          } else if (_filtroDestino == 'CON_DEUDA' &&
              ((data['saldoCuentaCorriente'] ?? 0) < 0)) {
            destinatarios.add(data);
          } else if (_filtroDestino == 'APTO_VENCIDO') {
            if (data['vencimientoAptoMedico'] != null) {
              DateTime venc = (data['vencimientoAptoMedico'] as Timestamp)
                  .toDate();
              if (venc.isBefore(DateTime.now())) destinatarios.add(data);
            }
          }
        }
      }

      final String titulo = _tituloController.text.trim();
      final String mensaje = _mensajeController.text.trim();

      for (var socio in destinatarios) {
        final String? telefono = socio['telefono'];
        final String? email = socio['email'];

        if ((_canalSeleccionado == 'WHATSAPP' ||
                _canalSeleccionado == 'TODOS_CANALES') &&
            telefono != null &&
            telefono.trim().isNotEmpty) {
          await _enviarWhatsAppApi(telefono, "*$titulo*\n\n$mensaje");
        }

        if ((_canalSeleccionado == 'EMAIL' ||
                _canalSeleccionado == 'TODOS_CANALES') &&
            email != null &&
            email.trim().isNotEmpty) {
          final String html =
              "<h3>$titulo</h3><p>$mensaje</p><hr/><p><small>Mensaje enviado desde la administración del club.</small></p>";
          await _enviarEmailApi(email, titulo, html);
        }
      }

      await _firestore.collection('mensajeria_notificaciones').add({
        'titulo': titulo,
        'mensaje': mensaje,
        'audiencia': _filtroDestino,
        'canal': _canalSeleccionado,
        'emisor': widget.rolUsuario,
        'fechaEnvio': Timestamp.fromDate(DateTime.now()),
        'totalImpactos': destinatarios.length,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '¡Procesados ${destinatarios.length} envíos correctamente!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        _tituloController.clear();
        _mensajeController.clear();
        setState(() => _sociosSeleccionadosManualmente.clear());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error procesando envíos: $e')));
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _enviarWhatsAppApi(String telefono, String mensaje) async {
    try {
      String limpio = telefono.replaceAll(RegExp(r'\D'), '');

      if (limpio.startsWith('0')) limpio = limpio.substring(1);
      if (limpio.startsWith('15')) limpio = limpio.substring(2);

      if (!limpio.startsWith('54')) {
        limpio = '549$limpio';
      } else if (!limpio.startsWith('549')) {
        limpio = '549${limpio.substring(2)}';
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl/send-whatsapp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': limpio, 'message': mensaje}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        debugPrint('Error enviando WhatsApp: ${response.body}');
      }
    } catch (e) {
      debugPrint('Excepción enviando WhatsApp: $e');
    }
  }

  Future<void> _enviarEmailApi(
    String email,
    String asunto,
    String mensajeHtml,
  ) async {
    try {
      await http
          .post(
            Uri.parse('$baseUrl/notificar-email'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'asunto': asunto,
              'mensajeHtml': mensajeHtml,
            }),
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      debugPrint('Excepción enviando Email: $e');
    }
  }
}
