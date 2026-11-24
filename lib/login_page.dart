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
  bool _cargando = false;
  String? _error;

  Future<void> _procesarAcceso() async {
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text.trim();

    if (email.isEmpty || password.length < 6) {
      setState(() => _error = 'Ingresa un correo válido y contraseña de al menos 6 caracteres.');
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      // Desbloquea audio y pide permiso push al interactuar con el botón
      SupabaseService.sonarAlarma(urgente: false);
      await SupabaseService.pedirPermisoPush();

      if (_esRegistro) {
        // 1. Crear cuenta nueva
        final res = await SupabaseService.client.auth.signUp(
          email: email,
          password: password,
        );

        // 2. Si Supabase no devolvió sesión activa automáticamente, iniciamos sesión al instante
        if (res.session == null) {
          await SupabaseService.client.auth.signInWithPassword(
            email: email,
            password: password,
          );
        }
      } else {
        // Iniciar sesión con cuenta existente
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(32),
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
              const Icon(Icons.event_available_rounded, size: 56, color: Color(0xFF0284C7)),
              const SizedBox(height: 12),
              const Text(
                'Mi Agenda Interactiva',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 6),
              Text(
                _esRegistro ? 'Crea tu cuenta personal gratis' : 'Inicia sesión para ver tus pendientes',
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 20),

              // Selector Iniciar Sesión / Crear Cuenta
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
              const SizedBox(height: 20),

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
              const SizedBox(height: 16),
              TextField(
                controller: _passCtrl,
                obscureText: true,
                onSubmitted: (_) => _procesarAcceso(),
                style: const TextStyle(color: Color(0xFF0F172A)),
                decoration: InputDecoration(
                  labelText: 'Contraseña (mínimo 6 caracteres)',
                  labelStyle: const TextStyle(color: Color(0xFF475569)),
                  prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF0284C7)),
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
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 24),
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
    );
  }
}
