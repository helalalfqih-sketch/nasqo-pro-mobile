"""Inspect the Android accessibility tree outside the outer WebView boundary."""
import json
import subprocess
import re
import time
import sys
from pathlib import Path
import xml.etree.ElementTree as ET

out=Path(sys.argv[1])
pkg='com.indexesstore.nasqo_qa'
def window():
    subprocess.run(['adb','shell','uiautomator','dump','/sdcard/nasqo-qa-window.xml'],check=True,
                   stdout=subprocess.DEVNULL,timeout=25)
    return subprocess.check_output(['adb','exec-out','cat','/sdcard/nasqo-qa-window.xml'])

xml=window()
# On a resized Google APIs image the unrelated launcher can time out. Keep the
# dialog evidence and close only that named system dialog before testing NASQO.
for attempt in range(2):
    nodes=list(ET.fromstring(xml).iter('node'))
    if not any(n.get('package')=='android' and n.get('resource-id')=='android:id/alertTitle'
               and n.get('text')=="Pixel Launcher isn't responding" for n in nodes):
        break
    close=next(n for n in nodes if n.get('package')=='android' and n.get('resource-id')=='android:id/aerr_close')
    out.with_name(out.stem+'-launcher-'+str(attempt)+'.xml').write_bytes(xml)
    left,top,right,bottom=map(int,re.findall(r'-?\d+',close.get('bounds')))
    subprocess.run(['adb','shell','input','tap',str((left+right)//2),str((top+bottom)//2)],check=True)
    time.sleep(1)
    xml=window()
out.write_bytes(xml)
webviews=[]
native=[]
def walk(node, in_web=False):
    if node.get('class')=='android.webkit.WebView':
        if not in_web:
            webviews.append(node.get('bounds'))
        in_web=True
    label=(node.get('content-desc') or node.get('text') or '').strip()
    if not in_web and node.get('package')==pkg and label:
        native.append({'label':label,'class':node.get('class'),'bounds':node.get('bounds')})
    for child in node:
        walk(child,in_web)
walk(ET.fromstring(xml))
assert len(webviews)==1, ('outer WebViews',webviews,native[:4])
assert not native, ('Unexpected Flutter or Android controls outside the web view',native)
print(json.dumps({'outerWebViews':webviews,'outsideNavigation':native}))
