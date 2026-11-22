import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../state/erp_controller.dart';
import 'react_workspace.dart';

const reactHomeEnabled = kDebugMode &&
    bool.fromEnvironment('NASQO_REACT_HYBRID_V2', defaultValue: true);
const _allowWrites = kDebugMode &&
    bool.fromEnvironment('NASQO_REACT_HYBRID_ALLOW_WRITES', defaultValue: true);

class ReactHome extends StatefulWidget {
  const ReactHome(
      {super.key, required this.controller, required this.onLegacy});
  final ErpController controller;
  final VoidCallback onLegacy;
  @override
  State<ReactHome> createState() => _ReactHomeState();
}

class _ReactHomeState extends State<ReactHome> {
  late final _workspace =
      ReactWorkspace(widget.controller, allowWrites: _allowWrites);
  MethodChannel? _channel;
  bool _failed = false;
  Future<void> _attach(int id) async {
    final channel = MethodChannel('nasqo/home/$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'reactRequest' && call.arguments is String) {
        return _workspace.handle(call.arguments as String);
      }
      return null;
    });
    try {
      await channel.invokeMethod<void>('start');
    } on PlatformException {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _chooseHome() async {
    final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('اختيار الواجهة'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('متابعة React')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('فتح واجهة Flutter السابقة')),
              ],
            ));
    if (leave == true && mounted) widget.onLegacy();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_chooseHome());
      },
      child: Scaffold(
          body: SafeArea(
              child: _failed
                  ? Center(
                      child: TextButton(
                          onPressed: widget.onLegacy,
                          child: const Text(
                              'تعذر فتح React. فتح واجهة Flutter السابقة')))
                  : AndroidView(
                      viewType: 'nasqo/offline-home',
                      layoutDirection: TextDirection.rtl,
                      creationParams: const {'reactWorkspace': true},
                      creationParamsCodec: const StandardMessageCodec(),
                      onPlatformViewCreated: _attach))));
}
