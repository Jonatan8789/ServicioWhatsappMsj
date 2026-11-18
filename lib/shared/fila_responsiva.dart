import 'package:flutter/material.dart';

/// Fila de campos de formulario (TextFormField/Dropdown/etc.) que se
/// apilan verticalmente por debajo de [breakpoint] de ancho en vez de
/// compartir un Row fijo — muchos diálogos de administración tenían 2-3
/// campos codo a codo que quedaban ilegibles en un teléfono.
Widget filaResponsiva(
  List<Widget> campos, {
  List<int>? flexes,
  double breakpoint = 500,
  double espaciado = 12,
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final bool esMovil = constraints.maxWidth < breakpoint;
      if (esMovil) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < campos.length; i++) ...[
              campos[i],
              if (i < campos.length - 1) SizedBox(height: espaciado),
            ],
          ],
        );
      }
      return Row(
        children: [
          for (int i = 0; i < campos.length; i++) ...[
            Expanded(
              flex: flexes != null ? flexes[i] : 1,
              child: campos[i],
            ),
            if (i < campos.length - 1) SizedBox(width: espaciado),
          ],
        ],
      );
    },
  );
}
