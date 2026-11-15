import { useEffect } from "react";

/**
 * Compatibility bridge for the protected phone simulator's FlowStack:
 * its gesture filterTap onClickCapture can cancel trusted taps even when the
 * live ERP browser is using native scrolling. Replay only the *already
 * canceled* tap of a dashboard button/checkbox; do not replay actual drags.
 * No changes to the protected src/mobile runtime or standalone simulator.
 */
export function useLiveDashboardTapBridge(): void {
  useEffect(() => {
    let travel = 0;
    let startX = 0, startY = 0;
    const inDashboard = (node: EventTarget | null): node is Element =>
      node instanceof Element && Boolean(node.closest(".nasqo-native-scroll, .nasqo-scan-overlay"));
    const onDown = (event: PointerEvent) => {
      if (!inDashboard(event.target)) return;
      travel = 0;
      startX = event.clientX;
      startY = event.clientY;
    };
    const onMove = (event: PointerEvent) => {
      if (!inDashboard(event.target)) return;
      travel = Math.max(travel, Math.hypot(event.clientX - startX, event.clientY - startY));
    };
    const onClick = (event: MouseEvent) => {
      if (!event.isTrusted || !window.matchMedia("(pointer: coarse)").matches ||
          !inDashboard(event.target)) return;
      const el = event.target.closest<HTMLButtonElement | HTMLInputElement>(
        'button, input[type="checkbox"], input[type="radio"]',
      );
      if (!el || el.closest(".nasqo-sort-handle") || el.disabled || travel > 12) return;
      // Deferred so the legacy FlowStack capture handler has finished;
      // its defaultPrevented flag is the proof that the trusted tap was eaten.
      window.setTimeout(() => {
        if (!event.defaultPrevented || !el.isConnected || el.disabled) return;
        el.click(); // isTrusted:false: never re-enters this bridge.
      }, 0);
    };
    document.addEventListener("pointerdown", onDown, true);
    document.addEventListener("pointermove", onMove, true);
    document.addEventListener("click", onClick, true);
    return () => {
      document.removeEventListener("pointerdown", onDown, true);
      document.removeEventListener("pointermove", onMove, true);
      document.removeEventListener("click", onClick, true);
    };
  }, []);
}
