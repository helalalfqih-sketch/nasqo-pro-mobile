from collections import Counter
from pathlib import Path
import csv
import io
import json
import os
import re
import shutil
import statistics

def read(path):
    return json.loads(Path(path).read_text())
def write(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
def require(condition, reason):
    if not condition:
        raise ValueError(reason)
qa = Path('qa')
logs = qa / 'test_logs'
pics = qa / 'screenshots/hybrid-work'
run = int(os.environ['NASQO_TEST_RUN'])
src = os.environ['NASQO_SOURCE']
repo = os.environ['GITHUB_REPOSITORY']
tmp = Path(os.environ['RUNNER_TEMP'])
candidates = list((tmp/'review-download').rglob('android.json'))
require(len(candidates) == 1, 'exactly one Android report required')
root = candidates[0].parent
report = read(candidates[0])
checks = report['checks']
visual = report['visual']
expected = {'installed_debug_apk','offline_react_home','single_react_header_and_footer','eight_metrics_same_sqlite_input','metric_long_press_pin_color_cold_open_reset','quick_actions_drawer_back','trial_balance_separate_currencies_and_nested_back','currency_change','native_statement_back','native_keyboard_and_back','offline_restart_scroll_and_filter','android_drag_reorder_and_cold_open','long_press_pin_and_hardware_back','frame_and_memory_samples','accounting_and_stock_integrity','preferences_after_cold_reopen','react_document_saved_lines_zoom_and_back'}
require(expected <= set(checks) and len(checks['eight_metrics_same_sqlite_input'])==8 and 'failure' not in report, 'missing Android acceptance evidence')
require(src == report['source'] == report['test_revision'], 'APK and test revision differ')
finance=checks['accounting_and_stock_integrity']
require(read(root/'baseline-table-digests.json')==read(root/'after-table-digests.json') and finance['foreign_key_errors']==0, 'business rows or FK changed')
review_log=(root/'review-log.txt').read_text(errors='replace')
require('FATAL EXCEPTION' not in review_log and 'Uncaught ' not in review_log, 'uncaught runtime exception')
refs=read(root/'fixed-web-reports/result.json')
for theme in ('light','dark'):
    before,after = [refs['evidence'][v+'-'+theme] for v in ('before','after')]
    require(before==after and len(after['names'])==10,'reports behavior')
    require((root/('fixed-web-reports/before-'+theme+'.png')).read_bytes()==(root/('fixed-web-reports/after-'+theme+'.png')).read_bytes(),'reports pixels')
    shutil.copyfile(root/('browser-check/embedded-'+theme+'-document.png'),pics/('embedded-'+theme+'-document.png'))
    shutil.copyfile(root/('fixed-web-reports/before-'+theme+'.png'),pics/('reference-848a555/reports-'+theme+'.png'))
    shutil.copyfile(root/('fixed-web-reports/after-'+theme+'.png'),pics/('reports-'+theme+'.png'))
for name in ('comparison-light','comparison-dark','diff-light','diff-dark','android-trial-all','android-quick','native-statement','native-keyboard','android-statement-document'):
    shutil.copyfile(root/(name+'.png'),pics/(name+'.png'))
if (root/'android-trial-eur.png').exists():
    shutil.copyfile(root/'android-trial-eur.png',pics/'android-trial-eur.png')
for old,new in [('android.json','work-android.json'),('baseline-table-digests.json','work-android-baseline.json'),('after-table-digests.json','work-android-after.json'),('fixed-web-reports/result.json','work-reports.json')]:
    shutil.copyfile(root/old,logs/new)
gfx=(root/'gfxinfo-scroll.txt').read_text()
def gfx_count(pattern):
    return int(re.search(pattern,gfx,re.M).group(1))
total=gfx_count(r'^Total frames rendered:\s*(\d+)')
janky=gfx_count(r'^Janky frames:\s*(\d+)')
frames={'frames':total,'janky_frames':janky,'janky_percent':round(100*janky/total,2),'mode':'debug APK, API 35 emulator','source':'adb shell dumpsys gfxinfo after input swipes'}
for pct in ('50th','90th','95th','99th'):
    match=re.search('^'+pct+r' percentile:\s*(\d+)ms',gfx,re.M)
    if match:
        frames[pct+'_ms']=int(match.group(1))
wv=(root/'webview-version.txt').read_text()
webview=re.search(r'Current WebView package \(name, version\): \(([^)]+)\)',wv).group(1)
performance={'webview':webview,'frames':frames,'median_verified_react_paint_ms':statistics.median(report['paint_ms']),'react_paint_samples_ms':report['paint_ms'],'android_fatal_or_uncaught_js_in_sample':False}
write(logs/'work-android-performance.json',performance)
build=(tmp/'offline-apk.log').read_text(errors='replace')
browser=(tmp/'offline-device.log').read_text(errors='replace')
flutter_counts=[int(n) for n in re.findall(r'\+(\d+): All tests passed!',build)]
require(len(flutter_counts)==2 and flutter_counts[0]>=279 and flutter_counts[1]>=5,'Flutter results not found')
full,focused=flutter_counts
def severities(name):
    return len(re.findall(r'\s'+name+r'\s+[•-]\s+',build))
analysis={k:severities(k) for k in ('info','warning','error')}
node=[int(n) for n in re.findall(r'(?:ℹ|#) pass (\d+)',browser)]
require(23 in node and 4 in node and re.search(r'\b10 passed\s*\(',browser) and '28 protected files' in browser,'web tests incomplete')
require(analysis['error']==0,'analyzer errors')
tests={'flutter':{'passed':full,'failed':0,'focused_bridge_trial_receipts':focused,'focused_subset':True,'analyzer':analysis},'react':{'unit_passed':23,'mobile_interactions_passed':10,'web_packaging_tests_passed':4,'protected_mobile_runtime_files':28,'report_routes':10,'report_modes':2,'fixed_reference':refs['base'],'menu_image_and_actions_identical':True,'document_browser_themes':2},'android':{'run':run,'api':35,'checks':len(checks),'offline':True,'result':'passed','business_tables':finance,'visual':visual},'physical_android':'pending'}
write(logs/'work-integrated-tests.json',tests)
release_meta=read(tmp/'signed-status.json')['workflow_runs'][0]
candidate=10000+release_meta['run_number']+1
public_code=None
manifest=tmp/'public-version.json'
if manifest.exists() and manifest.stat().st_size:
    try:
        data=read(manifest)
        for key in ('versionCode','version_code','buildNumber','latestVersionCode'):
            if isinstance(data,dict) and data.get(key) is not None:
                public_code=int(data[key])
                break
    except (ValueError,TypeError):
        pass
base=refs['base']
action='https://github.com/'+repo+'/actions/runs/'+str(run)
shots='qa/screenshots/hybrid-work/'
test_file='qa/hybrid_home/android_review.py'
db_test='flutter_app/test/financial_form_receipt_test.dart'
entries={}
matrix=qa/'PARITY_MATRIX.csv'
with matrix.open(newline='') as f:
    reader=csv.reader(f); header=next(reader); rows=list(reader)
def update(id,note,shot,status='VERIFIED',target=None,tests=None):
    row=next(r for r in rows if r[0]==id)
    row[5]='الوضع الهجين على Android'
    if target: row[9]=target
    row[10:14]=[status,note,tests or test_file,shots+shot]
    row[14]=base
def append(id,item,context,trigger,result,effect,target,note,tests,shot,react='src/Prototype.tsx'):
    require(all(r[0]!=id for r in rows),'duplicate row '+id)
    rows.append([id,'scenario',react,'',item,context,trigger,result,effect,target,'VERIFIED',note,tests,shot,base])
hybrid='qa/hybrid_home/host.tsx'
update('HOME-01','ثبت سحب الاختصار وإعادة فتحه على Android. غطى المتصفح ترتيب الشبكتين باللمس.','android-quick.png',target=hybrid,tests=test_file+'; qa/hybrid_home/browser.mjs')
update('HOME-02','حفظت SQLite الترتيب والتثبيت واللون واستعادت التفضيلات بعد الإغلاق. يغطي المتصفح الإخفاء والإظهار وإعادة الافتراضي.','comparison-light.png',target='flutter_app/lib/hybrid/home_presentation.dart',tests=test_file+'; qa/hybrid_home/browser.mjs')
update('HOME-03','ثُبّت مؤشر واختصار وأعيد فتح التطبيق ثم استُعيد الوضع الافتراضي.','android-quick.png',target=hybrid)
update('AB-02','عرض المشغّل أرصدة منفصلة للعملات على بيانات SQLite. تحقق تمرير «الكل» من قسمي الدولار واليورو.','android-trial-all.png',target='flutter_app/lib/hybrid/home_presentation.dart',tests=test_file+'; flutter_app/test/hybrid_home_test.dart')
update('AB-03','فتح المسار الهجين المجموعة ثم الحساب بعملته. استعاد الرجوع كشف الحساب ثم القائمة والمرشح.','native-statement.png',target='flutter_app/lib/hybrid/directory_presentation.dart',tests=test_file+'; qa/hybrid_home/browser.mjs')
update('AB-06','اجتاز APK المقارنة الفاتحة والداكنة في RTL والتمرير واستعادة المرشح على محاكي Android 35. تجربة الهاتف الفعلي في HY-05.','comparison-dark.png',target=hybrid)
update('HY-01','رسمت React الشريطين وجدول المجموعات والمؤشرات الثماني والاختصارات الـ24 مرة واحدة في وضع الطيران.','comparison-light.png',target=hybrid)
hy1=next(r for r in rows if r[0]=='HY-01')
hy1[6:8]=['فتح APK التصحيح من الصفر في وضع الطيران','شريط علوي وسفلي واحد، والمؤشرات والاختصارات والجدول في RTL']
update('HW-01','تحقق Android من شريط واحد في كل طرف ومن فتح الإجراءات والرجوع.','android-quick.png',target=hybrid)
update('HW-02','طابقت التسميات والقيم الثماني مرجع React باستخدام عينة SQLite نفسها بالعملة وطرف الرصيد.','comparison-dark.png')
update('HW-03','يغطي Android ضغط المؤشر المطول واللون والافتراضي وسحب اختصار وإعادة الفتح. يغطي المتصفح التخصيص للشبكتين.','android-quick.png',tests=test_file+'; qa/hybrid_home/browser.mjs')
update('HW-05','اجتاز مسار المجموعة والمورد والكشف المحاكي. اجتاز محدد الحساب والمخازن والبحث المتصفح. الطباعة ومحدد الملفات في انتظار الهاتف.','native-statement.png','IMPLEMENTED_UNVERIFIED',tests=test_file+'; qa/hybrid_home/browser.mjs')
append('HW-06','ميزان المراجعة واختيار الكل','تقرير محلي','اختر الكل ومرّر وارجع','قائمتا الدولار واليورو مستقلتان','قراءة SQLite','flutter_app/lib/services/trial_balance_summary.dart','غطى Flutter العملة والتاريخ والصناديق وتحويل الصندوق الداخلي. غطى Android اختيار الكل والرجوع المتداخل.',test_file+'; flutter_app/test/trial_balance_summary_test.dart',shots+'android-trial-all.png')
append('INT-01','إيصال الترحيل ومنع التكرار','بيع وشراء وسند نقدي','أرسل بالتوازي وأعد فتح قاعدة SQLite ثم كرر','نفس معرّف القيد وحركة واحدة لكل طرف صحيح','كتابة ذرية داخل Flutter','flutter_app/lib/services/posting_receipt.dart','ثُبت رفض حمولة متغيرة وصندوق بعملة مختلفة. فُحصت البصمات والمفاتيح الخارجية والرصيد في الدليل والميزان.',db_test,'','')
append('INT-02','معاينة المستند المحفوظ من الكشف','مكوّن React الأصلي وSQLite','افتح الفاتورة وكبّرها ثم ارجع','الصفوف والمبلغ من المستند المحدد والعودة إلى الكشف','قراءة محلية','flutter_app/lib/hybrid/hybrid_document_view.dart','تحقق المتصفح من 3 × 8.5 ومن غياب الصفوف المصطنعة للمستند القديم، وغطى Android مستند العينة ثم العودة. طباعة الهاتف ضمن فجوات المراجعة.',test_file+'; qa/hybrid_home/browser.mjs; '+db_test,shots+'android-statement-document.png')
with matrix.open('w',newline='') as f:
    writer=csv.writer(f,quoting=csv.QUOTE_ALL,lineterminator='\n');writer.writerow(header);writer.writerows(rows)
statuses=dict(Counter(row[10] for row in rows))
progress_path=qa/'PARITY_PROGRESS.json'
progress=read(progress_path)
historical_keys=('batch','branch','base_git_sha','apk_source_git_sha','inventory','test_evidence','visual','arch','release','matrix_status','current_code_batch','current_hybrid_batch','hybrid_work_20261121')
history=progress.setdefault('history',{})
history.setdefault('before_branch_integration',{key:progress[key] for key in historical_keys if key in progress})
branch='integration/hybrid-seven-20261121'
for key in ('current_code_batch','current_hybrid_batch'):
    progress.pop(key,None)
progress.update({'batch':'integrated-hybrid-20261121','branch':branch,'base_git_sha':'4ce31ce7f149078ba3fbb4f36a89eb677e1328cd','apk_source_git_sha':src,'matrix_status':statuses,'test_evidence':tests,'visual':visual,'arch':{'view':'bundled offline React','host':'Flutter and Android','financial_writes':'Flutter over one local SQLite database'}})
progress['inventory']={**progress.get('inventory',{}),'review_scenarios':len(rows),'static_inventory_basis':'historical reference scan; see history.before_branch_integration'}
progress['release']={'status':'debug_verified_for_release_chat','version_name':'1.0.18','candidate_version_code':candidate,'last_signed_workflow_run':release_meta['id'],'last_signed_workflow_number':release_meta['run_number'],'published_version_code_read':public_code,'signed_by_this_batch':False,'published_by_this_batch':False,'phone':'pending'}
progress['hybrid_work_20261121']={'branch':branch,'application_sha':src,'merged_financial_source':'4d8eb31f687976324f27bb4205b9668bdc0f996d','home_trial_preintegration_run':44942335455,'integration_run':run,'apk_build_and_test_same_revision':True,'flutter':tests['flutter'],'browser':tests['react'],'android':{**tests['android'],'performance':performance},'offline_sqlite':'same store for document, account directory, eight indicators, statements and cash/trial totals','evidence':['qa/test_logs/work-integrated-tests.json','qa/test_logs/work-android.json','qa/screenshots/hybrid-work'],'screens':['home and shortcuts','trial balance','suppliers and account groups','account directory and picker','warehouse directory','stored document preview inside Flutter'],'remaining':['physical phone acceptance','print/save on device','visual evidence per remaining reference state','signed candidate by release conversation']}
write(progress_path,progress)
light,dark=[100*visual[t]['share'] for t in ('light','dark')]
public_line=(f'رقم القناة وقت الفحص {public_code}. ' if public_code is not None else '')
release_line=f'{public_line}الرقم المرشح بحسب آخر تشغيل للتوقيع هو 1.0.18 ({candidate})، وتخصصه محادثة الإصدارات عند البناء.'
kit=f'''# تسليم فرع تكامل NASQO PRO Hybrid

فرع البناء هو **{branch}**. بُني APK تصحيح من {src} وشُغّلت اختبارات التطبيق والمتصفح والمحاكي من النسخة نفسها. يضيف آخر commit على فرع التكامل ملفات المراجعة والصور إلى شجرة التطبيق المختبرة. {release_line} [تشغيل التكامل]({action}) · [الفروق البرمجية منذ الفرع الذي راجعه المراجع](https://github.com/{repo}/compare/4ce31ce...{src}).

## ما تغيّر في التطبيق

احتفظ DashboardPage بشريطي React والبطاقات الثماني وجدول المجموعات والاختصارات الأربعة والعشرين. يتحكم Flutter في الحاوية والتنقل الأصلي والطباعة. تأتي الأرصدة وفلاتر العملات من SQLite. يعالج الدليل والمؤشرات وميزان المراجعة طرفَي السند النقدي بوصفهما حركة على حسابين، مع الحفاظ على سلوك القيود القديمة المستوردة.

دُمج كود إيصالات الترحيل والفواتير والسندات مع تاريخ فرعي التطوير. يُرجع تكرار طلب البيع أو الشراء أو السند المطابق الإيصال المحفوظ، بما في ذلك بعد إعادة فتح القاعدة. تُرفض إعادة استخدام معرّف الطلب ببيانات مختلفة، كما يُرفض صندوق بعملة مختلفة. تتضمن الاختبارات التوازي والتحويل بين صندوقين وسلامة المفاتيح الخارجية.

من كشف الحساب الأصلي يمكن فتح معاينة المستند المحفوظ بمكوّن CashInvoicePreviewPage الأصلي. يقرأ Flutter المستند وبنوده بحساب القيد ومعرّفه داخل معاملة SQLite واحدة ثم يرسل بيانات العرض. تعيد حركة الرجوع المستخدم إلى الكشف. حافظت الفواتير القديمة الخالية من البنود على حالتها. يرسل زر الطباعة طلبًا إلى Android. [لقطة المستند من المحاكي](screenshots/hybrid-work/android-statement-document.png) · [مرجع React الفاتح](screenshots/hybrid-work/embedded-light-document.png) · [الداكن](screenshots/hybrid-work/embedded-dark-document.png).

| نطاق الفحص | النتيجة |
|---|---|
| Flutter وSQLite | {full} اختبارًا ناجحًا، منها {focused} أُعيد تشغيلها للجسر وميزان المراجعة وإيصالات الترحيل. [ملخص الاختبارات](test_logs/work-integrated-tests.json) |
| React | اجتازت 23 حالة للحسابات والمظهر، و10 حالات للتفاعل والتمرير والرجوع، و4 اختبارات لحزمة الويب. راجع الفاحص 28 ملفًا محميًا. اكتمل الفحص الساكن وبناء الموقع. [تشغيل CI]({action}) |
| قائمة التقارير | عشرة مسارات وتفاصيلها وإجراءات الفلترة والرجوع في الوضعين مع مرجع Git ثابت. تطابقت صور القائمة قبل استخراج ReportsMenu وبعده. [نتائج المقارنة](test_logs/work-reports.json) |
| Android 35 دون اتصال | {len(checks)} فحصًا ناجحًا شملت الشريطين والضغط المطول والتخصيص والحفظ وإعادة التشغيل و«الكل» في الميزان ومعاينة المستند. [تفاصيل المحاكي](test_logs/work-android.json) · [ميزان المراجعة](screenshots/hybrid-work/android-trial-all.png) |
| سلامة SQLite أثناء التصفح | تطابقت بصمات {finance['tables']} جدولًا و{finance['rows']} صفًا قبل التفاعل وبعده، مع صفر مخالفات مفاتيح خارجية. [قبل](test_logs/work-android-baseline.json) · [بعد](test_logs/work-android-after.json) |
| صور الرئيسية | المرجع إلى اليسار وتطبيق Android إلى اليمين. تجاوز فرق قناة لونية واحدة 16 في {light:.2f}٪ من البكسلات في الفاتح و{dark:.2f}٪ في الداكن. [المقارنة الفاتحة](screenshots/hybrid-work/comparison-light.png) · [الداكنة](screenshots/hybrid-work/comparison-dark.png) · [قناع الفاتح](screenshots/hybrid-work/diff-light.png) · [الداكن](screenshots/hybrid-work/diff-dark.png) |
| التمرير | سجل محاكي بناء التصحيح {janky} إطارًا متأخرًا من {total} ({frames['janky_percent']:.2f}٪). [قياسات الإطارات وزمن الرسم وإصدار WebView](test_logs/work-android-performance.json) |

نجح التشغيل السابق [44942335455](https://github.com/{repo}/actions/runs/44942335455) في اختيار «الكل» والتمرير لرؤية الدولار واليورو منفصلين. يعيد تشغيل التكامل اختبار السلوك على التطبيق المدمج. استُبدل اختيار أول حقل في اختبار Android بتحديد القائمة باسمها الميسّر، وأصبح بدء اختبار المحاكي ينتظر عودة اتصال adb بعد إعادة تشغيله.

## متابعة المراجعة والإصدار

تغطي الأدلة مسارات الرئيسية والدليل والمورد وميزان المراجعة ومعاينة مستند حقيقي. تغطي اختبارات المتصفح محدد الحساب وقائمة المخازن. يبقى اعتماد المجموعة المرجعية الكاملة مفتوحًا إلى أن تُطابق كل حالة بلقطة وتفاعل على الهاتف. في الدفعة التالية تُراجع حالة إنشاء السند وحالة قائمة العمليات داخل الكشف، وتُقارن القيم بعد الحفظ والرجوع. على الهاتف تُفحص سرعة التمرير وتكبير الخط وTalkBack وحوار Android للطباعة وحفظ PDF. [الفروق المفتوحة](PARITY_GAPS.md) · [مصفوفة الحالات](PARITY_MATRIX.csv).
'''
handoff=qa/'REVIEW_HANDOFF.md'
old=handoff.read_text()
marker='# تسليم الدفعة 03'
if marker in old: old=old[old.index(marker):]
handoff.write_text(kit+'\n## سجل الدفعات السابقة\n\n'+old)
gaps=qa/'PARITY_GAPS.md'
old=gaps.read_text()
intro=f'''# نتائج التكامل وشروط القبول المتبقية

قورنت الرئيسية في Chromium وAndroid على مدخل SQLite نفسه. اجتازت معاينة الفاتورة من كشف الحساب التشغيل دون اتصال والتكبير والرجوع. وفّر اختيار «الكل» أقسامًا مستقلة للعملات. في الوضعين الفاتح والداكن تجاوز فرق 16 في قناة لونية {light:.2f}٪ و{dark:.2f}٪ على الترتيب. سجل محاكي التصحيح {janky} إطارًا متأخرًا من {total}. [الصور والقياسات](REVIEW_HANDOFF.md) · [تشغيل الكود المدمج]({action}).

| ما يحتاج مزيدًا من التحقق | معيار الحسم |
|---|---|
| الهاتف المستهدف | ظهور الخط العربي عند تكبيره، قراءة TalkBack، زمن اللمس والتمرير في البناء الموقّع. |
| عمليات المستند الأصلية | التحقق من طباعة Android وحفظ PDF ومحدد الملفات على الهاتف. الرفع إلى Drive معطل في وضع عدم الاتصال. |
| باقي الحالات المرجعية | ربط كل حالة برابط مرجعي وشاشة قابلة للوصول من التطبيق ثم تقديم صور وفحوص مستقلة لها. تبقى نماذج الترحيل الأصلية في Flutter. |
| تعافي فتح SQLite | توثيق حالة فشل قراءة قاعدة البيانات ثم إعادة المحاولة بالمقارنة المرجعية. |

'''
gaps.write_text(intro+old)
print(json.dumps({'run':run,'tests':tests,'candidate':candidate,'public_code':public_code,'frames':frames,'matrix':statuses},ensure_ascii=False))
