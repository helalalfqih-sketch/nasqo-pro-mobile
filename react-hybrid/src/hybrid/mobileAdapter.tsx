import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type InputHTMLAttributes,
  type PropsWithChildren,
  type ReactNode,
  type Ref,
  type RefObject,
  type TextareaHTMLAttributes,
} from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { AnimatePresence, motion } from "motion/react";
import { hybridBridge } from "./bridge";
import { normalizeFlowScreenIdToHybridRoute } from "./routes";

export type MobileDeviceId = "iphone" | "pixel10";

export type MobileDeviceGeometry = {
  id: MobileDeviceId;
  platform: "ios" | "android";
  name: string;
  screenWidth: number;
  screenHeight: number;
  safeAreaTop: number;
  safeAreaBottom: number;
};

export const pixelGeometry: MobileDeviceGeometry = {
  id: "pixel10",
  platform: "android",
  name: "Android WebView",
  screenWidth: 393,
  screenHeight: 852,
  safeAreaTop: 0,
  safeAreaBottom: 0,
};

export const iphoneGeometry: MobileDeviceGeometry = pixelGeometry;

export const mobileDevices = {
  pixel10: pixelGeometry,
  iphone: iphoneGeometry,
} as const;

export const mobileAssets = {
  androidKeyboard: "",
  iphoneKeyboard: "",
} as const;

export function useMobileDevice() {
  return {
    device: pixelGeometry,
    deviceId: "pixel10" as MobileDeviceId,
    setDeviceId: (_id: MobileDeviceId) => {},
  };
}

export function DevicePicker() {
  return null;
}

export function StatusBar() {
  return null;
}

export function HomeIndicator() {
  return null;
}

export function KeyboardDock() {
  return null;
}

const ScreenPortalContext = createContext<{ screenRef: RefObject<HTMLDivElement | null> }>({
  screenRef: { current: null },
});

export function useScreenPortal() {
  return useContext(ScreenPortalContext);
}

export function PhoneFrame({ children }: PropsWithChildren) {
  const screenRef = useRef<HTMLDivElement | null>(null);
  return (
    <ScreenPortalContext.Provider value={{ screenRef }}>
      <div ref={screenRef} className="hybrid-webview-viewport" data-testid="hybrid-viewport">
        {children}
      </div>
    </ScreenPortalContext.Provider>
  );
}

export function MobileRuntime({ children }: PropsWithChildren) {
  return (
    <PhoneFrame>
      <KeyboardProvider>{children}</KeyboardProvider>
    </PhoneFrame>
  );
}

type KeyboardContextValue = {
  visible: boolean;
  height: number;
  fullHeight: number;
  progress: number;
  dragOffset: number;
  isDragging: boolean;
  focusedElement: HTMLElement | null;
  setDragOffset: (offset: number) => void;
  setDragging: (dragging: boolean) => void;
  show: (element?: HTMLElement | null) => void;
  hide: () => void;
};

const KeyboardContext = createContext<KeyboardContextValue | null>(null);

export function KeyboardProvider({ children }: PropsWithChildren) {
  const [focusedElement, setFocusedElement] = useState<HTMLElement | null>(null);
  const [keyboardHeight, setKeyboardHeight] = useState(0);

  useEffect(() => {
    if (typeof window === "undefined" || !window.visualViewport) return;
    const vv = window.visualViewport;
    const syncInset = () => {
      const diff = Math.max(0, Math.round(window.innerHeight - vv.height - vv.offsetTop));
      setKeyboardHeight(diff > 80 ? diff : 0);
    };
    syncInset();
    vv.addEventListener("resize", syncInset);
    vv.addEventListener("scroll", syncInset);
    return () => {
      vv.removeEventListener("resize", syncInset);
      vv.removeEventListener("scroll", syncInset);
    };
  }, []);

  const value = useMemo<KeyboardContextValue>(
    () => ({
      visible: keyboardHeight > 0,
      height: keyboardHeight,
      fullHeight: keyboardHeight,
      progress: keyboardHeight > 0 ? 1 : 0,
      dragOffset: 0,
      isDragging: false,
      focusedElement,
      setDragOffset: () => {},
      setDragging: () => {},
      show: (element) => {
        setFocusedElement(element ?? null);
      },
      hide: () => {
        if (focusedElement && typeof focusedElement.blur === "function") {
          focusedElement.blur();
        } else if (
          typeof document !== "undefined" &&
          document.activeElement instanceof HTMLElement
        ) {
          document.activeElement.blur();
        }
        setFocusedElement(null);
      },
    }),
    [focusedElement, keyboardHeight],
  );

  return <KeyboardContext.Provider value={value}>{children}</KeyboardContext.Provider>;
}

export function useKeyboard(): KeyboardContextValue {
  const context = useContext(KeyboardContext);
  if (!context) {
    return {
      visible: false,
      height: 0,
      fullHeight: 0,
      progress: 0,
      dragOffset: 0,
      isDragging: false,
      focusedElement: null,
      setDragOffset: () => {},
      setDragging: () => {},
      show: () => {},
      hide: () => {},
    };
  }
  return context;
}

export function useKeyboardInsets() {
  const kb = useKeyboard();
  const avail =
    typeof window !== "undefined"
      ? (window.visualViewport?.height ?? window.innerHeight)
      : 852;
  return {
    keyboardHeight: kb.height,
    keyboardFullHeight: kb.fullHeight,
    keyboardDragging: false,
    bottomInset: kb.height,
    availableHeight: avail,
    isKeyboardVisible: kb.visible,
  };
}

type KeyboardInputProps = InputHTMLAttributes<HTMLInputElement> & {
  ref?: Ref<HTMLInputElement>;
};

export function KeyboardInput(props: KeyboardInputProps) {
  const keyboard = useKeyboard();
  const { ref, ...inputProps } = props;

  return (
    <input
      {...inputProps}
      ref={ref}
      onFocus={(event) => {
        keyboard.show(event.currentTarget);
        inputProps.onFocus?.(event);
      }}
    />
  );
}

export function KeyboardTextarea(props: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  const keyboard = useKeyboard();

  return (
    <textarea
      {...props}
      onFocus={(event) => {
        keyboard.show(event.currentTarget);
        props.onFocus?.(event);
      }}
    />
  );
}

export function MobileTextField({
  id,
  label,
  placeholder,
  testId,
}: {
  id: string;
  label: string;
  placeholder?: string;
  testId?: string;
}) {
  return (
    <label className="mobile-field" htmlFor={id}>
      <span className="field-label">{label}</span>
      <KeyboardInput id={id} data-testid={testId} placeholder={placeholder} />
    </label>
  );
}

export function MobileScroll({
  className,
  children,
}: PropsWithChildren<{ className?: string }>) {
  const { isKeyboardVisible, keyboardHeight } = useKeyboardInsets();
  const style = {
    "--keyboard-height": `${keyboardHeight}px`,
  } as CSSProperties;

  return (
    <section
      className={`mobile-page ${className ?? ""}`}
      data-keyboard-dragging="false"
      data-keyboard-visible={isKeyboardVisible ? "true" : "false"}
      style={style}
    >
      <div className="mobile-scroll hybrid-native-scroll" data-testid="mobile-scroll">
        <div className="mobile-scroll-content" data-testid="mobile-scroll-content">
          {children}
        </div>
      </div>
    </section>
  );
}

export type CarouselProps = PropsWithChildren<{
  className?: string;
  contentClassName?: string;
  ariaLabel?: string;
  showScrollbar?: boolean;
  draggingEnabled?: boolean;
}>;

export function Carousel({
  className,
  contentClassName,
  ariaLabel,
  children,
}: CarouselProps) {
  return (
    <div
      className={`mobile-carousel hybrid-native-carousel ${className ?? ""}`}
      aria-label={ariaLabel}
      role={ariaLabel ? "region" : undefined}
    >
      <div className={`mobile-carousel-content ${contentClassName ?? ""}`}>{children}</div>
    </div>
  );
}

export function BottomSheet({
  open,
  onOpenChange,
  title,
  description,
  snap = 0.72,
  children,
}: PropsWithChildren<{
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  description?: string;
  snap?: number;
}>) {
  const { screenRef } = useScreenPortal();
  const keyboard = useKeyboard();
  const { keyboardHeight } = useKeyboardInsets();

  useEffect(() => {
    if (open) keyboard.hide();
  }, [open, keyboard]);

  const viewportHeight =
    screenRef.current?.clientHeight ||
    (typeof window !== "undefined" ? window.innerHeight : 852);
  const effectiveHeight = Math.max(
    260,
    Math.round(viewportHeight * snap) - Math.min(keyboardHeight, 180),
  );

  return (
    <Dialog.Root
      open={open}
      onOpenChange={(nextOpen) => {
        if (nextOpen) keyboard.hide();
        onOpenChange(nextOpen);
      }}
    >
      <Dialog.Portal container={screenRef.current ?? undefined} forceMount>
        <AnimatePresence>
          {open ? (
            <>
              <Dialog.Overlay asChild forceMount>
                <motion.div
                  className="sheet-overlay"
                  data-testid="sheet-overlay"
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  transition={{ duration: 0.16 }}
                />
              </Dialog.Overlay>
              <Dialog.Content asChild forceMount>
                <motion.div
                  className="bottom-sheet"
                  data-testid="bottom-sheet"
                  style={{ bottom: 0, maxHeight: effectiveHeight }}
                  initial={{ y: effectiveHeight + 24 }}
                  animate={{ y: 0 }}
                  exit={{ y: effectiveHeight + 24 }}
                  transition={{ duration: 0.2, ease: [0.22, 1, 0.36, 1] }}
                >
                  <div className="sheet-handle-zone" data-testid="sheet-handle">
                    <div className="sheet-handle" />
                  </div>
                  <div className="sheet-header">
                    <Dialog.Title className="sheet-title">{title}</Dialog.Title>
                    {description ? (
                      <Dialog.Description className="sheet-description">
                        {description}
                      </Dialog.Description>
                    ) : null}
                  </div>
                  <div className="sheet-content">{children}</div>
                </motion.div>
              </Dialog.Content>
            </>
          ) : null}
        </AnimatePresence>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

export type FlowScreen = {
  id: string;
  title?: string;
  header?: (flow: FlowControls) => ReactNode;
  headerHeight?: number;
  footer?: (flow: FlowControls) => ReactNode;
  footerHeight?: number;
  render: (flow: FlowControls) => ReactNode;
};

type FlowEntry = FlowScreen & {
  key: string;
};

export type FlowControls = {
  current: FlowEntry;
  previous: FlowEntry | null;
  stack: FlowEntry[];
  canGoBack: boolean;
  push: (screen: FlowScreen) => void;
  pop: () => void;
  replace: (screen: FlowScreen) => void;
  reset: (screen: FlowScreen) => void;
};

const FlowContext = createContext<FlowControls | null>(null);

export function useFlow() {
  const context = useContext(FlowContext);
  if (!context) {
    throw new Error("useFlow must be used inside FlowStack");
  }
  return context;
}

export function FlowStack({
  initial,
  onSystemBack,
}: {
  initial: FlowScreen;
  onSystemBack?: () => boolean;
}) {
  const keyboard = useKeyboard();
  const { bottomInset } = useKeyboardInsets();
  const sequence = useRef(1);
  const initialEntry = useRef<FlowEntry>({ ...initial, key: `${initial.id}-0` });
  const [stack, setStack] = useState<FlowEntry[]>(() => [initialEntry.current]);
  const [direction, setDirection] = useState(1);

  const systemBackRef = useRef(onSystemBack);
  systemBackRef.current = onSystemBack;
  const stackRef = useRef(stack);
  stackRef.current = stack;
  const lastNavDispatchRef = useRef<{ route: string; ts: number }>({ route: "", ts: 0 });
  const lastBackDispatchRef = useRef<number>(0);

  const emitNavigateOnce = useCallback((screenId: string) => {
    const route = normalizeFlowScreenIdToHybridRoute(screenId);
    const now = Date.now();
    if (
      lastNavDispatchRef.current.route === route &&
      now - lastNavDispatchRef.current.ts < 120
    ) {
      return;
    }
    lastNavDispatchRef.current = { route, ts: now };
    hybridBridge.notify("navigate", { route });
  }, []);

  const emitGoBackOnce = useCallback((screenId: string, stackDepth: number) => {
    const now = Date.now();
    if (now - lastBackDispatchRef.current < 120) return;
    lastBackDispatchRef.current = now;
    hybridBridge.notify("goBack", {
      currentRoute: normalizeFlowScreenIdToHybridRoute(screenId),
      stackDepth,
    });
  }, []);

  const toEntry = useCallback((screen: FlowScreen): FlowEntry => {
    const next = sequence.current;
    sequence.current += 1;
    return { ...screen, key: `${screen.id}-${next}` };
  }, []);

  const pop = useCallback(() => {
    keyboard.hide();
    const currentStack = stackRef.current;
    if (currentStack.length <= 1) {
      emitGoBackOnce(currentStack[0]?.id ?? "home", 1);
      return;
    }
    const nextStack = currentStack.slice(0, -1);
    const top = nextStack[nextStack.length - 1];
    stackRef.current = nextStack;
    setDirection(-1);
    setStack(nextStack);
    emitNavigateOnce(top.id);
  }, [emitGoBackOnce, emitNavigateOnce, keyboard]);

  // Listen to Android hardware back button forwarded by Flutter via the bridge
  useEffect(() => {
    const handleBack = () => {
      if (systemBackRef.current?.()) return true;
      if (stackRef.current.length <= 1) return false;
      pop();
      return true;
    };
    const onAndroidBack = (event: Event) => {
      if (handleBack()) event.preventDefault();
    };
    window.addEventListener("nasqo:android-back", onAndroidBack);
    const unsubscribe = hybridBridge.onHostEvent("backPressed", handleBack);
    return () => {
      window.removeEventListener("nasqo:android-back", onAndroidBack);
      unsubscribe();
    };
  }, [pop]);

  const controls = useMemo<FlowControls>(() => {
    const current = stack[stack.length - 1];
    const previous = stack.length > 1 ? stack[stack.length - 2] : null;

    return {
      current,
      previous,
      stack,
      canGoBack: stack.length > 1,
      push: (screen) => {
        keyboard.hide();
        const currentStack = stackRef.current;
        const top = currentStack[currentStack.length - 1];
        if (top && top.id === screen.id) return;
        const next = [...currentStack, toEntry(screen)];
        stackRef.current = next;
        setDirection(1);
        setStack(next);
        emitNavigateOnce(screen.id);
      },
      pop,
      replace: (screen) => {
        keyboard.hide();
        const currentStack = stackRef.current;
        const next = [...currentStack.slice(0, -1), toEntry(screen)];
        stackRef.current = next;
        setDirection(1);
        setStack(next);
        emitNavigateOnce(screen.id);
      },
      reset: (screen) => {
        keyboard.hide();
        const next = [toEntry(screen)];
        stackRef.current = next;
        setDirection(-1);
        setStack(next);
        emitNavigateOnce(screen.id);
      },
    };
  }, [emitNavigateOnce, keyboard, pop, stack, toEntry]);

  const topIndex = stack.length - 1;
  const header = controls.current.header?.(controls);
  const headerHeight = controls.current.headerHeight ?? 0;
  const footer = controls.current.footer?.(controls);
  const footerHeight = controls.current.footerHeight ?? 0;

  return (
    <FlowContext.Provider value={controls}>
      <div
        className="flow-stack hybrid-flow-stack"
        data-testid="flow-stack"
        data-keyboard-dragging="false"
        style={
          {
            "--flow-header-height": `${header ? headerHeight : 0}px`,
            "--flow-header-content-height": `${headerHeight}px`,
            "--flow-header-safe-area": "0px",
            "--flow-footer-height": `${footer ? footerHeight : 0}px`,
            "--keyboard-height": `${bottomInset}px`,
          } as CSSProperties
        }
      >
        {header ? (
          <header className="flow-fixed-header" data-testid="flow-fixed-header">
            {header}
          </header>
        ) : null}
        <div className="flow-scenes">
          <AnimatePresence initial={false} custom={direction}>
            {stack.map((entry, index) => {
              const isTop = index === topIndex;
              const isVisible = index >= topIndex - 1;
              return (
                <motion.div
                  key={entry.key}
                  className="flow-screen"
                  aria-hidden={!isTop}
                  inert={!isTop}
                  data-flow-current={isTop ? "true" : "false"}
                  data-testid={isTop ? "flow-current" : undefined}
                  initial={isTop ? { opacity: 0.92 } : false}
                  animate={{ opacity: isVisible ? 1 : 0 }}
                  exit={{ opacity: 0 }}
                  transition={{ duration: 0.16, ease: [0.22, 1, 0.36, 1] }}
                  style={{
                    pointerEvents: isTop ? "auto" : "none",
                    visibility: isVisible ? "visible" : "hidden",
                    zIndex: isTop ? 2 : 1,
                  }}
                >
                  {entry.render(controls)}
                </motion.div>
              );
            })}
          </AnimatePresence>
        </div>
        {footer ? (
          <footer className="flow-fixed-footer" data-testid="flow-fixed-footer">
            {footer}
          </footer>
        ) : null}
      </div>
    </FlowContext.Provider>
  );
}
