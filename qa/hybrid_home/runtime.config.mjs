import {defineConfig} from '@playwright/test';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
export default defineConfig({
  testDir: root + '/tests',
  testMatch: ['mobile-runtime.spec.ts', 'android-back-navigation.spec.ts'],
  workers: 1,
  use: {
    baseURL: 'http://127.0.0.1:44817',
    viewport: {width: 1100, height: 1100},
    launchOptions: {executablePath: process.env.CHROME_BIN},
  },
  webServer: {
    command: 'node_modules/.bin/vite --host 127.0.0.1 --port 44817 --strictPort',
    cwd: root,
    url: 'http://127.0.0.1:44817/tests/runtime-fixture.html',
  },
});
