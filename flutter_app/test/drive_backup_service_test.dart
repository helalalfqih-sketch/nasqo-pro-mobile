import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/services/drive_backup_service.dart';

class _Headers extends Fake implements HttpHeaders {
  final values=<String,Object>{};
  @override void set(String name,Object value,{bool preserveHeaderCase=false}){values[name]=value;}
}
class _Reply extends Stream<List<int>> implements HttpClientResponse {
  _Reply(this.data,{this.statusCode=200});
  final List<int> data;
  @override final int statusCode;
  @override int get contentLength=>data.length;
  @override StreamSubscription<List<int>> listen(void Function(List<int>)? onData,{Function? onError,void Function()? onDone,bool? cancelOnError})=>
    Stream.value(data).listen(onData,onError:onError,onDone:onDone,cancelOnError:cancelOnError);
  @override dynamic noSuchMethod(Invocation invocation)=>super.noSuchMethod(invocation);
}
class _Request extends Fake implements HttpClientRequest {
  _Request(this.method,this.uri,this.respond);
  final String method;
  @override final Uri uri;
  final _Reply Function(_Request) respond;
  @override final _Headers headers=_Headers();
  @override bool followRedirects=true;
  @override int contentLength=-1;
  final bytes=<int>[];
  @override void add(List<int> data)=>bytes.addAll(data);
  @override Future<HttpClientResponse> close()async=>respond(this);
}
class _Client extends Fake implements HttpClient {
  _Client(this.respond);
  final _Reply Function(_Request) respond;
  final history=<_Request>[];
  @override Duration? connectionTimeout;
  @override Duration idleTimeout=Duration.zero;
  @override Future<HttpClientRequest> openUrl(String method,Uri url)async{
    final request=_Request(method,url,respond);history.add(request);return request;
  }
  @override void close({bool force=false}){}
}
_Reply jsonReply(Object value)=>_Reply(utf8.encode(jsonEncode(value)));
void main(){
  test('only granted HTTPS files are downloaded, with size and digest checks',()async{
    final bytes=utf8.encode('{"fixture":1}'), wrong=utf8.encode('{"fixture":2}');
    bool corrupt=false,expired=false;
    Map<String,Object> meta(String id)=>{'id':id,'name':'اختبار-$id.json','size':bytes.length.toString(),'md5Checksum':md5.convert(bytes).toString()};
    final http=_Client((request){
      expect(request.uri.scheme,'https');expect(request.uri.host,'www.googleapis.com');
      expect(request.headers.values['authorization'],'Bearer synthetic-consent');expect(request.followRedirects,isFalse);
      if(expired)return _Reply([] ,statusCode:401);
      if(request.uri.queryParameters['alt']=='media')return _Reply(corrupt?wrong:bytes);
      if(request.uri.queryParameters.containsKey('pageToken'))return jsonReply({'files':[meta('second')]});
      return jsonReply({'files':[meta('first')],'nextPageToken':'two'});
    });
    final drive=DriveBackupService(authorize:()async=>'synthetic-consent',client:http);
    addTearDown(drive.dispose);
    await expectLater(drive.download('first'),throwsA(isA<DriveFailure>()));
    expect(http.history,isEmpty);
    await drive.connect();expect(drive.files.map((f)=>f.id),['first','second']);
    await expectLater(drive.download('unknown'),throwsA(isA<DriveFailure>()));
    final progress=<int>[];
    expect(await drive.download('second',progress:(n,_)=>progress.add(n)),bytes);
    expect(progress.last,bytes.length);
    corrupt=true;await expectLater(drive.download('second'),throwsA(isA<DriveFailure>()));
    expired=true;await expectLater(drive.refresh(),throwsA(isA<DriveFailure>()));
    expect(drive.connected,isFalse);expect(drive.files,isEmpty);
  });
  test('new backup upload succeeds only after Google returns matching size and checksum',()async{
    final bytes=Uint8List.fromList(utf8.encode('{"synthetic":true}'));
    bool bad=false;
    final http=_Client((request){
      if(request.method=='GET')return jsonReply({'files':[]});
      expect(request.method,'POST');expect(request.uri.path,'/upload/drive/v3/files');
      expect(request.uri.queryParameters['uploadType'],'multipart');
      expect(utf8.decode(request.bytes),contains('{"synthetic":true}'));
      return jsonReply({'id':'review-file','size':'${bytes.length}','md5Checksum':bad?'wrong':md5.convert(bytes).toString()});
    });
    final drive=DriveBackupService(authorize:()async=>'synthetic-consent',client:http);addTearDown(drive.dispose);
    await drive.connect();expect(await drive.upload('synthetic.json',bytes),'review-file');
    bad=true;await expectLater(drive.upload('synthetic.json',bytes),throwsA(isA<DriveFailure>()));
  });
}
