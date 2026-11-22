export interface User {
  uid: string;
  email: string | null;
  displayName: string | null;
  photoURL: string | null;
}

export function onAuthStateChanged(
  _auth: unknown,
  callback: (user: User | null) => void,
): () => void {
  callback({
    uid: "local-erp-workspace",
    email: "offline@nasqo.local",
    displayName: "نسقو برو — Android المحلي",
    photoURL: null,
  });
  return () => {};
}

export function getAuth(): { currentUser: User | null } {
  return { currentUser: null };
}

export function initializeApp(): Record<string, never> {
  return {};
}

export class GoogleAuthProvider {
  addScope(_scope: string) {}
  setCustomParameters(_params: Record<string, string>) {}
  static credentialFromResult(): { accessToken: null } {
    return { accessToken: null };
  }
}

export async function signInWithPopup(): Promise<never> {
  throw new Error("المصادقة عبر Firebase غير مستخدمة في نسخة Android المحلية.");
}

export async function signOut(): Promise<void> {}
