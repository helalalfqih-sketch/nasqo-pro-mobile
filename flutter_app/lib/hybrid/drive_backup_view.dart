import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/drive_backup_service.dart';
import '../state/erp_controller.dart';

class DriveBackupView extends StatefulWidget {
  const DriveBackupView({super.key, required this.controller, required this.inspect});
  final ErpController controller;
  final Future<void> Function(XFile) inspect;

  @override
  State<DriveBackupView> createState() => _DriveBackupViewState();
}

class _DriveBackupViewState extends State<DriveBackupView> {
  final _drive = DriveBackupService();
  // An old list or a JavaScript-supplied path cannot select a remote file.
  final _displayed = <String, DriveBackupFile>{};
  int _generation = 0;
  MethodChannel? _channel;
  String? _busy, _error, _status;
  int? _progress;
  bool _overlay = false, _ready = false, _failed = false;
  Timer? _timer;
  bool get _current => mounted && ModalRoute.of(context)?.isCurrent == true;

  void _replaceFiles() {
    _generation++;
    _displayed.clear();
    for (final file in _drive.files) {
      _displayed['${_generation}_${_displayed.length}'] = file;
    }
  }

  void _unavailable() {
    if (mounted && !_failed) setState(() => _failed = true);
  }

  void _present() {
    if (!_ready || !mounted || _failed) return;
    final state = {
      'standalone': 'drive', 'dark': Theme.of(context).brightness == Brightness.dark,
      'connected': _drive.connected, 'busyAction': _busy, 'errorMsg': _error,
      'status': _status, 'progress': _progress,
      'files': [for (final row in _displayed.entries) {
        'id':row.key, 'name':row.value.name, 'size':row.value.size,
        'modifiedTime':row.value.updated, 'mimeType':'application/json',
      }],
    };
    _channel?.invokeMethod<void>('present', jsonEncode(state)).catchError((Object _) => _unavailable());
  }

  @override
  void didChangeDependencies(){super.didChangeDependencies(); _present();}

  Future<void> _attach(int id) async {
    final channel = MethodChannel('nasqo/home/$id');
    _channel = channel;
    channel.setMethodCallHandler(_handle);
    _timer = Timer(const Duration(seconds:15), _unavailable);
    try { await channel.invokeMethod<void>('start'); }
    on PlatformException { _unavailable(); }
  }

  Future<void> _handle(MethodCall call) async {
    if (call.method != 'intent' || call.arguments is! String || !_current) return;
    final raw = call.arguments as String;
    if (raw.length > 160) return;
    dynamic msg;
    try { msg=jsonDecode(raw); } on FormatException { return; }
    if (msg is! Map || msg['action'] is! String) return;
    final action = msg['action'] as String;
    if (action=='overlay' && msg.length==2 && msg['active'] is bool) {
      setState(() => _overlay=msg['active'] as bool);
      return;
    }
    if (action=='ready' && msg.length==1) { _ready=true; _present(); return; }
    if (action=='paint' && msg.length==1) {
      _timer?.cancel(); await _channel?.invokeMethod<void>('paint'); return;
    }
    if (!_ready || _busy!=null) return;
    if (action=='close' && msg.length==1) { await Navigator.of(context).maybePop(); return; }
    if (action=='disconnect' && msg.length==1) {
      _drive.disconnect(); _replaceFiles(); _error=null; _status='تم فصل الحساب.'; _present(); return;
    }
    if (!{'connect','backup','refresh','download','inspect'}.contains(action)) return;
    if (action!='connect' && !_drive.connected) return;
    final fileAction = action=='inspect' || action=='download';
    final selected = _displayed[msg['id']];
    if (fileAction ? msg.length!=2 || selected==null : msg.length!=1) return;
    setState(() {
      _busy=switch(action){'connect'=>'auth','download'=>'dl:${msg['id']}',_=>action};
      _progress=null; _status=null; _error=null;
    });
    _present();
    try {
      switch(action) {
        case 'connect': await _drive.connect(); _replaceFiles();
        case 'refresh': await _drive.refresh(); _replaceFiles();
        case 'backup': await _upload();
        case 'download':
        case 'inspect': await _download(selected!, inspect: action=='inspect');
      }
    } on DriveFailure catch(e) { _error=e.message; }
    on PlatformException catch(e) {
      _error=e.code=='CANCELLED'?'أُلغي اختيار الحساب.':'تعذّر إكمال العملية على Android. تحقق من إعداد حساب Google.';
    } catch(_) { _error='تعذّر إكمال العملية. تحقق من الاتصال وأعد المحاولة.'; }
    finally {
      if (mounted) {
        if (!_drive.connected) _replaceFiles();
        setState(() { _busy=null; _progress=null; });
        _present();
      }
    }
  }

  Future<void> _upload() async {
    final confirm=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('رفع نسخة مساحة العمل إلى Google Drive؟'),
      content:const Text('تحتوي النسخة على الحسابات والأرصدة والمستندات المحلية.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('رفع نسخة'))]));
    if (confirm!=true || !_current) return;
    final local=await widget.controller.createLocalBackup();
    await widget.controller.verifyLocalBackup(local.id);
    final bytes=await widget.controller.readLocalBackupBytes(local.id);
    await _drive.upload(local.id,bytes);
    _status='رُفعت النسخة وتطابق حجمها وبصمتها.';
    await _drive.refresh();
    _replaceFiles();
  }

  Future<void> _download(DriveBackupFile file,{required bool inspect}) async {
    final bytes=await _drive.download(file.id,progress:(done,total) {
      final percent=(100*done/(total>0?total:file.size)).floor().clamp(0,100);
      if(percent!=_progress){_progress=percent; _present();}
    });
    if (!_current) return;
    if (inspect) {
      await widget.inspect(XFile.fromData(bytes,name:file.name));
    } else {
      final suffix=file.name.toLowerCase().endsWith('.back')?'back':'json';
      const picker=MethodChannel('com.indexesstore.nasqo_qa/csv_export');
      final saved=await picker.invokeMethod<bool>('saveDriveDownload',{
        'suggestedName':'nasqo-drive-backup.$suffix','bytes':bytes});
      _status=saved==true?'تم حفظ الملف في الموقع المحدد.':'أُلغي حفظ الملف.';
    }
  }

  @override
  void dispose(){_timer?.cancel(); _channel?.setMethodCallHandler(null); _drive.dispose(); super.dispose();}

  @override
  Widget build(BuildContext context) => Scaffold(body:SafeArea(child:_failed
    ? Center(child:Column(mainAxisSize:MainAxisSize.min, children:[
        const Text('تعذّر عرض مدير Google Drive على هذا الجهاز.'),
        TextButton(onPressed:()=>Navigator.pop(context),child:const Text('رجوع'))]))
    : PopScope(canPop:_busy==null&&!_overlay,onPopInvokedWithResult:(didPop,_) {
        if(!didPop && _busy==null && _overlay){_channel?.invokeMethod<void>('endEdit');}
      },child:AndroidView(viewType:'nasqo/offline-home',layoutDirection:TextDirection.rtl,onPlatformViewCreated:_attach))));
}
