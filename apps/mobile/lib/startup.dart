import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';

import 'app.dart';
import 'bootstrap.dart';
import 'ui/account_view_model.dart';
import 'ui/theme.dart';

/// Owns production account services; injected AwaazApp services stay caller-owned.
class AwaazStartup extends StatefulWidget {
  const AwaazStartup({super.key, this.loadAccounts = createAccountServices});

  final Future<AccountViewModel> Function() loadAccounts;

  @override
  State<AwaazStartup> createState() => _AwaazStartupState();
}

class _AwaazStartupState extends State<AwaazStartup> {
  AccountViewModel? _accounts;

  @override
  void initState() {
    super.initState();
    // Paint an actual Flutter frame before storage/Auth/native initialization.
    // This is sequencing, not an artificial timer or fabricated progress value.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Timeline.instantSync('awaaz.startup.first_frame');
      unawaited(_load());
    });
  }

  Future<void> _load() async {
    final task = TimelineTask()..start('awaaz.startup.accounts');
    AccountViewModel accounts;
    try {
      accounts = await widget.loadAccounts();
    } catch (_) {
      accounts = AccountViewModel(configurationProblem: true);
    } finally {
      task.finish();
    }
    if (!mounted) {
      accounts.dispose();
      return;
    }
    setState(() => _accounts = accounts);
  }

  @override
  void dispose() {
    _accounts?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _accounts;
    if (accounts != null) return AwaazApp(accountViewModel: accounts);
    return MaterialApp(
      title: 'Awaaz',
      debugShowCheckedModeBanner: false,
      theme: awaazTheme(false),
      home: const Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield, size: 54, color: AwaazColors.primary),
                SizedBox(height: 24),
                SizedBox(
                  key: Key('startup-loading'),
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    semanticsLabel: 'Loading Awaaz',
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
