export function validScanCode(text: string): string | null {
  const clean = text.trim();
  return /^[A-Za-z0-9._:\-]{1,64}$/.test(clean) ? clean : null;
}
