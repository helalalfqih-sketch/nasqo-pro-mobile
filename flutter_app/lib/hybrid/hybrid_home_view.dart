import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../screens/home_account_views.dart';
import '../state/erp_controller.dart';
import 'home_presentation.dart';

class HybridHomeView extends StatefulWidget {
  const HybridHomeView(
      {super.key,
      required this.controller,
      required this.openModule,
      required this.showNative});
  final ErpController controller;
  final Future<void> Function(String) openModule;
  final VoidCallback showNative;
  @override
  State<HybridHomeView> createState() => HybridHomeState();
}

class HybridHomeState extends State<HybridHomeView> {
  late final view = HomePresentation(widget.controller);
  MethodChannel? _channel;
  bool _ready = false, _editing = false, _overlay = false, _failed = false;
  bool _opening = false;
  late bool _dark;
  Timer? _startup;
  Future<void> _pending = Future.value();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dark = Theme.of(context).brightness == Brightness.dark;
    _refresh();
  }

  void _error() {
    _startup?.cancel();
    if (mounted && !_failed) setState(() => _failed = true);
  }

  Future<void> _attach(int id) async {
    final channel = MethodChannel('nasqo/home/$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (call.method != 'intent' ||
          call.arguments is! String ||
          !mounted ||
          _failed) {
        return;
      }
      final msg = view.parse(call.arguments as String);
      if (msg == null) return;
      switch (msg['action']) {
        case 'ready':
          if (!_ready) {
            _ready = true;
            _refresh();
          }
        case 'paint':
          _startup?.cancel();
          await channel.invokeMethod<void>('paint');
        case 'editing':
          if (_editing != msg['active']) {
            setState(() => _editing = msg['active'] as bool);
          }
        case 'overlay':
          if (_overlay != msg['active']) {
            setState(() => _overlay = msg['active'] as bool);
          }
        case 'currency':
        case 'scroll':
        case 'layout':
          _pending = _pending.then((_) async {
            await view.savePreference(msg);
            if (msg['action'] == 'currency') _refresh();
          }).catchError((Object error) {
            _error();
          });
        case 'tile':
        case 'navigate':
          if (_opening || ModalRoute.of(context)?.isCurrent != true) return;
          _opening = true;
          try {
            final id = msg['id'] as String;
            final route = msg['action'] == 'tile' ? homeDestinations[id]! : id;
            await widget.openModule(route);
            if (mounted &&
                (route == 'measurements' || route == 'measurement-new')) {
              await view.loadMeasurementCount();
              _refresh();
            }
          } finally {
            _opening = false;
          }
        case 'group':
          await _pending;
          if (!mounted || _failed) return;
          if (ModalRoute.of(context)?.isCurrent != true) return;
          final group = msg['id'] as int;
          final currency = view.currencyFor(group);
          final category = view.categoryFor(group);
          await Navigator.of(context).push<void>(MaterialPageRoute(
              builder: (_) => category == null
                  ? HomeAccountsView.restoredGroup(
                      controller: widget.controller,
                      groupId: group,
                      initialCurrency: currency)
                  : HomeAccountsView(
                      controller: widget.controller,
                      category: category,
                      initialCurrency: currency)));
        case 'haptic':
          await HapticFeedback.selectionClick();
      }
    });
    try {
      await view.load();
      if (!mounted) return;
      _startup = Timer(const Duration(seconds: 15), _error);
      await channel.invokeMethod<void>('start');
    } catch (_) {
      _error();
    }
  }

  void _refresh() {
    if (_ready && !_failed && mounted) {
      _channel
          ?.invokeMethod<void>('present', jsonEncode(view.snapshot(_dark)))
          .catchError((Object error) {
        _error();
      });
    }
  }

  @override
  void dispose() {
    _startup?.cancel();
    widget.controller.removeListener(_refresh);
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('تعذّر فتح الرئيسية الهجينة على هذا الجهاز.'),
        TextButton(
            onPressed: widget.showNative,
            child: const Text('فتح الرئيسية الأصلية')),
      ]));
    }
    return PopScope(
        canPop: !_editing && !_overlay,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && (_editing || _overlay)) {
            _channel?.invokeMethod<void>('endEdit');
          }
        },
        child: AndroidView(
            viewType: 'nasqo/offline-home',
            layoutDirection: TextDirection.rtl,
            onPlatformViewCreated: _attach));
  }
}
