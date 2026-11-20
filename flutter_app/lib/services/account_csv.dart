typedef ImportedAccount = ({String name,String phone,double opening});

double parseAccountAmount(String input) {
  var text = input.trim().replaceAll('٬','').replaceAll('٫','.');
  for (var i=0;i<10;i++) {
    text=text.replaceAll('٠١٢٣٤٥٦٧٨٩'[i], '$i').replaceAll('۰۱۲۳۴۵۶۷۸۹'[i], '$i');
  }
  if(text.isEmpty) return 0;
  final number=double.tryParse(text.replaceAll(',',''));
  if(number==null || !number.isFinite || number<0) throw const FormatException('أدخل مبلغًا موجبًا أو صفرًا.');
  return number;
}

List<ImportedAccount> readAccountCsv(String input) {
  final text=input.replaceFirst(RegExp(r'^\uFEFF'),'');
  final result=<ImportedAccount>[];
  var header=true, quoted=false, closed=false;
  final row=<String>[];
  var field=StringBuffer();
  void finishField() {
    row.add(field.toString().trim());
    field=StringBuffer();
    closed=false;
  }
  void finishRow() {
    finishField();
    if(row.any((v)=>v.isNotEmpty)) {
      if(header) { header=false; }
      else if(row[0].isNotEmpty) {
        result.add((name:row[0],phone:row.length>1?row[1]:'',
          opening:parseAccountAmount(row.length>2?row[2]:'')));
      }
    }
    row.clear();
  }
  for(var i=0;i<text.length;i++) {
    final ch=text[i];
    if(quoted) {
      if(ch!='"') {field.write(ch); continue;}
      if(i+1<text.length && text[i+1]=='"') {field.write('"'); i++; continue;}
      quoted=false;closed=true;
    } else if(ch==',') {
      finishField();
    } else if(ch=='\r'||ch=='\n') {
      if(ch=='\r' && i+1<text.length && text[i+1]=='\n') i++;
      finishRow();
    } else if(ch=='"' && field.isEmpty && !closed) {
      quoted=true;
    } else if(closed && ch.trim().isNotEmpty || ch=='"') {
      throw const FormatException('تنسيق علامات الاقتباس في الملف غير صالح.');
    } else {
      field.write(ch);
    }
  }
  if(quoted) throw const FormatException('حقل غير مكتمل في ملف الحسابات.');
  finishRow();
  if(result.isEmpty) throw const FormatException('الملف لا يحتوي على حسابات بعد صف العناوين.');
  return result;
}
