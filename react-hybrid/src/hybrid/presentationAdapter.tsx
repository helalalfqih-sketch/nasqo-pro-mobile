import { createContext, useContext, type PropsWithChildren } from "react";
import { hybridBridge } from "./bridge";
import type {
  HybridCapabilities,
  HybridExportPdfPayload,
  HybridPickFileRequest,
  HybridPickFileResult,
  HybridPrintPayload,
  HybridUiPreferences,
} from "./contracts";

export interface HybridPresentationAdapterValue {
  isHybrid: boolean;
  capabilities: HybridCapabilities;
  notifyNavigate: (route: string, params?: Record<string, string | number | boolean | undefined>) => void;
  requestGoBack: (currentRoute?: string, stackDepth?: number) => void;
  notifyCurrencyChanged: (
    scope: "dashboard" | "category" | "statement" | "report",
    currency: string,
    targetId?: string,
  ) => void;
  syncUiPreferences: (preferences: HybridUiPreferences) => void;
  notifyOpenInvoice: (params: {
    intent: "invoice" | "return" | "quote" | "order";
    accountId?: string;
    entryId?: string;
    kindOverride?: "purchase" | "sale";
  }) => void;
  notifyOpenVoucher: (params: { accountId?: string; entryId?: string }) => void;
  notifyOpenAccountStatement: (accountId: string, currency?: string) => void;
  printDocument: (payload: HybridPrintPayload) => Promise<boolean>;
  exportPdf: (payload: HybridExportPdfPayload) => Promise<boolean>;
  pickFile: (request: HybridPickFileRequest) => Promise<HybridPickFileResult | null>;
  showMessage: (message: string, level?: "info" | "success" | "warning" | "error") => void;
}

const DEFAULT_WEB_ADAPTER: HybridPresentationAdapterValue = {
  isHybrid: false,
  capabilities: {
    offlineReady: false,
    printingSupported: true,
    pdfExportSupported: true,
    filePickerSupported: true,
    googleDriveConfigured: true,
    whatsappShareSupported: true,
  },
  notifyNavigate: () => {},
  requestGoBack: () => {},
  notifyCurrencyChanged: () => {},
  syncUiPreferences: () => {},
  notifyOpenInvoice: () => {},
  notifyOpenVoucher: () => {},
  notifyOpenAccountStatement: () => {},
  printDocument: async () => false,
  exportPdf: async () => false,
  pickFile: async () => null,
  showMessage: () => {},
};

const HybridPresentationContext = createContext<HybridPresentationAdapterValue>(DEFAULT_WEB_ADAPTER);

export function createFlutterPresentationAdapter(
  capabilitiesOverride?: Partial<HybridCapabilities>,
): HybridPresentationAdapterValue {
  const capabilities: HybridCapabilities = {
    offlineReady: true,
    printingSupported: true,
    pdfExportSupported: true,
    filePickerSupported: true,
    googleDriveConfigured: false,
    whatsappShareSupported: true,
    ...capabilitiesOverride,
  };

  return {
    isHybrid: true,
    capabilities,
    notifyNavigate: (route, params) => {
      hybridBridge.notify("navigate", { route, params });
    },
    requestGoBack: (currentRoute, stackDepth) => {
      hybridBridge.notify("goBack", { currentRoute, stackDepth });
    },
    notifyCurrencyChanged: (scope, currency, targetId) => {
      hybridBridge.notify("changeCurrency", { scope, currency, targetId });
    },
    syncUiPreferences: (preferences) => {
      hybridBridge.notify("saveUiPreferences", { preferences });
    },
    notifyOpenInvoice: (params) => {
      hybridBridge.notify("openInvoice", params);
    },
    notifyOpenVoucher: (params) => {
      hybridBridge.notify("openVoucher", params);
    },
    notifyOpenAccountStatement: (accountId, currency) => {
      hybridBridge.notify("openAccountStatement", { accountId, currency });
    },
    printDocument: async (payload) => {
      if (!hybridBridge.hasNativeTransport()) return false;
      await hybridBridge.invoke("printDocument", payload);
      return true;
    },
    exportPdf: async (payload) => {
      if (!hybridBridge.hasNativeTransport()) return false;
      await hybridBridge.invoke("exportPdf", payload);
      return true;
    },
    pickFile: async (request) => {
      if (!hybridBridge.hasNativeTransport()) return null;
      // Android's system document picker is user-driven. The previous global
      // 35-second heavy-operation timeout expired while selecting a .back and
      // scanning its 23-table SQLite archive, so React silently lost the
      // native preview even when the Dart inspection was still running.
      // Allow up to five minutes for the full picker + native read-only scan.
      // No file bytes cross the WebView boundary.
      const result = await hybridBridge.invoke<"pickFile", HybridPickFileResult | null>(
        "pickFile",
        request,
        { timeoutMs: 300_000 },
      );
      if (!result || result.cancelled) return null;
      return result;
    },
    showMessage: (message, level = "info") => {
      hybridBridge.notify("showMessage", { message, level });
    },
  };
}

export function HybridPresentationProvider({
  adapter,
  children,
}: PropsWithChildren<{ adapter: HybridPresentationAdapterValue }>) {
  return (
    <HybridPresentationContext.Provider value={adapter}>
      {children}
    </HybridPresentationContext.Provider>
  );
}

export function useHybridPresentation(): HybridPresentationAdapterValue {
  return useContext(HybridPresentationContext);
}
