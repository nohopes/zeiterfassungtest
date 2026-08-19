import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/auth_service.dart';
import '../services/push_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/profile_section.dart';

/// Zeigt den eingeloggten Nutzer, einen Logout-Button, und für Admins
/// zusätzlich eine einfache Verwaltung der Kollegen-Konten.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  List<Map<String, dynamic>>? _users;
  bool _loadingUsers = false;
  String? _usersError;
  bool _subscribingPush = false;
  bool _pushEnabled = false;

  @override
  void initState() {
    super.initState();
    if (AuthService.instance.isAdmin) {
      _loadUsers();
    }
  }

  Uri _apiUri(String pathAndQuery) => Uri.base.resolve(pathAndQuery);

  Future<void> _loadUsers() async {
    setState(() {
      _loadingUsers = true;
      _usersError = null;
    });
    try {
      final response = await http.get(
        _apiUri('/api/admin/users'),
        headers: AuthService.instance.authHeaders,
      );
      if (response.statusCode != 200) {
        throw Exception('Serverfehler (${response.statusCode})');
      }
      final list = (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _users = list;
        _loadingUsers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _usersError = 'Nutzerliste konnte nicht geladen werden';
        _loadingUsers = false;
      });
    }
  }

  Future<void> _deleteUser(int id, String username) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nutzer löschen?'),
        content: Text('"$username" wird dauerhaft gelöscht und sofort abgemeldet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final response = await http.delete(
      _apiUri('/api/admin/users/$id'),
      headers: AuthService.instance.authHeaders,
    );
    if (!mounted) return;
    if (response.statusCode != 200) {
      final map = jsonDecode(response.body) as Map<String, dynamic>?;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(map?['error'] as String? ?? 'Löschen fehlgeschlagen')),
      );
      return;
    }
    _loadUsers();
  }

  Future<void> _openAddUserDialog() async {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    var isAdmin = false;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Neuen Kollegen anlegen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(labelText: 'Benutzername'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Passwort (mind. 4 Zeichen)'),
              ),
              CheckboxListTile(
                value: isAdmin,
                onChanged: (v) => setDialogState(() => isAdmin = v ?? false),
                title: const Text('Admin-Rechte'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (error != null) ...[
                const SizedBox(height: 4),
                Text(error!, style: const TextStyle(color: AppColors.rust)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () async {
                final response = await http.post(
                  _apiUri('/api/admin/users'),
                  headers: {
                    ...AuthService.instance.authHeaders,
                    'content-type': 'application/json',
                  },
                  body: jsonEncode({
                    'username': usernameController.text.trim(),
                    'password': passwordController.text,
                    'isAdmin': isAdmin,
                  }),
                );
                if (response.statusCode == 200) {
                  if (context.mounted) Navigator.of(context).pop();
                  _loadUsers();
                  return;
                }
                final map = jsonDecode(response.body) as Map<String, dynamic>?;
                setDialogState(() {
                  error = map?['error'] as String? ?? 'Anlegen fehlgeschlagen';
                });
              },
              child: const Text('Anlegen'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enablePushReminders() async {
    setState(() => _subscribingPush = true);
    final error = await PushService.instance.subscribe();
    if (!mounted) return;
    setState(() {
      _subscribingPush = false;
      _pushEnabled = error == null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'Erinnerungen sind jetzt aktiv.')),
    );
  }

  Future<void> _sendTestNotification() async {
    final ok = await PushService.instance.sendTestNotification();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Test-Benachrichtigung verschickt - sollte gleich ankommen.'
              : 'Test-Benachrichtigung konnte nicht verschickt werden.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Konto')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.amberDim,
                  child: Icon(Icons.person, color: AppColors.amber),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth.username ?? '',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (auth.isAdmin)
                        Text(
                          'Admin',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.inkMuted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => auth.logout(),
            icon: const Icon(Icons.logout),
            label: const Text('Abmelden'),
          ),
          const SizedBox(height: 28),
          Text('ERINNERUNGEN', style: AppTextStyles.eyebrow(AppColors.inkMuted)),
          const SizedBox(height: 4),
          Text(
            'Erinnert werktags um 16:30 Uhr, falls für heute noch kein '
            'Eintrag im Logbuch existiert.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkMuted),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _subscribingPush ? null : _enablePushReminders,
            icon: _subscribingPush
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.notifications_active_outlined),
            label: const Text('Erinnerungen aktivieren'),
          ),
          if (_pushEnabled) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _sendTestNotification,
              icon: const Icon(Icons.send_outlined, size: 18),
              label: const Text('Test-Benachrichtigung senden'),
            ),
          ],
          const SizedBox(height: 28),
          const ProfileSection(),
          if (auth.isAdmin) ...[
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'NUTZERVERWALTUNG',
                  style: AppTextStyles.eyebrow(AppColors.inkMuted),
                ),
                IconButton(
                  icon: const Icon(Icons.person_add_outlined),
                  tooltip: 'Neuen Kollegen anlegen',
                  onPressed: _openAddUserDialog,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loadingUsers)
              const Center(child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ))
            else if (_usersError != null)
              Text(_usersError!, style: const TextStyle(color: AppColors.rust))
            else if (_users != null)
              ..._users!.map(
                (u) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(border: Border.all(color: AppColors.line)),
                  child: ListTile(
                    title: Text(u['username'] as String),
                    subtitle: (u['isAdmin'] == true) ? const Text('Admin') : null,
                    trailing: (u['id'] == auth.userId)
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppColors.rust),
                            onPressed: () =>
                                _deleteUser(u['id'] as int, u['username'] as String),
                          ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
