import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../auth/auth_services.dart';

class UsuariosPage extends StatelessWidget {
  const UsuariosPage({super.key});

  // Función para actualizar el rol en la base de datos
  Future<void> _cambiarRol(
    BuildContext context,
    String uid,
    String nuevoRol,
  ) async {
    try {
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).update({
        'rol': nuevoRol,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rol actualizado a ${nuevoRol.toUpperCase()}'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al actualizar el rol'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // NUEVA FUNCIÓN: Habilitar o Deshabilitar el acceso del usuario
  Future<void> _cambiarEstadoActivo(
    BuildContext context,
    String uid,
    bool nuevoEstado,
  ) async {
    try {
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).update({
        'activo': nuevoEstado,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              nuevoEstado
                  ? 'Usuario HABILITADO con éxito'
                  : 'Usuario DESHABILITADO con éxito',
            ),
            backgroundColor: nuevoEstado ? Colors.teal : Colors.orangeAccent,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al cambiar el estado'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // Función para disparar el blanqueo de contraseña
  Future<void> _enviarReseteoContrasena(
    BuildContext context,
    String email,
  ) async {
    final exito = await AuthService().recuperarContrasena(email);
    if (context.mounted) {
      if (exito) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Mail de reseteo enviado a $email'),
            backgroundColor: Colors.teal,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al enviar el mail de reseteo'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Administración de Usuarios',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const Text(
            'Gestiona los perfiles, permisos, contraseñas y estados de acceso al sistema.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 40),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('usuarios')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('No hay usuarios registrados.'),
                  );
                }

                final usuarios = snapshot.data!.docs;

                return ListView.builder(
                  itemCount: usuarios.length,
                  itemBuilder: (context, index) {
                    var usuario = usuarios[index];
                    String uid = usuario.id;
                    String email = usuario['email'] ?? 'Sin correo';
                    String rolActual = usuario['rol'] ?? 'socio';

                    // Leemos el nuevo campo de estado (si no existe en Firebase, asumimos true por defecto)
                    bool estaActivo = true;
                    try {
                      estaActivo = usuario['activo'] ?? true;
                    } catch (e) {
                      estaActivo = true;
                    }

                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: estaActivo
                              ? const Color(0xFF1E293B).withValues(alpha: 0.1)
                              : Colors.redAccent.withValues(alpha: 0.1),
                          child: Icon(
                            Icons.person,
                            color: estaActivo
                                ? const Color(0xFF1E293B)
                                : Colors.redAccent,
                          ),
                        ),
                        title: Text(
                          email,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            decoration: estaActivo
                                ? TextDecoration.none
                                : TextDecoration.lineThrough,
                            color: estaActivo
                                ? const Color(0xFF0F172A)
                                : Colors.grey,
                          ),
                        ),
                        subtitle: Text(
                          'ID: $uid',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),

                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 1. CONTROL DE ESTADO (HABILITAR / DESHABILITAR)
                            Tooltip(
                              message: estaActivo
                                  ? 'Deshabilitar acceso'
                                  : 'Habilitar acceso',
                              child: Switch(
                                value: estaActivo,
                                activeThumbColor: Colors.teal,
                                inactiveThumbColor: Colors.redAccent,
                                onChanged: (bool nuevoValor) {
                                  _cambiarEstadoActivo(
                                    context,
                                    uid,
                                    nuevoValor,
                                  );
                                },
                              ),
                            ),

                            const SizedBox(width: 12),

                            // 2. SELECTOR DE ROL (Solo editable si el usuario está habilitado)
                            DropdownButton<String>(
                              value: rolActual,
                              icon: const Icon(
                                Icons.arrow_drop_down,
                                color: Colors.blueGrey,
                              ),
                              underline: const SizedBox(),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: estaActivo
                                    ? const Color(0xFF0F172A)
                                    : Colors.grey,
                              ),
                              onChanged: estaActivo
                                  ? (String? nuevoValor) {
                                      if (nuevoValor != null &&
                                          nuevoValor != rolActual) {
                                        _cambiarRol(context, uid, nuevoValor);
                                      }
                                    }
                                  : null, // Se deshabilita el menú si el usuario está apagado
                              items: const [
                                DropdownMenuItem(
                                  value: 'admin',
                                  child: Text('Admin'),
                                ),
                                DropdownMenuItem(
                                  value: 'profe',
                                  child: Text('Profe'),
                                ),
                                DropdownMenuItem(
                                  value: 'socio',
                                  child: Text('Socio'),
                                ),
                              ],
                            ),

                            const SizedBox(width: 12),

                            // 3. BOTÓN DE RESETEO DE CONTRASEÑA
                            Tooltip(
                              message: 'Blanquear contraseña',
                              child: IconButton(
                                icon: const Icon(
                                  Icons.lock_reset_rounded,
                                  color: Colors.blueGrey,
                                ),
                                onPressed: estaActivo
                                    ? () {
                                        _enviarReseteoContrasena(
                                          context,
                                          email,
                                        );
                                      }
                                    : null, // Bloqueado si está inactivo
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
