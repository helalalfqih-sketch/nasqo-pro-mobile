"""Review the installed offline backup screen on a newly created CI emulator."""
import os
import sys
from pathlib import Path

# Reuse the guarded fixtures and exact SQLite digest checks of the home suite.
sys.argv = [sys.argv[0], "--debug", *sys.argv[1:]]
from android_review import OUT, PACKAGE, adb, back, books, find, launch, passed, require, save, seed, shot, stop, tap, theme

def run(apk):
    require(os.environ.get("GITHUB_ACTIONS") == "true" and
            adb("get-serialno").strip().startswith(b"emulator-") and
            adb("shell","getprop","ro.kernel.qemu").strip() == b"1", "Requires a disposable CI emulator")
    require(PACKAGE.encode() not in adb("shell","pm","list","packages",PACKAGE), "Requires a fresh install")
    OUT.mkdir(exist_ok=True,parents=True)
    adb("root"); adb("wait-for-device")
    adb("shell","wm","size","412x870"); adb("shell","wm","density","160")
    adb("shell","settings","put","system","font_scale","1.0")
    adb("shell","cmd","connectivity","airplane-mode","enable")
    adb("shell","svc","wifi","disable"); adb("shell","svc","data","disable")
    require(adb("shell","settings","get","global","airplane_mode_on").strip()==b"1", "Offline setup")
    adb("install", str(apk))
    launch(); find("الرئيسية"); stop(); seed()
    for dark in (False,True):
        stop(); theme(dark); before=books()
        launch(); tap(find("خيارات"))
        tap(find("Google Drive السحابي"))
        find("Sign in with Google"); shot("gate-dark" if dark else "gate-light")
        back(); find("الرئيسية")
        after=books()
        require(before==after,"Opening Drive changed SQLite business tables")
        passed("offline_drive_gate_dark" if dark else "offline_drive_gate_light",
               {"tables":len(after),"rows":sum(v[0] for v in after.values()),"foreign_key_errors":0})
    launch(); find("الرئيسية"); passed("cold_reopen_after_drive")
if __name__ == "__main__":
    try: run(Path(sys.argv[-1]))
    except Exception as err:
        save("error.json", {"error":str(err)})
        try: shot("failed")
        except Exception: pass
        raise
