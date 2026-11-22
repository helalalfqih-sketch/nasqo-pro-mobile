import "@fontsource/ibm-plex-sans-arabic/400.css";
import "@fontsource/ibm-plex-sans-arabic/500.css";
import "@fontsource/ibm-plex-sans-arabic/600.css";
import "@fontsource/ibm-plex-sans-arabic/700.css";
import "@fontsource/cairo/600.css";
import "@fontsource/cairo/700.css";
import "@fontsource/cairo/800.css";

import { StrictMode, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import "../styles.css";
import "../prototype.css";
import "./hybrid.css";

import { AuthenticatedWorkspace } from "../Prototype";
import { NasqoBrandLoader } from "../components/NasqoBrandLoader";
import {
  applyCardAppearanceSettings,
  readExtendedSettings,
  writeExtendedSettings,
} from "../utils/appSettings";
import { useBrandColor } from "../utils/brandColor";
import {
  writeHomeMetricOrder,
  writeHomeTileLayout,
  writePinnedFavorites,
  writeWidgetOrder,
} from "../utils/dashboardPrefs";
import { writeHapticsEnabled } from "../utils/haptics";
import { useThemeMode } from "../utils/theme";
import type { ErpWorkspaceData } from "../erp";

import { hybridBridge } from "./bridge";
import {
  validateHybridSnapshot,
  type HybridCapabilities,
  type HybridUiPreferences,
  type HybridWorkspaceSnapshot,
} from "./contracts";
import {
  createFlutterPresentationAdapter,
  HybridPresentationProvider,
} from "./presentationAdapter";
import { KeyboardProvider, PhoneFrame } from "./mobileAdapter";
import {
  applyHybridSnapshot,
  LOCAL_WORKSPACE_UID,
} from "./serviceAdapter";
import type { User } from "./firebaseAuthStub";

function hydrateUiPreferencesFromHost(prefs?: HybridUiPreferences) {
  if (!prefs) return;
  if (prefs.extendedSettings) {
    const merged = { ...readExtendedSettings(), ...prefs.extendedSettings };
    writeExtendedSettings(merged);
    applyCardAppearanceSettings(merged);
  }
  if (prefs.homeTileLayout) {
    writeHomeTileLayout(prefs.homeTileLayout);
  }
  if (prefs.homeMetricOrder) {
    writeHomeMetricOrder(prefs.homeMetricOrder);
  }
  if (prefs.widgetOrder) {
    writeWidgetOrder(prefs.widgetOrder);
  }
  if (prefs.favorites) {
    writePinnedFavorites(prefs.favorites);
  }
  if (typeof prefs.hapticsEnabled === "boolean") {
    writeHapticsEnabled(prefs.hapticsEnabled);
  }
}

function HybridRootApp() {
  const { mode: themeMode, setMode: setThemeMode } = useThemeMode();
  const { brandColor, setBrandColor, resetBrandColor } = useBrandColor();

  const [bootState, setBootState] = useState<"loading" | "ready" | "error">("loading");
  const [bootError, setBootError] = useState<string>("");
  const [capabilities, setCapabilities] = useState<Partial<HybridCapabilities> | undefined>(
    undefined,
  );
  const [hybridUser, setHybridUser] = useState<User>({
    uid: LOCAL_WORKSPACE_UID,
    email: "offline@nasqo.local",
    displayName: "نسقو برو — Android المحلي",
    photoURL: null,
  });

  const adapter = useMemo(
    () => createFlutterPresentationAdapter(capabilities),
    [capabilities],
  );

  const handleSetThemeMode = useCallback(
    (nextMode: typeof themeMode) => {
      setThemeMode(nextMode);
      adapter.syncUiPreferences({ themeMode: nextMode });
    },
    [adapter, setThemeMode],
  );

  const handleSetBrandColor = useCallback(
    (hex: string) => {
      setBrandColor(hex);
      adapter.syncUiPreferences({ brandColor: hex });
    },
    [adapter, setBrandColor],
  );

  const handleResetBrandColor = useCallback(() => {
    resetBrandColor();
    adapter.syncUiPreferences({ brandColor: "" });
  }, [adapter, resetBrandColor]);

  const setThemeModeRef = useRef(setThemeMode);
  setThemeModeRef.current = setThemeMode;
  const setBrandColorRef = useRef(setBrandColor);
  setBrandColorRef.current = setBrandColor;
  const didBootstrapRef = useRef(false);

  const applyValidatedSnapshot = useCallback((rawSnap: unknown) => {
    const checked = validateHybridSnapshot(rawSnap);
    if (!checked.valid) {
      throw new Error(checked.reason);
    }
    const snap: HybridWorkspaceSnapshot = checked.value;
    hybridBridge.setReadOnlyFinancialMode(Boolean(snap.capabilities?.readOnlyFinancial));
    if (snap.uiPreferences) {
      hydrateUiPreferencesFromHost(snap.uiPreferences);
      if (snap.uiPreferences.themeMode) {
        setThemeModeRef.current(snap.uiPreferences.themeMode);
      }
      if (snap.uiPreferences.brandColor) {
        setBrandColorRef.current(snap.uiPreferences.brandColor);
      }
    }
    if (snap.capabilities) {
      setCapabilities(snap.capabilities);
    }
    if (snap.userEmail) {
      setHybridUser((prev) => ({ ...prev, email: snap.userEmail ?? prev.email }));
    }
    applyHybridSnapshot(snap);
  }, []);

  const bootstrapFromFlutter = useCallback(async () => {
    setBootState("loading");
    setBootError("");
    try {
      const rawSnap = await hybridBridge.invoke<"getSnapshot", unknown>(
        "getSnapshot",
        { workspaceId: LOCAL_WORKSPACE_UID, forceRefresh: true },
        { timeoutMs: 12_000 },
      );
      applyValidatedSnapshot(rawSnap);
      setBootState("ready");
    } catch (err) {
      setBootError(
        err instanceof Error
          ? err.message
          : "تعذر استلام البيانات الأولية من تطبيق Flutter المحلي.",
      );
      setBootState("error");
    }
  }, [applyValidatedSnapshot]);

  useEffect(() => {
    const win = window as unknown as {
      __nasqoHybridReady?: boolean;
      __nasqoHybridSaveErp?: (workspaceId: string, erpData: ErpWorkspaceData) => void;
    };
    win.__nasqoHybridReady = true;
    win.__nasqoHybridSaveErp = (workspaceId, erpData) => {
      void hybridBridge.invoke("saveErpData", { workspaceId, data: erpData }).catch(() => {
        // Error surfaced through bridge or host event
      });
    };

    const unsubSnapshot = hybridBridge.onHostEvent<unknown>("snapshotUpdated", (rawSnap) => {
      try {
        applyValidatedSnapshot(rawSnap);
      } catch (err) {
        hybridBridge.notify("showMessage", {
          message: err instanceof Error ? err.message : "بيانات اللقطة الواردة غير صالحة.",
          level: "error",
        });
      }
    });

    if (!didBootstrapRef.current) {
      didBootstrapRef.current = true;
      void bootstrapFromFlutter();
    }

    return () => {
      unsubSnapshot();
    };
  }, [applyValidatedSnapshot, bootstrapFromFlutter]);

  if (bootState === "loading") {
    return (
      <div className="hybrid-boot-shell" data-testid="hybrid-boot-loading">
        <div className="hybrid-boot-card">
          <NasqoBrandLoader label="جاري تحميل مساحة العمل المحلية..." />
        </div>
      </div>
    );
  }

  if (bootState === "error") {
    return (
      <div className="hybrid-boot-shell" data-testid="hybrid-boot-error">
        <div className="hybrid-boot-card">
          <h1 className="hybrid-boot-title">تعذر الاتصال بقاعدة البيانات المحلية</h1>
          <p className="hybrid-boot-desc">{bootError}</p>
          <button
            type="button"
            className="hybrid-boot-btn"
            data-testid="hybrid-boot-retry"
            onClick={() => void bootstrapFromFlutter()}
          >
            إعادة المحاولة
          </button>
        </div>
      </div>
    );
  }

  return (
    <HybridPresentationProvider adapter={adapter}>
      <PhoneFrame>
        <KeyboardProvider>
          <AuthenticatedWorkspace
            user={hybridUser}
            cloudInitializationError=""
            onLocalSignOut={() => {
              adapter.showMessage("النظام يعمل في الوضع المحلي المتكامل مع Flutter.", "info");
            }}
            themeMode={themeMode}
            setThemeMode={handleSetThemeMode}
            brandColor={brandColor}
            setBrandColor={handleSetBrandColor}
            resetBrandColor={handleResetBrandColor}
          />
        </KeyboardProvider>
      </PhoneFrame>
    </HybridPresentationProvider>
  );
}

const rootEl = document.getElementById("root");
if (rootEl) {
  createRoot(rootEl).render(
    <StrictMode>
      <HybridRootApp />
    </StrictMode>,
  );
}
