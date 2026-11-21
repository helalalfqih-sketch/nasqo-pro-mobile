import {createContext, useContext} from 'react';

export const Workspace = createContext(null);
export const useWorkspace = () => useContext(Workspace);
export const useScreenPortal = () => ({screenRef: {current: document.getElementById('home')}});
export const useKeyboard = () => ({hide() { (document.activeElement as HTMLElement)?.blur(); }});
export const simpleEntryScreen = () => 'simple-entry';
export const erpModuleScreen = (route: string) => route;

export function send(action: string, fields: object = {}) {
  window.NasqoHome?.postMessage(JSON.stringify({action, ...fields}));
}
export const triggerHaptic = (kind: string) => send('haptic', {kind});
