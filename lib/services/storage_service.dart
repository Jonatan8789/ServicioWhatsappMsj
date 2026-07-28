import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Subir Foto de Perfil del Socio
  /// Recibe los bytes de la imagen y el ID del socio
  Future<String> subirFotoSocio({
    required String socioId,
    required Uint8List bytes,
    required String nombreArchivo,
  }) async {
    try {
      final Reference ref = _storage
          .ref()
          .child('socios')
          .child(socioId)
          .child('perfil_$nombreArchivo');

      final UploadTask uploadTask = ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      throw Exception('Error al subir foto de perfil: $e');
    }
  }

  /// Subir Certificado de Apto Médico (Soporta JPG, PNG y PDF)
  Future<String> subirAptoMedico({
    required String socioId,
    required Uint8List bytes,
    required String nombreArchivo,
    required String contentType, // 'image/jpeg', 'application/pdf', etc.
  }) async {
    try {
      final Reference ref = _storage
          .ref()
          .child('socios')
          .child(socioId)
          .child('aptos')
          .child('${DateTime.now().millisecondsSinceEpoch}_$nombreArchivo');

      final UploadTask uploadTask = ref.putData(
        bytes,
        SettableMetadata(contentType: contentType),
      );

      final TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      throw Exception('Error al subir apto médico: $e');
    }
  }
}
