import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import type { IScannerControls } from "@zxing/browser";
import { rpc } from "./liveOdoo";
import { validScanCode } from "./dashboardScanMath";
import { openNativeOdoo } from "./odooNavigation";
import { vibrateFeedback } from "./dashboardPreferences";
type Product = {
  id: number; display_name: string;
  default_code: string | false; barcode: string | false;
};
export function DashboardScanner({ onClose, haptics }: { onClose: () => void; haptics: boolean }) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const controlsRef = useRef<IScannerControls | null>(null);
  const decodedRef = useRef(false);
  const [camera, setCamera] = useState(false);
  const [input, setInput] = useState("");
  const [message, setMessage] = useState("");
  const [product, setProduct] = useState<Product | null>(null);
  const [searching, setSearching] = useState(false);
  const abort = useRef<AbortController | null>(null);
  const handleClose = () => {
    controlsRef.current?.stop();
    controlsRef.current = null;
    abort.current?.abort();
    onClose();
  };
  useEffect(() => () => {
    controlsRef.current?.stop();
    abort.current?.abort();
  }, []);
  useEffect(() => {
    if (!camera || !videoRef.current) return;
    let canceled = false;
    // Load QR decoding only while the camera is actively requested.
    const startScanner = async () => {
      try {
        const { BrowserMultiFormatReader } = await import("@zxing/browser");
        if (canceled || !videoRef.current) return;
        const reader = new BrowserMultiFormatReader();
        const controls = await reader.decodeFromVideoDevice(undefined, videoRef.current, result => {
      if (!result || canceled || decodedRef.current) return;
      decodedRef.current = true;
      const code = validScanCode(result.getText());
      controlsRef.current?.stop();
      controlsRef.current = null;
      setCamera(false);
      if (code) {
        setInput(code);
        vibrateFeedback(haptics, "success");
        setMessage("تم مسح الرمز. اختر البحث عن المنتج للتحقق من Odoo.");
      } else {
        setMessage("الرمز لا يحتوي على معرّف صنف صالح. لن يتم فتح روابط QR.");
      }
        });
        if (canceled) controls.stop();
        else controlsRef.current = controls;
      } catch {
        if (!canceled) {
          setCamera(false);
          setMessage("تعذّر الوصول للكاميرا. تحقق من إذن المتصفح، أو أدخل الباركود يدويًا.");
        }
      }
    };
    void startScanner();
    return () => {
      canceled = true;
      controlsRef.current?.stop();
      controlsRef.current = null;
    };
  }, [camera, haptics]);

  const lookup = async () => {
    const code = validScanCode(input);
    if (!code) { setMessage("أدخل باركود أو رقم صنف يتكون من أحرف وأرقام."); return; }
    abort.current?.abort();
    const signal = new AbortController();
    abort.current = signal;
    setSearching(true);
    setProduct(null);
    setMessage("");
    try {
      const rows = await rpc<unknown>("/web/dataset/call_kw/product.product/search_read", {
        model: "product.product", method: "search_read",
        args: [["|", ["barcode", "=", code], ["default_code", "=", code]]],
        kwargs: { fields: ["id", "display_name", "barcode", "default_code"], limit: 2 },
      }, signal.signal);
      if (!Array.isArray(rows)) throw Error("INVALID_RESULT");
      if (rows.length === 1) {
        setProduct(rows[0] as Product);
        vibrateFeedback(haptics, "success");
      } else if (rows.length > 1) setMessage("تم العثور على أكثر من صنف؛ افتح قائمة المنتجات في Odoo لتحديد الصحيح.");
      else setMessage("لم يُعثر على صنف مطابق في المنتجات التي يسمح لك Odoo برؤيتها.");
    } catch (error) {
      if (signal.signal.aborted) return;
      setMessage(error instanceof Error && error.message === "ODOO_ACCESS_DENIED"
        ? "هذا الحساب لا يملك صلاحية قراءة المنتجات في Odoo."
        : "تعذّر البحث في Odoo. لم يتم إنشاء أي صنف أو حركة مخزون.");
    } finally {
      if (!signal.signal.aborted) setSearching(false);
    }
  };
  return createPortal(<div className="nasqo-scan-overlay" role="dialog" aria-modal="true" aria-label="مسح رمز المنتج">
    <div className="nasqo-scan-modal">
      <header><h3>مسح رمز المنتج</h3><button type="button" onClick={handleClose} aria-label="إغلاق الماسح">✕</button></header>
      <p>مسح QR أو باركود للبحث في منتجات Odoo. لا يتم تعديل المخزون تلقائيًا.</p>
      {camera ? <video ref={videoRef} autoPlay muted playsInline aria-label="معاينة الكاميرا" /> : null}
      <button type="button" onClick={() => {
        if (!window.isSecureContext) {
          setMessage("تتطلب الكاميرا اتصال HTTPS آمنًا.");
          return;
        }
        decodedRef.current = false;
        setCamera(v => !v);
        vibrateFeedback(haptics);
      }}>{camera ? "إيقاف الكاميرا" : "فتح كاميرا المسح"}</button>
      <label>الباركود أو رقم الصنف
        <input value={input} onChange={e => { setInput(e.target.value); setProduct(null); }}
          maxLength={64} autoComplete="off" placeholder="امسح أو أدخل الرمز" />
      </label>
      <button type="button" onClick={() => void lookup()} disabled={searching}>{
        searching ? "جارٍ البحث..." : "البحث عن المنتج"
      }</button>
      {product ? <div className="nasqo-scan-result">
        <strong>{product.display_name}</strong>
        <small>الرمز: {product.default_code || product.barcode || "—"}</small>
        <p>لإضافة كمية للمخزون، افتح استلامًا مخزنيًا في Odoo وأكمل الصنف والكمية والموقع هناك.</p>
        <div><button type="button" onClick={() => openNativeOdoo("products")}>تفاصيل المنتجات</button>
        <button type="button" onClick={() => openNativeOdoo("stockReceipts")}>استلام مخزني</button></div>
      </div> : null}
      {message ? <p role="status">{message}</p> : null}
    </div>
  </div>, document.body);
}
