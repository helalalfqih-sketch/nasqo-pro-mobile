"""Install two signed APKs on a disposable Android emulator; exercise the real WebView via touch."""
import hashlib
import io
import json
import os
import re
import sqlite3
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "flutter_app/test"))
from android_offline_smoke import PACKAGE, adb, screen
from android_upgrade_smoke import installed_code

OUT = Path(os.environ.get("HYBRID_EVIDENCE", "hybrid-evidence"))
DB = f"/data/user/0/{PACKAGE}/databases/nasqo_pro_erp.db"
FIXTURE = json.loads((ROOT / "qa/groups_lab/assets/fixture.json").read_text())
DEBUG = sys.argv[1:2] == ["--debug"]
CANDIDATE = ({"source": os.environ.get("GITHUB_SHA")} if DEBUG
             else json.loads((OUT / "candidate.json").read_text()))
RESULT = {"source": CANDIDATE["source"], "checks": {}, "paint_ms": [], "am_total_ms": []}
def save(name, value):
    (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2)+"\n")
def passed(test, detail=True):
    RESULT["checks"][test] = detail
    save("android.json", RESULT)
    print("PASS", test, detail, flush=True)
def require(expr, message):
    if not expr: raise AssertionError(message)
def shot(name):
    raw = adb("exec-out", "screencap", "-p")
    (OUT / (name+".png")).write_bytes(raw)
    return Image.open(io.BytesIO(raw)).convert("RGB")
def wait(fn, label, seconds=25):
    deadline = time.monotonic()+seconds
    while time.monotonic()<deadline:
        try:
            value=fn()
            if value is not None and value is not False and (not isinstance(value,int) or value!=0): return value
        except (subprocess.CalledProcessError, SyntaxError):
            pass
        time.sleep(.35)
    raise AssertionError("Timed out: "+label)
def nodes():
    tree=list(screen().iter("node"))
    # A freshly booted Pixel image can show a launcher ANR after changing its
    # resolution. Dismiss that exact background process only, and preserve the
    # evidence. A NASQO or WebView error must still fail the test.
    if any(n.get("package")=="android" and n.get("resource-id")=="android:id/alertTitle" and
           n.get("text")=="Pixel Launcher isn't responding" for n in tree):
        count=RESULT.get("launcher_dialogs_dismissed",0)
        require(count<2, "Pixel Launcher repeatedly blocked the test emulator")
        shot("pixel-launcher-dialog-"+str(count+1))
        close=next(n for n in tree if n.get("resource-id")=="android:id/aerr_close" and n.get("package")=="android")
        tap(close);RESULT["launcher_dialogs_dismissed"]=count+1
        return list(screen().iter("node"))
    return tree
def label(n):
    return (n.get("text","")+"\n"+n.get("content-desc","")).strip()
def find(text, seconds=20):
    def match():
        return next((n for n in nodes() if text in label(n)),None)
    return wait(match, text, seconds)
def exact_button(text):
    return wait(lambda: next((n for n in nodes() if n.get("class")=="android.widget.Button" and label(n)==text),None),text)
def center(n):
    x,y,r,b=bounds(n)
    return (x+r)/2,(y+b)/2
def bounds(n):
    return list(map(int,re.findall(r"-?\d+",n.get("bounds"))))
def tapxy(x,y):
    adb("shell","input","tap", str(round(x)), str(round(y)))
def tap(n):
    tapxy(*center(n))
def back():
    adb("shell","input","keyevent","4");time.sleep(.55)
def launch(expect_hybrid=True):
    adb("logcat","-c")
    adb("shell","wm","dismiss-keyguard")
    output=adb("shell","am","start","-W","-n",PACKAGE+"/.MainActivity").decode()
    total=re.search(r"TotalTime:\s*(\d+)",output)
    if expect_hybrid:
        msg=wait(lambda: re.search(rb"home_paint_ms=(\d+)",adb("logcat","-d","NasqoHybrid:I","*:S")), "React paint", 35)
        RESULT["paint_ms"].append(int(msg.group(1)))
        if total: RESULT["am_total_ms"].append(int(total.group(1)))
    return output
def stop():
    adb("shell","am","force-stop",PACKAGE)
def sql(statements):
    uid=adb("shell","stat","-c","%u",DB).decode().strip()
    require(uid.isdecimal() and int(uid)>=10000,"invalid app DB owner")
    return subprocess.check_output(["adb","shell","-T","su",uid,"sqlite3",DB],
        input=(".bail on\n.timeout 5000\n"+statements+"\n").encode()).decode().strip()
def quote(s):
    return "'"+str(s).replace("'","''")+"'"
def theme(dark):
    state=json.loads(sql("SELECT payloadJson FROM erp_state WHERE stateKey='settings';"))
    state["companyName"]="مختبر المطابقة"; state["isDarkMode"]=dark
    sql("UPDATE erp_state SET payloadJson="+quote(json.dumps(state,ensure_ascii=False))+" WHERE stateKey='settings';")
def seed():
    cmds=["PRAGMA foreign_keys=ON;","BEGIN;"]
    for i,a in enumerate(FIXTURE["accounts"]):
        values=[a["id"],a["name"],a["category"],"",0,{"ريال":"sar","دولار":"usd"}[a["currency"]],0,"synthetic",a["openingBalance"],a["openingDirection"],91040+i]
        cmds.append("INSERT INTO accounts(id,name,category,phone,creditLimit,currency,isCashAccount,note,openingBalance,openingDirection,codeNumber) VALUES("+",".join(quote(v) for v in values)+");")
    cmds.append("INSERT INTO erp_state(stateKey,payloadJson,updatedAt) VALUES('original_web_export',"+quote(json.dumps(FIXTURE,ensure_ascii=False))+",'2026-11-21T00:00:00Z');")
    sql("\n".join(cmds+["COMMIT;"]));theme(False)
def books():
    # Copy all committed pages of the stopped disposable DB, including its WAL.
    stop()
    with tempfile.TemporaryDirectory() as tmp:
        target=Path(tmp)/"test.sqlite"
        for suffix in ["","-wal","-journal"]:
            if suffix and subprocess.run(["adb","shell","test","-f",DB+suffix]).returncode:continue
            with Path(str(target)+suffix).open("wb") as f:
                subprocess.run(["adb","exec-out","cat",DB+suffix],stdout=f,check=True)
        with sqlite3.connect(target) as con:
            require(con.execute("PRAGMA integrity_check").fetchall()==[("ok",)],"SQLite integrity")
            require(not con.execute("PRAGMA foreign_key_check").fetchall(),"SQLite foreign keys")
            result={}
            for (name,) in con.execute("select name from sqlite_master where type='table' order by name"):
                ident='"'+name.replace('"','""')+'"'
                query="select * from "+ident+(" where stateKey<>'hybrid_home_ui_v1'" if name=="erp_state" else "")
                rows=sorted(json.dumps(row,ensure_ascii=False,default=lambda b:b.hex()) for row in con.execute(query))
                result[name]=[len(rows),hashlib.sha256(json.dumps(rows).encode()).hexdigest()]
            return result
def prefs():
    text=sql("SELECT payloadJson FROM erp_state WHERE stateKey='hybrid_home_ui_v1';")
    return json.loads(text or "{}")
def viewport():
    n=next((n for n in nodes() if n.get("class")=="android.webkit.WebView" and bounds(n)[3]-bounds(n)[1]>150),None)
    if n is not None: return bounds(n)
    header = find("فتح القائمة")
    nav = find("الشريط السفلي للشاشة الرئيسية")
    left, top, right, bottom = bounds(header)
    # Native status/navigation bars are outside the WebView. Anchor to the
    # centers of the fixed 52dp React header and the 68dp navigation strip.
    bar = bounds(nav)
    return [0, round((top+bottom)/2-26), 427, bar[3]]
def comparison_sample():
    # Only called after the disposable-emulator guard. The React reference
    # computes the metrics from the same synthetic accounts and entries as Dart.
    def records(query):
        return json.loads(sql(".mode json\n"+query) or "[]")
    currencies={"sar":"ريال","usd":"دولار","eur":"يورو","currency2":"عملة 2"}
    accounts=records("SELECT id,name,category,currency,isCashAccount,openingBalance,openingDirection,creditLimit FROM accounts;")
    ledger=records("SELECT id,accountId,kind,direction,amount,currency,deleted,payment,entryDate FROM ledger_entries;")
    groups={a["id"]:a["groupId"] for a in FIXTURE["accounts"]}
    for a in accounts:
        a.update(currency=currencies[a["currency"]],isCashAccount=bool(a["isCashAccount"]),groupId=groups.get(a["id"]))
    for e in ledger:
        e.update(currency=currencies[e["currency"]],deleted=bool(e["deleted"]),
                 kind={"simpleEntry":"simple-entry","returnEntry":"return"}.get(e["kind"],e["kind"]))
    # Initial QA workspace has no dismissed/read notifications or imported due dates.
    low=int(sql("SELECT COUNT(*) FROM inventory_items WHERE minThreshold>0 AND quantity<minThreshold;"))
    due=int(sql("SELECT COUNT(*) FROM ledger_entries WHERE deleted=0 AND kind='invoice' AND payment='credit' AND date(entryDate,'+30 days')<=date('now','+10 days');"))
    limits=0
    for a in accounts:
        balance=a["openingBalance"]*(1 if a["openingDirection"]=="debit" else -1)
        balance+=sum(e["amount"]*(1 if e["direction"]=="debit" else -1) for e in ledger
            if e["accountId"]==a["id"] and e["currency"]==a["currency"] and not e["deleted"] and e["kind"] not in ("quote","order"))
        limits+=a["creditLimit"]>0 and balance>a["creditLimit"]
    save("comparison-input.json",{"unread":low+due+limits,"fixture":{"accountGroups":FIXTURE["accountGroups"],"accounts":accounts,"ledger":ledger}})

def crop_compare(mode,box):
    full=shot("android-"+mode)
    actual=full.crop(box)
    w,h=actual.size
    subprocess.run(["node","qa/hybrid_home/browser.mjs",str(OUT/"browser"),str(w),str(h),'--capture-only'],
                   env={**os.environ,"NASQO_ANDROID_FIXTURE":str((OUT/"comparison-input.json").resolve())},check=True)
    ref=Image.open(OUT/"browser"/("reference-"+mode+".png")).convert("RGB")
    diff=ImageChops.difference(actual,ref)
    rgb=diff.split()
    mask=ImageChops.lighter(ImageChops.lighter(rgb[0],rgb[1]),rgb[2]).point(lambda c:255 if c>16 else 0)
    n=mask.histogram()[255]
    combined=Image.new("RGB",(w*2,h));combined.paste(ref,(0,0));combined.paste(actual,(w,0))
    combined.save(OUT/("comparison-"+mode+".png"));mask.save(OUT/("diff-"+mode+".png"))
    RESULT.setdefault("visual",{})[mode]={"viewport":box,"pixels":w*h,"pixels_over_16":n,"share":n/(w*h)}
    save("android.json", RESULT)
    return json.loads((OUT/"browser"/("reference-"+mode+".json")).read_text())
def taprect(box,rect):
    tapxy(box[0]+rect["x"]+rect["w"]/2,box[1]+rect["y"]+rect["h"]/2)
def swipe(x,y,x2,y2,ms=360):
    adb("shell","input","swipe",str(round(x)),str(round(y)),str(round(x2)),str(round(y2)),str(ms))
def visible_button(text,box,direction="down"):
    for _ in range(7):
        for n in nodes():
            if n.get("class")!="android.widget.Button" or text not in label(n):continue
            l,t,r,b=bounds(n)
            if r>l and b-t>=18 and box[1]+56<(t+b)/2<box[3]-80:return n
        upper,lower=box[1]+170,box[1]+410
        if direction=="up":swipe(160,upper,160,lower)
        else:swipe(160,lower,160,upper)
        time.sleep(.25)
    raise AssertionError("No unobstructed button: "+text)

def record_diag(name):
    logs=adb("logcat","-d","NasqoHybrid:I","chromium:I","AndroidRuntime:E","flutter:I","*:S").decode(errors="replace")
    (OUT/(name+"-log.txt")).write_text(logs[-20000:])
    try:
        (OUT/(name+"-ui.xml")).write_bytes(adb("exec-out","cat","/sdcard/window.xml"))
    except Exception: pass

def run(baseline,candidate):
    require(os.environ.get("GITHUB_ACTIONS")=="true" and adb("get-serialno").strip().startswith(b"emulator-") and adb("shell","getprop","ro.kernel.qemu").strip()==b"1","Disposable CI emulator required")
    require(PACKAGE.encode() not in adb("shell","pm","list","packages",PACKAGE),"Emulator must start empty")
    adb("root");adb("wait-for-device")
    require(adb("shell","id","-u").strip()==b"0","Emulator root required")
    adb("shell","wm","size","427x952");adb("shell","wm","density","160")
    adb("shell","settings","put","system","font_scale","1.0")
    adb("shell","cmd","connectivity","airplane-mode","enable");adb("shell","svc","wifi","disable");adb("shell","svc","data","disable")
    require(adb("shell","settings","get","global","airplane_mode_on").strip()==b"1","Airplane mode")
    OUT.mkdir(exist_ok=True, parents=True)
    adb("install",candidate if DEBUG else baseline)
    if not DEBUG: require(installed_code()==10014,"baseline identity")
    launch(DEBUG);find("الرئيسية",40);stop();seed()
    baseline_books=books();save("baseline-table-digests.json",baseline_books)
    if DEBUG:
        passed("installed_debug_apk", installed_code())
    else:
        adb("install","-r",candidate);require(installed_code()==CANDIDATE["versionCode"],"candidate identity")
        passed("in_place_signed_upgrade", [10014,installed_code()])
    launch();group=find("مجموعة الشمال")
    passed("offline_react_home",label(group))
    box=viewport()
    tree=nodes()
    for name,edge in [("خيارات","top"),("الرئيسية","bottom")]:
        bars=[n for n in tree if label(n)==name and n.get("class")=="android.widget.Button" and bounds(n)[2]>bounds(n)[0]]
        require(len(bars)==1,"Expected one "+name+" button on the home screen")
        y=center(bars[0])[1]
        require(box[1]<=y<=box[1]+62 if edge=="top" else box[3]-72<=y<=box[3],"Chrome outside the React viewport")
    passed("single_react_header_and_footer",{"webview":box,"options":1,"home":1})
    comparison_sample()
    geometry=crop_compare("light",box)
    expected=geometry["metrics"]
    labels={label(n) for n in tree if n.get("class")=="android.widget.Button"}
    require(len(expected)==8 and all(x in labels for x in expected),"Android metrics differ from independent React: "+repr([x for x in expected if x not in labels]))
    passed("eight_metrics_same_sqlite_input",expected)
    stop();theme(True);launch();find("مجموعة الشمال")
    crop_compare("dark",viewport())
    stop();theme(False);launch();find("مجموعة الشمال")
    sales=visible_button(expected[0],box)
    x,y=center(sales);swipe(x,y,x,y,720)
    tap(exact_button("تثبيت المؤشر"))
    wait(lambda:"sales" in (prefs().get("metricLayout") or {}).get("pinned",[]),"pinned financial metric")
    tap(exact_button("تبديل اللون"))
    wait(lambda:(prefs().get("metricLayout") or {}).get("toneOverrides",{}).get("sales")=="amber","recolored financial metric")
    back();stop();launch();find("مجموعة الشمال")
    require(prefs()["metricLayout"]["toneOverrides"]=={"sales":"amber"},"lost metric color on cold start")
    x,y=center(visible_button(expected[0],box));swipe(x,y,x,y,720)
    tap(exact_button("افتراضي"))
    wait(lambda:(prefs().get("metricLayout") or {}).get("pinned")==[],"restored metric order")
    back();passed("metric_long_press_pin_color_cold_open_reset")
    tap(find("الإجراءات السريعة"));find("مسح باركود");shot("android-quick")
    back();find("مجموعة الشمال")
    tap(find("فتح القائمة"));find("الرسائل الفورية واتساب");back();find("مجموعة الشمال")
    passed("quick_actions_drawer_back")
    report_tab=wait(lambda:next((n for n in nodes() if label(n)=="التقارير" and
        n.get("class")=="android.widget.Button" and bounds(n)[1]>box[3]-75),None),"React reports tab")
    tap(report_tab);tap(exact_button("ميزان المراجعة"));find("اجمالي المدين")
    currency=wait(lambda:next((n for n in nodes() if n.get("class")=="android.widget.Spinner" and
        bounds(n)[2]>bounds(n)[0]),None),"trial currency selector")
    tap(currency);tap(find("الكل"));find("الحسابات — دولار");find("الحسابات — يورو")
    shot("android-trial-all")
    back();find("اختر تقريرًا");back();find("مجموعة الشمال")
    passed("trial_balance_separate_currencies_and_nested_back")
    # Test the real Android select popup; it returns the selection to Dart.
    taprect(box,geometry["select"]);tap(find("دولار"))
    wait(lambda:prefs().get("filters",{}).get("group-41")=="دولار","currency in SQLite")
    find("25");passed("currency_change")
    taprect(box,geometry["name"]);tap(find("فتح كشف عميل دولار تجريبي"))
    find("الرصيد الختامي: 25.00 دولار");shot("native-statement")
    back();find("عميل دولار تجريبي");back();find("مجموعة الشمال")
    require(prefs()["filters"]["group-41"]=="دولار","lost filter on return");passed("native_statement_back")
    tap(exact_button("بحث"));find("البحث السريع المحلي")
    ed=wait(lambda:next((n for n in nodes() if n.get("class")=="android.widget.EditText"),None),"native search field")
    tap(ed);adb("shell","input","text","SKU-101")
    find("SKU-101")
    ime=adb("shell","dumpsys","input_method").decode(errors="replace")
    require("mInputShown=true" in ime or "isInputViewShown=true" in ime,"native IME")
    shot("native-keyboard");back();back();find("مجموعة الشمال");passed("native_keyboard_and_back")
    adb("shell","dumpsys","gfxinfo",PACKAGE,"reset")
    for i in range(3):
        swipe(185,box[1]+440,185,box[1]+160)
        swipe(185,box[1]+160,185,box[1]+440)
    swipe(185,box[1]+460,185,box[1]+160)
    (OUT/"gfxinfo-scroll.txt").write_bytes(adb("shell","dumpsys","gfxinfo",PACKAGE))
    y=wait(lambda:prefs().get("scroll",0),"persisted real Android touch scroll")
    time.sleep(.4);y=prefs()["scroll"];shot("scrolled")
    stop();launch();find("الإعدادات")
    require(abs(prefs()["scroll"]-y)<=2,"lost scroll on reopen")
    base=shot("reopened-scroll")
    scrolled=Image.open(OUT/"scrolled.png").convert("RGB")
    window=(box[0]+8,box[1]+6,box[2]-8,box[3]-6)
    from PIL import ImageStat
    change=ImageStat.Stat(ImageChops.difference(base.crop(window),scrolled.crop(window))).mean
    require(max(change)<4,"Cold-start scroll viewport differs: "+repr(change))
    passed("offline_restart_scroll_and_filter",{"css_px":y,"rgb_mean_absolute_difference":change})
    swipe(185,box[1]+150,185,box[1]+620,200)
    wait(lambda:prefs().get("scroll",0)==0,"top after swipe")
    x,y=center(visible_button("سند جديد",box))
    swipe(x,y,x,y,740);find("تحرير البطائق")
    # WebView exposes each tile as one accessibility node; its center selects
    # the tile. The edit toolbar exposes separate, labelled native touch targets.
    voucher=center(visible_button("تثبيت سند جديد بالأعلى",box))
    transfer=center(visible_button("تثبيت حوالة جديدة بالأعلى",box))
    swipe(*voucher,*transfer,510)
    def moved_after_transfer():
        order=(prefs().get("layout") or {}).get("order",[])
        return "new-voucher" in order and "new-transfer" in order and order.index("new-voucher")>order.index("new-transfer")
    wait(moved_after_transfer, "persisted real Android drag reorder")
    dragged=prefs()["layout"]
    back();find("مجموعة الشمال");stop();launch()
    fresh_tile=visible_button("سند جديد",box)
    require(prefs()["layout"]==dragged and moved_after_transfer(),"dragged order before pin on cold reopen")
    x,y=center(fresh_tile);swipe(x,y,x,y,740)
    find("تحرير البطائق");passed("android_drag_reorder_and_cold_open")
    tap(visible_button("تثبيت بالأعلى",box,"up"))
    wait(lambda:"new-voucher" in (prefs().get("layout") or {}).get("pinned",[]),"pinned tile")
    # The original React pin operation promotes the selected tile to the start
    # of its pinned block while keeping every other tile in the same order.
    pinned=prefs()["layout"]
    expected_order=["new-voucher"]+[key for key in dragged["order"] if key!="new-voucher"]
    require(pinned["order"]==expected_order and pinned["pinned"]==["new-voucher"],"pin promotion differs from React")
    back();time.sleep(.5);find("البطائق المثبّتة");passed("long_press_pin_and_hardware_back")
    mem=adb("shell","dumpsys","meminfo",PACKAGE).decode()
    frames=adb("shell","dumpsys","gfxinfo",PACKAGE).decode()
    (OUT/"meminfo.txt").write_text(mem);(OUT/"gfxinfo.txt").write_text(frames)
    (OUT/"webview-version.txt").write_bytes(adb("shell","dumpsys","webviewupdate"))
    passed("frame_and_memory_samples", {"process":PACKAGE})
    after=books();save("after-table-digests.json",after)
    require(after==baseline_books,"Business table difference: "+str([k for k in after if baseline_books.get(k)!=after[k]]))
    passed("accounting_and_stock_integrity",{"tables":len(after),"rows":sum(s[0] for s in after.values()),"foreign_key_errors":0})
    launch();find("البطائق المثبّتة")
    require(prefs()["filters"]["group-41"]=="دولار","cold currency filter")
    require(prefs()["layout"]==pinned,"lost post-pin layout on cold reopen")
    passed("preferences_after_cold_reopen")
    save("android.json", RESULT)

if __name__=="__main__":
    OUT.mkdir(parents=True,exist_ok=True)
    try: run(*sys.argv[1:])
    except BaseException as error:
        RESULT["failure"]=str(error);save("android.json", RESULT)
        try: shot("failed");record_diag("failed")
        except Exception:pass
        raise

