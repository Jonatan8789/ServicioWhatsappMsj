import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../paddle/reserva_cancha_screen.dart';
import '../paddle/partidos_abiertos_page.dart';
import '../natatorio/socio_reserva_andarivel_page.dart';
import '../gimnasio/socio_clases_gimnasio_page.dart';
import '../gimnasio/mi_rutina_page.dart';
import '../../shared/mercado_pago_dialog.dart';

class SocioDashboardPage extends StatefulWidget {
  final String socioId;
  final Map<String, dynamic> socioData;

  const SocioDashboardPage({
    super.key,
    required this.socioId,
    required this.socioData,
  });

  @override
  State<SocioDashboardPage> createState() => _SocioDashboardPageState();
}

class _SocioDashboardPageState extends State<SocioDashboardPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // 🔗 DEEP LINKS: antes tocar una notificación push sólo abría la app en
  // la pestaña por defecto (Turnos) — ahora, según el dato 'ruta' que manda
  // la Cloud Function (ver functions/notificaciones.js), salta directo a
  // la pestaña correspondiente (Torneos, Turnos, etc.). Necesita un
  // TabController explícito (antes era un DefaultTabController implícito)
  // para poder llamar animateTo() desde fuera del árbol de widgets.
  static const int _tabCount = 8;
  late final TabController _tabController;

  static const Map<String, int> _rutaATabIndex = {
    'turnos': 0,
    'reservas_canchas': 0,
    'partido_abierto': 1,
    'natatorio': 2,
    'andarivel': 2,
    'clases_gimnasio': 3,
    'mi_rutina': 4,
    'torneos': 5,
    'mi_cuenta': 6,
    'cuenta_corriente': 6,
    'mi_carnet': 7,
  };

  void _irATabPorRuta(String? ruta) {
    if (ruta == null) return;
    final index = _rutaATabIndex[ruta];
    if (index != null) _tabController.animateTo(index);
  }

  void _manejarAperturaPorNotificacion(RemoteMessage? message) {
    if (message == null) return;
    _irATabPorRuta(message.data['ruta']);
  }

  // 🔒 QR Dinámico anti-capturas: antes el carnet mostraba un QR estático
  // con el DNI en texto plano — una captura de pantalla de ese QR servía
  // para siempre, así que cualquiera podía compartir/reusar la foto del
  // carnet de otro socio para entrar al gimnasio. Ahora el QR también lleva
  // un token aleatorio que se renueva cada 25s y se valida contra Firestore
  // al escanear (ver control_acceso_page.dart): una captura vieja deja de
  // sernir pasados esos segundos.
  static const Duration _rotacionQr = Duration(seconds: 25);
  Timer? _qrRotationTimer;
  String _qrTokenActual = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    _inicializarNotificacionesPush();
    _rotarTokenQr();
    _qrRotationTimer = Timer.periodic(_rotacionQr, (_) => _rotarTokenQr());
  }

  @override
  void dispose() {
    _qrRotationTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _rotarTokenQr() async {
    final nuevoToken = const Uuid().v4();
    final expira = DateTime.now().add(_rotacionQr + const Duration(seconds: 5));
    try {
      await _firestore.collection('socios').doc(widget.socioId).update({
        'qrTokenActual': nuevoToken,
        'qrTokenExpira': Timestamp.fromDate(expira),
      });
      if (mounted) setState(() => _qrTokenActual = nuevoToken);
    } catch (_) {
      // Si falla (sin conexión momentánea), el carnet sigue mostrando el
      // último token válido hasta el próximo intento.
    }
  }

  Future<void> _inicializarNotificacionesPush() async {
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      String? token = await _fcm.getToken();
      if (token != null) {
        await _guardarTokenSocio(token);
      }

      _fcm.onTokenRefresh.listen((nuevoToken) {
        _guardarTokenSocio(nuevoToken);
      });

      // 🔗 App abierta en background y el socio toca la notificación.
      FirebaseMessaging.onMessageOpenedApp.listen(
        _manejarAperturaPorNotificacion,
      );
      // 🔗 App estaba totalmente cerrada y se abrió DESDE la notificación.
      final mensajeInicial = await _fcm.getInitialMessage();
      _manejarAperturaPorNotificacion(mensajeInicial);

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);

      await _localNotifications.initialize(
        initializationSettings,
        // 🔗 Notificación recibida con la app ABIERTA (foreground): la
        // mostramos nosotros mismos vía flutter_local_notifications, así
        // que el tap tampoco pasa por onMessageOpenedApp — hay que leer el
        // 'payload' que le mandamos abajo con la misma ruta.
        onDidReceiveNotificationResponse: (response) {
          _irATabPorRuta(response.payload);
        },
      );

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        RemoteNotification? notification = message.notification;
        AndroidNotification? android = message.notification?.android;

        if (notification != null && android != null) {
          _localNotifications.show(
            notification.hashCode,
            notification.title,
            notification.body,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'oqua_push_channel',
                'Notificaciones Oqua Club',
                channelDescription:
                    'Canal principal de avisos y turnos de Oqua Club',
                importance: Importance.max,
                priority: Priority.high,
                icon: '@mipmap/ic_launcher',
              ),
            ),
            payload: message.data['ruta'],
          );
        }
      });
    }
  }

  Future<void> _guardarTokenSocio(String token) async {
    await _firestore.collection('socios').doc(widget.socioId).update({
      'fcmToken': token,
      'ultimaActualizacionToken': FieldValue.serverTimestamp(),
    });
  }

  // 📤 SUBIDA DE COMPROBANTE DE TRANSFERENCIA
  Future<void> _subirComprobanteTransferencia(String reservaId) async {
    final resultado = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );

    if (resultado != null && resultado.files.first.bytes != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Subiendo comprobante...')));

      try {
        final fileBytes = resultado.files.first.bytes!;
        final fileName = resultado.files.first.name;
        final ext = fileName.contains('.') ? fileName.split('.').last : 'jpg';
        final storageRef = FirebaseStorage.instance.ref().child(
          'comprobantes_reservas/${reservaId}_${DateTime.now().millisecondsSinceEpoch}.$ext',
        );

        final uploadTask = await storageRef.putData(
          fileBytes,
          SettableMetadata(
            contentType: ext == 'pdf' ? 'application/pdf' : 'image/$ext',
          ),
        );
        final downloadUrl = await uploadTask.ref.getDownloadURL();

        await _firestore.collection('reservas_canchas').doc(reservaId).update({
          'estadoReserva': 'Comprobante Adjunto',
          'comprobanteUrl': downloadUrl,
          'fechaAdjuntoComprobante': DateTime.now(),
        });

        // 📲 Aviso por WhatsApp a los Administradores
        //
        // 🚨 Antes apuntaba a '/send-whatsapp-admin', un endpoint que nunca
        // existió en el bridge de WhatsApp (404 silencioso, atrapado por el
        // catch vacío). Ahora pasa por la Cloud Function
        // 'notificarWhatsappSocio' (tipo: 'notificar_admin'), que valida que
        // quien llama es un socio real y manda SIEMPRE al teléfono de
        // administrador configurado del lado del servidor — nunca a uno que
        // mande el cliente.
        try {
          final callable = FirebaseFunctions.instance.httpsCallable(
            'notificarWhatsappSocio',
          );
          final resp = await callable.call({
            'tipo': 'notificar_admin',
            'mensaje':
                '📑 *NUEVO COMPROBANTE ADJUNTO*\n'
                '• Reserva: $reservaId\n'
                '• Socio: ${widget.socioData['nombre']}\n'
                '• Estado: Comprobante Adjunto\n'
                '• Ver enlace: $downloadUrl',
          });
          if (resp.data['success'] != true) {
            debugPrint('⚠️ Aviso WhatsApp a admin no enviado: ${resp.data['error']}');
          }
        } catch (e) {
          debugPrint('⚠️ Error al avisar por WhatsApp: $e');
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '✅ Comprobante adjuntado. En revisión por administración.',
              ),
              backgroundColor: Colors.teal,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al subir comprobante: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _mostrarDialogoInscripcionTorneo(
    String torneoId,
    Map<String, dynamic> torneo,
  ) {
    final parejaNombreCtrl = TextEditingController();
    final parejaDniCtrl = TextEditingController();
    final parejaTelefonoCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(
              Icons.emoji_events_rounded,
              color: Colors.amber,
              size: 28,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Inscripción: ${torneo['nombre'] ?? 'Torneo'}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          // 📱 antes era SizedBox(width: 400): en un teléfono angosto eso
          // fuerza el diálogo a 400px reales en vez de dejarlo achicarse.
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Categoría: ${torneo['categoria'] ?? 'Única'} | Rama: ${torneo['rama'] ?? 'Libre'}',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Datos de tu Pareja de Juego:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: parejaNombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre y Apellido del Compañero/a',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: parejaDniCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'DNI del Compañero/a',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: parejaTelefonoCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono / WhatsApp',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone_android_outlined),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0A3B43),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('Confirmar Inscripción'),
            onPressed: () async {
              if (parejaNombreCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Ingresá el nombre de tu pareja de juego.'),
                  ),
                );
                return;
              }

              Navigator.pop(ctx);

              await _firestore
                  .collection('torneos')
                  .doc(torneoId)
                  .collection('parejas_inscriptas')
                  .add({
                    'jugador1Id': widget.socioId,
                    'jugador1Nombre': widget.socioData['nombre'] ?? 'Socio',
                    'jugador1Dni': widget.socioData['dni'] ?? '',
                    'jugador2Nombre': parejaNombreCtrl.text.trim(),
                    'jugador2Dni': parejaDniCtrl.text.trim(),
                    'jugador2Telefono': parejaTelefonoCtrl.text.trim(),
                    'fechaInscripcion': DateTime.now(),
                    'estadoPago': 'Pendiente',
                  });

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ ¡Inscripción registrada con éxito!'),
                    backgroundColor: Colors.teal,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildVistaCuentaCorriente() {
    final double saldo =
        (widget.socioData['saldoCuentaCorriente'] as num?)?.toDouble() ?? 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: saldo < 0 ? Colors.red.shade900 : const Color(0xFF0A3B43),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Estado de Cuenta Corriente',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      saldo < 0
                          ? 'Deuda: \$${saldo.abs().toStringAsFixed(2)} ARS'
                          : 'Saldo A Favor: \$${saldo.toStringAsFixed(2)} ARS',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Icon(
                  saldo < 0
                      ? Icons.warning_amber_rounded
                      : Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ],
            ),
          ),
          if (saldo < 0) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.qr_code_2_rounded),
                label: const Text('Pagar deuda con Mercado Pago'),
                onPressed: () => mostrarDialogoCobroMercadoPago(
                  context,
                  concepto: 'Pago de cuota social',
                  cloudFunction: 'crearCobroMercadoPagoSocio',
                  parametrosExtra: const {'tipo': 'cuota'},
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),

          // LISTADO DE TURNOS Y RESERVAS PENDIENTES CON ADJUNTO
          const Text(
            'Mis Reservas de Canchas & Comprobantes:',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),

          StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('reservas_canchas')
                .where('socioId', isEqualTo: widget.socioId)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());

              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Text(
                  'No tenés reservas registradas.',
                  style: TextStyle(color: Colors.grey),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                itemBuilder: (context, idx) {
                  final resData = docs[idx].data() as Map<String, dynamic>;
                  final String resId = docs[idx].id;
                  final String estado =
                      resData['estadoReserva'] ?? 'Confirmada';
                  final String? comprobanteUrl = resData['comprobanteUrl'];
                  final bool pagadoConMP = resData['estadoPagoMP'] == 'Aprobado';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      children: [
                        ListTile(
                          title: Text(
                            '${resData['cancha']} (${resData['horaInicio']}:00 hs)',
                          ),
                          subtitle: Text(
                            'Estado: $estado • Monto: \$${resData['precio']} ARS',
                          ),
                          trailing: estado == 'Confirmada'
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                )
                              : ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0A3B43),
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: Icon(
                                    comprobanteUrl != null
                                        ? Icons.find_in_page
                                        : Icons.upload_file,
                                    size: 16,
                                  ),
                                  label: Text(
                                    comprobanteUrl != null
                                        ? 'Reemplazar'
                                        : 'Adjuntar Pago',
                                  ),
                                  onPressed: () =>
                                      _subirComprobanteTransferencia(resId),
                                ),
                        ),
                        if (pagadoConMP)
                          const Padding(
                            padding: EdgeInsets.only(
                              left: 16,
                              right: 16,
                              bottom: 10,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '✅ Pagado con Mercado Pago',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 12,
                              right: 12,
                              bottom: 10,
                            ),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.indigo,
                                ),
                                icon: const Icon(
                                  Icons.qr_code_2_rounded,
                                  size: 16,
                                ),
                                label: const Text('Pagar con Mercado Pago'),
                                onPressed: () => mostrarDialogoCobroMercadoPago(
                                  context,
                                  concepto: 'Alquiler de cancha',
                                  cloudFunction: 'crearCobroMercadoPagoSocio',
                                  parametrosExtra: {
                                    'tipo': 'reserva_cancha',
                                    'reservaId': resId,
                                  },
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),

          const SizedBox(height: 24),
          const Text(
            'Movimientos y Consumos Recientes:',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),

          StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('socios')
                .doc(widget.socioId)
                .collection('cuenta_corriente')
                .orderBy('fecha', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());

              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'No hay movimientos registrados en tu cuenta.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                itemBuilder: (context, idx) {
                  final mov = docs[idx].data() as Map<String, dynamic>;
                  final double monto =
                      (mov['monto'] as num?)?.toDouble() ?? 0.0;
                  final DateTime fecha = (mov['fecha'] as Timestamp).toDate();

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: Icon(
                        monto < 0
                            ? Icons.remove_circle_outline
                            : Icons.add_circle_outline,
                        color: monto < 0 ? Colors.red : Colors.green,
                      ),
                      title: Text(
                        mov['detalle'] ?? mov['tipo'] ?? 'Movimiento',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        DateFormat('dd/MM/yyyy HH:mm').format(fecha),
                      ),
                      trailing: Text(
                        '\$${monto.abs().toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: monto < 0 ? Colors.red : Colors.green.shade800,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // 🪪 CARNET DIGITAL — el QR codifica el DNI del socio, el mismo valor que
  // usa control_acceso_page.dart al buscar por DNI, para que un solo código
  // sirva tanto para el escáner de cámara como para un lector USB tipo
  // teclado.
  Widget _buildVistaCarnet() {
    final String dni = (widget.socioData['dni'] ?? '').toString();
    final String fotoUrl = (widget.socioData['fotoUrl'] ?? '').toString();
    final bool matriculaAlDia = widget.socioData['matriculaAlDia'] == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: const Color(0xFF0A3B43).withValues(
                      alpha: 0.1,
                    ),
                    backgroundImage: fotoUrl.isNotEmpty
                        ? CachedNetworkImageProvider(fotoUrl)
                        : null,
                    child: fotoUrl.isEmpty
                        ? const Icon(
                            Icons.person,
                            size: 40,
                            color: Color(0xFF0A3B43),
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.socioData['nombre'] ?? 'Socio',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'N° ${widget.socioData['numeroSocio'] ?? widget.socioId}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: dni.isNotEmpty
                        ? QrImageView(
                            // "dni::token": el token rota cada 25s (ver
                            // _rotarTokenQr) y lo valida control_acceso_page
                            // .dart — una captura de pantalla vieja de este
                            // QR deja de servir pasado ese lapso.
                            data: _qrTokenActual.isEmpty
                                ? dni
                                : '$dni::$_qrTokenActual',
                            version: QrVersions.auto,
                            size: 200,
                          )
                        : const SizedBox(
                            width: 200,
                            height: 200,
                            child: Center(
                              child: Text(
                                'Tu ficha no tiene DNI cargado.\nPedile a recepción que lo complete.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: matriculaAlDia
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      matriculaAlDia ? 'Matrícula al día' : 'Matrícula pendiente',
                      style: TextStyle(
                        color: matriculaAlDia
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Presentá este código en el lector de acceso de recepción.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVistaTorneos() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('torneos').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'No hay torneos abiertos actualmente.',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: docs.length,
          itemBuilder: (context, idx) {
            final tId = docs[idx].id;
            final tData = docs[idx].data() as Map<String, dynamic>;

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          tData['nombre'] ?? 'Torneo de Pádel',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Chip(
                          label: Text(
                            tData['estado'] ?? 'Abierto',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          backgroundColor: const Color(0xFF0A3B43),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Categoría: ${tData['categoria']} | Rama: ${tData['rama']}',
                      style: const TextStyle(
                        color: Colors.blueGrey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Divider(height: 24),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A3B43),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(45),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () =>
                          _mostrarDialogoInscripcionTorneo(tId, tData),
                      icon: const Icon(Icons.how_to_reg_rounded, size: 18),
                      label: const Text(
                        'Inscribirme con Pareja',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('Hola, ${widget.socioData['nombre'] ?? 'Socio'}'),
        backgroundColor: const Color(0xFF0A3B43),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.tealAccent,
          indicatorWeight: 3,
          labelColor: Colors.tealAccent,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.calendar_today_rounded), text: 'Turnos'),
            Tab(icon: Icon(Icons.groups_rounded), text: 'Partido Abierto'),
            Tab(icon: Icon(Icons.pool_rounded), text: 'Natatorio'),
            Tab(icon: Icon(Icons.fitness_center_rounded), text: 'Clases Gym'),
            Tab(icon: Icon(Icons.assignment_rounded), text: 'Mi Rutina'),
            Tab(icon: Icon(Icons.emoji_events_rounded), text: 'Torneos'),
            Tab(icon: Icon(Icons.receipt_long_rounded), text: 'Mi Cuenta'),
            Tab(icon: Icon(Icons.qr_code_2_rounded), text: 'Mi Carnet'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const ReservaCanchaScreen(),
          const PartidosAbiertosPage(),
          const SocioReservaAndarivelPage(),
          const SocioClasesGimnasioPage(),
          const MiRutinaPage(),
          _buildVistaTorneos(),
          _buildVistaCuentaCorriente(),
          _buildVistaCarnet(),
        ],
      ),
    );
  }
}
