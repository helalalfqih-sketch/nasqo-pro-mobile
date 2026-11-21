// Read the active document's geometry from the installed debug APK. Touch input
// goes through adb on the emulator, including when UIAutomator omits a subtree.
const port = Number(process.argv[2]);
if (!Number.isInteger(port) || port < 1 || port > 65535) throw Error('Invalid forwarded port');
const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();

function measureDocument() {
  const doc = document.querySelector('.hybrid-document');
  if (!doc || document.visibilityState !== 'visible') return null;
  const controls = {};
  for (const button of doc.querySelectorAll('button')) {
    const box = button.getBoundingClientRect();
    const name = button.getAttribute('aria-label') || button.textContent.trim();
    const receivesTouch = [.1, .5, .9].every(x => [.1, .5, .9].every(y =>
      button.contains(document.elementFromPoint(box.left + box.width * x, box.top + box.height * y))));
    controls[name] = {rect: [box.left, box.top, box.right, box.bottom], receivesTouch};
  }
  return {controls, width: innerWidth, density: devicePixelRatio,
    rtl: getComputedStyle(doc).direction === 'rtl', text: doc.innerText};
}

for (const target of targets) {
  if (target.url !== 'https://appassets.androidplatform.net/home/index.html') continue;
  const socket = new WebSocket(target.webSocketDebuggerUrl);
  const value = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(Error('Timed out reading the local WebView')), 4000);
    socket.onopen = () => socket.send(JSON.stringify({id: 1, method: 'Runtime.evaluate',
      params: {expression: `(${measureDocument.toString()})()`, returnByValue: true}}));
    socket.onerror = () => {clearTimeout(timer); reject(Error('Local WebView connection failed'));};
    socket.onmessage = event => {
      const data = JSON.parse(event.data);
      if (data.id !== 1) return;
      clearTimeout(timer); resolve(data.result?.result?.value);
    };
  }).finally(() => socket.close());
  if (value) {process.stdout.write(JSON.stringify(value)); break;}
}
