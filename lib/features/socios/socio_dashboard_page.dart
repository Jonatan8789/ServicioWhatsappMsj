import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import '../paddle/reserva_cancha_screen.dart';

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

class _SocioDashboardPageState extends State<SocioDashboardPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _inicializarNotificacionesPush();
  }

  // 🔔 INICIALIZACIÓN DE NOTIFICACIONES PUSH (FCM)
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

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);

      await _localNotifications.initialize(initializationSettings);

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

  // 🏆 DIÁLOGO DE INSCRIPCIÓN A TORNEO
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
        content: SizedBox(
          width: 400,
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

  // 💳 PESTAÑA HISTORIAL DE PAGOS & CUENTA CORRIENTE
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
                  padding: EdgeInsets.symmetric(vertical: 30),
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

  // 🏆 PESTAÑA DE TORNEOS DISPONIBLES
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
    return DefaultTabController(
      length: 3,
      child: Scaffold(
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
          bottom: const TabBar(
            indicatorColor: Colors.tealAccent,
            indicatorWeight: 3,
            labelColor: Colors.tealAccent,
            unselectedLabelColor: Colors.white60,
            tabs: [
              Tab(icon: Icon(Icons.calendar_today_rounded), text: 'Turnos'),
              Tab(icon: Icon(Icons.emoji_events_rounded), text: 'Torneos'),
              Tab(icon: Icon(Icons.receipt_long_rounded), text: 'Mi Cuenta'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const ReservaCanchaScreen(),
            _buildVistaTorneos(),
            _buildVistaCuentaCorriente(),
          ],
        ),
      ),
    );
  }
}
