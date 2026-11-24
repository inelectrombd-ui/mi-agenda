import 'dart:js_interop';
import 'package:supabase_flutter/supabase_flutter.dart';

// Puentes hacia las funciones JavaScript de web/index.html
@JS('solicitarPermisoNotificacion')
external JSPromise<JSString> _solicitarPermisoJS();

@JS('mostrarNotificacionPush')
external void _mostrarNotificacionJS(JSString titulo, JSString cuerpo);

@JS('reproducirSonidoAlarma')
external void _reproducirSonidoJS(JSBoolean urgente);

@JS('actualizarTituloPestana')
external void _actualizarTituloJS(JSString texto);

@JS('agregarAlarmaCalendarioNativo')
external void _agregarAlarmaCalendarioJS(JSString titulo, JSString descripcion, JSString fechaIsoUtc);

class SupabaseService {
  static const String supabaseUrl = 'https://jjpezgqkunuwtqilphol.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_5ddfAxfzhba2zcjsZg6b4Q_a2zu8gL_';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;

  // Métodos de alertas web y nativas
  static Future<String> pedirPermisoPush() async {
    final res = await _solicitarPermisoJS().toDart;
    return res.toDart;
  }

  static void enviarNotificacionPush(String titulo, String cuerpo) {
    _mostrarNotificacionJS(titulo.toJS, cuerpo.toJS);
  }

  static void sonarAlarma({bool urgente = false}) {
    _reproducirSonidoJS(urgente.toJS);
  }

  static void cambiarTituloPestana(String texto) {
    _actualizarTituloJS(texto.toJS);
  }

  static void agendarEnCalendarioNativo(String titulo, String descripcion, DateTime fechaUtc) {
    _agregarAlarmaCalendarioJS(
      titulo.toJS,
      descripcion.toJS,
      fechaUtc.toIso8601String().toJS,
    );
  }
}
