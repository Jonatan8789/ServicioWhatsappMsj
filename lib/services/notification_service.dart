import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> inicializar(String socioId) async {
    // 1. Solicitar permisos al usuario (iOS / Android 13+)
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      // 2. Obtener Token FCM del dispositivo actual
      String? token = await _fcm.getToken();
      if (token != null) {
        await _guardarTokenSocio(socioId, token);
      }

      // Escuchar cambios de token
      _fcm.onTokenRefresh.listen((nuevoToken) {
        _guardarTokenSocio(socioId, nuevoToken);
      });

      // 3. Configurar Notificaciones Locales (Primer Plano)
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);

      await _localNotifications.initialize(initializationSettings);

      // 4. Handler cuando la app está abierta en primer plano
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

  // 💾 Guardar Token en la ficha del socio en Firestore
  static Future<void> _guardarTokenSocio(String socioId, String token) async {
    await FirebaseFirestore.instance.collection('socios').doc(socioId).update({
      'fcmToken': token,
      'ultimaActualizacionToken': DateTime.now(),
    });
  }
}
