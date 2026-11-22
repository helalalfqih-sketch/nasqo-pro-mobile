"""Inspect the Android accessibility tree outside the outer WebView boundary."""
import json
import subprocess
import sys
from pathlib import Path
import xml.etree.ElementTree as ET

out=Path(sys.argv[1])
pkg='com.indexesstore.nasqo_qa'
subprocess.run(['adb','shell','uiautomator','dump','/sdcard/nasqo-qa-window.xml'],check=True,stdout=subprocess.DEVNULL,timeout=22)
xml=subprocess.check_output(['adb','exec-out','cat','/sdcard/nasqo-qa-window.xml'])
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
