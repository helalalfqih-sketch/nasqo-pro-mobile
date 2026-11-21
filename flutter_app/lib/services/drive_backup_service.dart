import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'local_backup_files.dart';

class DriveBackupFile {
  const DriveBackupFile(this.id,this.name,this.size,this.updated,this.checksum);
  final String id,name,updated,checksum;
  final int size;
}

class DriveFailure implements Exception {
  const DriveFailure(this.message);
  final String message;
}

/// The WebView never receives a token, remote URL, Drive response, or database
/// bytes. This transport only talks to Google's fixed TLS origin.
class DriveBackupService {
  DriveBackupService({Future<String?> Function()? authorize, HttpClient? client})
      : _authorize=authorize ?? _nativeAuthorize, _client=client ?? HttpClient() {
    _client.connectionTimeout=const Duration(seconds:15);
    _client.idleTimeout=const Duration(seconds:15);
  }
  static const _channel=MethodChannel('com.indexesstore.nasqo_qa/drive');
  static const _limit=LocalBackupFiles.maxBackupBytes;
  final Future<String?> Function() _authorize;
  final HttpClient _client;
  String? _token;
  final _files=<String,DriveBackupFile>{};
  bool get connected=>_token!=null;
  List<DriveBackupFile> get files=>List.unmodifiable(_files.values);
  static Future<String?> _nativeAuthorize()=>_channel.invokeMethod<String>('authorize');
  Future<void> connect() async {
    final token=await _authorize();
    if(token==null || token.isEmpty) throw const DriveFailure('لم يكتمل ربط حساب Google.');
    _token=token; _files.clear(); await refresh();
  }
  void disconnect(){_files.clear();_token=null;}
  void dispose(){disconnect();_client.close(force:true);}

  Future<Uint8List> _request(String method,String path,Map<String,String> query,
      {List<int>? body,String? type,int limit=1024*1024,void Function(int,int)? progress}) async {
    final token=_token;
    if(token==null) throw const DriveFailure('اربط حساب Google أولًا.');
    final req=await _client.openUrl(method,Uri.https('www.googleapis.com',path,query)).timeout(const Duration(seconds:20));
    req.followRedirects=false;
    req.headers.set(HttpHeaders.authorizationHeader,'Bearer $token');
    if(body!=null){req.headers.set(HttpHeaders.contentTypeHeader,type!);req.contentLength=body.length;req.add(body);}
    final res=await req.close().timeout(const Duration(seconds:30));
    if(res.statusCode==401){disconnect();await res.drain<void>().timeout(const Duration(seconds:15));throw const DriveFailure('انتهت جلسة Google. أعد ربط الحساب.');}
    if(res.statusCode<200 || res.statusCode>=300){await res.drain<void>().timeout(const Duration(seconds:15));throw const DriveFailure('تعذّر الوصول إلى الملف في Google Drive. تحقق من الاتصال والصلاحية.');}
    if(res.contentLength>limit){req.abort();throw const DriveFailure('حجم الملف يتجاوز الحد المتاح.');}
    final bytes=BytesBuilder(copy:false);
    await for(final part in res.timeout(const Duration(seconds:25))){
      if(bytes.length+part.length>limit){req.abort();throw const DriveFailure('حجم الملف يتجاوز الحد المتاح.');}
      bytes.add(part);progress?.call(bytes.length,res.contentLength);
    }
    return bytes.takeBytes();
  }

  Future<void> refresh() async {
    final found=<String,DriveBackupFile>{}, seen=<String>{};
    String? page;
    do {
      final raw=await _request('GET','/drive/v3/files',{
        'q':"trashed = false and (mimeType = 'application/json' or name contains '.back' or name contains '.json')",
        'spaces':'drive','pageSize':'100','orderBy':'modifiedTime desc','fields':'nextPageToken,files(id,name,size,modifiedTime,md5Checksum)',
        if(page!=null)'pageToken':page});
      final data=jsonDecode(utf8.decode(raw)) as Map;
      for(final f in data['files'] as List){
        final id=f['id'] as String,name=f['name'] as String;
        if(!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) || !RegExp(r'\.(json|back)$',caseSensitive:false).hasMatch(name)) continue;
        found[id]=DriveBackupFile(id,name,int.tryParse(f['size']?.toString()??'')??-1,f['modifiedTime']??'',f['md5Checksum']??'');
      }
      page=data['nextPageToken'] as String?;
      if(page!=null && !seen.add(page))throw const DriveFailure('تعذّرت متابعة صفحات قائمة Drive.');
    } while(page!=null);
    _files..clear()..addAll(found);
  }

  Future<Uint8List> download(String id,{void Function(int,int)? progress}) async {
    final file=_files[id];
    if(file==null || file.size<1 || file.size>_limit)throw const DriveFailure('اختر نسخة ضمن الحجم المدعوم من القائمة.');
    final bytes=await _request('GET','/drive/v3/files/$id',{'alt':'media'},limit:_limit,progress:progress);
    if(bytes.length!=file.size || file.checksum.isNotEmpty && md5.convert(bytes).toString()!=file.checksum){
      throw const DriveFailure('لم يطابق التنزيل حجم الملف أو بصمته. حدّث القائمة وأعد التنزيل.');
    }
    return bytes;
  }

  Future<String> upload(String name,Uint8List bytes) async {
    if(bytes.isEmpty || bytes.length>_limit)throw const DriveFailure('حجم النسخة غير مدعوم.');
    final boundary='nasqo-${List.generate(18,(_)=>Random.secure().nextInt(256).toRadixString(16).padLeft(2,'0')).join()}';
    final body=BytesBuilder(copy:false)
      ..add(utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${jsonEncode({'name':name,'mimeType':'application/json','appProperties':{'nasqo':'local-backup'}})}\r\n--$boundary\r\nContent-Type: application/json\r\n\r\n'))
      ..add(bytes)..add(utf8.encode('\r\n--$boundary--\r\n'));
    final raw=await _request('POST','/upload/drive/v3/files',{'uploadType':'multipart','fields':'id,size,md5Checksum'},
      body:body.takeBytes(),type:'multipart/related; boundary="$boundary"');
    final result=jsonDecode(utf8.decode(raw)) as Map;
    if(result['id'] is! String || result['size']?.toString()!=bytes.length.toString() ||
        result['md5Checksum']!=md5.convert(bytes).toString())throw const DriveFailure('لم تؤكَّد سلامة النسخة المرفوعة. حدّث القائمة قبل إعادة المحاولة.');
    return result['id'] as String;
  }
}
