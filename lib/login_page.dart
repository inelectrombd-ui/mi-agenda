import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _esRegistro = false;
  bool _verContrasena = false;
  bool _aceptoTerminos = false;
  bool _cargando = false;
  String? _error;
  Future<void> _procesarAcceso() async {
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text.trim();

    if (email.isEmpty || password.length < 6) {
      setState(() => _error = 'Ingresa un correo válido y contraseña de al menos 6 caracteres.');
      return;
    }

    if (_esRegistro && !_aceptoTerminos) {
      setState(() => _error = 'Debes aceptar el Aviso de Privacidad y los Términos de Uso para crear tu cuenta.');
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      SupabaseService.sonarAlarma(urgente: false);
      await SupabaseService.pedirPermisoPush();

      if (_esRegistro) {
        final res = await SupabaseService.client.auth.signUp(
          email: email,
          password: password,
          data: {
            'acepto_terminos': true,
            'version_terminos': 'v1.0-2026',
          },
        );

        if (res.session == null) {
          await SupabaseService.client.auth.signInWithPassword(
            email: email,
            password: password,
          );
        }
      } else {
        await SupabaseService.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
      }
    } on AuthException catch (e) {
      setState(() => _error = 'Error: ${e.message}');
    } catch (e) {
      setState(() => _error = 'Ocurrió un error inesperado al conectar.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }
  void _mostrarDocumentoLegal({required String titulo, required String contenido}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.gavel_rounded, color: Color(0xFF0284C7)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                titulo,
                style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Text(
              contenido,
              style: const TextStyle(color: Color(0xFF334155), fontSize: 13.5, height: 1.5),
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
            ),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  static const String _textoAvisoPrivacidad = '''
AVISO DE PRIVACIDAD INTEGRAL (v1.0-2026)

1. Responsable y Finalidad:
Mi Agenda Interactiva es una herramienta digital gratuita para la organización personal. El único dato personal identificable que recabamos es tu correo electrónico, utilizado exclusivamente para crear tu cuenta, autenticar tu acceso y aislar tus notas para que nadie más pueda verlas.

2. Datos Almacenados:
Las notas, fechas y recordatorios que registres se almacenan de forma cifrada en la nube (Supabase) vinculados únicamente a tu identificador privado de usuario. No vendemos, alquilamos ni compartimos tu correo o información con terceros ni con fines publicitarios.

3. Derechos ARCO y Eliminación Total:
En cumplimiento con la Ley Federal de Protección de Datos Personales en Posesión de los Particulares (LFPDPPP), puedes acceder, rectificar o eliminar por completo tu cuenta y todos tus registros en cualquier momento directamente desde el botón "Eliminar mi cuenta" dentro de la aplicación, lo cual borra de forma irreversible tu usuario y tus notas.
''';
  static const String _textoTerminosDeslinde = '''
TÉRMINOS DE USO Y DESLINDE DE RESPONSABILIDAD (v1.0-2026)

1. Uso "Tal Cual" (As-Is):
Esta aplicación se proporciona de forma gratuita como herramienta auxiliar de productividad personal, "tal cual" y "según disponibilidad", sin garantías de disponibilidad ininterrumpida.

2. Deslinde sobre Alarmas y Notificaciones:
Las alertas visuales, sonoras y notificaciones push dependen del navegador web, permisos del sistema operativo, conexión a internet, estado de batería y configuraciones de silencio o ahorro de energía de tu dispositivo. El desarrollador no se hace responsable por retrasos, bloqueos del navegador o fallos en la entrega de notificaciones.

3. Prohibición de Uso Crítico:
No utilices esta agenda como único medio para recordatorios médicos, toma de medicamentos vitales, emergencias, plazos legales o financieros críticos donde una falla pueda ocasionar daños personales o patrimoniales.

4. Responsabilidad del Contenido:
Cada usuario es el único responsable de la veracidad, legalidad y respaldo de las notas que almacena en su cuenta, así como de mantener la confidencialidad de su contraseña.
''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 430),
            padding: const EdgeInsets.all(28),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.event_available_rounded, size: 54, color: Color(0xFF0284C7)),
                const SizedBox(height: 10),
                const Text(
                  'Mi Agenda Interactiva',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 4),
                Text(
                  _esRegistro ? 'Crea tu cuenta personal gratis' : 'Inicia sesión para ver tus pendientes',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text('Iniciar Sesión')),
                        selected: !_esRegistro,
                        selectedColor: const Color(0xFF0284C7),
                        backgroundColor: const Color(0xFFF1F5F9),
                        labelStyle: TextStyle(
                          color: !_esRegistro ? Colors.white : const Color(0xFF334155),
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (_) => setState(() {
                          _esRegistro = false;
                          _error = null;
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text('Crear Cuenta')),
                        selected: _esRegistro,
                        selectedColor: const Color(0xFF0284C7),
                        backgroundColor: const Color(0xFFF1F5F9),
                        labelStyle: TextStyle(
                          color: _esRegistro ? Colors.white : const Color(0xFF334155),
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (_) => setState(() {
                          _esRegistro = true;
                          _error = null;
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Color(0xFF0F172A)),
                  decoration: InputDecoration(
                    labelText: 'Correo electrónico',
                    labelStyle: const TextStyle(color: Color(0xFF475569)),
                    prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF0284C7)),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                TextField(
                  controller: _passCtrl,
                  obscureText: !_verContrasena,
                  onSubmitted: (_) => _procesarAcceso(),
                  style: const TextStyle(color: Color(0xFF0F172A)),
                  decoration: InputDecoration(
                    labelText: 'Contraseña (mínimo 6 caracteres)',
                    labelStyle: const TextStyle(color: Color(0xFF475569)),
                    prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF0284C7)),
                    suffixIcon: IconButton(
                      tooltip: _verContrasena ? 'Ocultar contraseña' : 'Ver contraseña',
                      icon: Icon(
                        _verContrasena ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: const Color(0xFF64748B),
                      ),
                      onPressed: () => setState(() => _verContrasena = !_verContrasena),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                  ),
                ),
                if (_esRegistro) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _aceptoTerminos ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _aceptoTerminos,
                          activeColor: const Color(0xFF0284C7),
                          onChanged: (val) => setState(() => _aceptoTerminos = val ?? false),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 10, bottom: 6, right: 6),
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(color: Color(0xFF334155), fontSize: 12.5, height: 1.4),
                                children: [
                                  const TextSpan(text: 'He leído y acepto el '),
                                  TextSpan(
                                    text: 'Aviso de Privacidad',
                                    style: const TextStyle(
                                      color: Color(0xFF0284C7),
                                      fontWeight: FontWeight.bold,
                                      decoration: TextDecoration.underline,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () => _mostrarDocumentoLegal(
                                            titulo: 'Aviso de Privacidad',
                                            contenido: _textoAvisoPrivacidad,
                                          ),
                                  ),
                                  const TextSpan(text: ' y los '),
                                  TextSpan(
                                    text: 'Términos y Deslinde de Responsabilidad',
                                    style: const TextStyle(
                                      color: Color(0xFF0284C7),
                                      fontWeight: FontWeight.bold,
                                      decoration: TextDecoration.underline,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () => _mostrarDocumentoLegal(
                                            titulo: 'Términos y Deslinde',
                                            contenido: _textoTerminosDeslinde,
                                          ),
                                  ),
                                  const TextSpan(text: '.'),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13)),
                ],
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _cargando ? null : _procesarAcceso,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _cargando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            _esRegistro ? 'Registrarme y Entrar' : 'Entrar a mi Agenda',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
