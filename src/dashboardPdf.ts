import type { DashboardSnapshot } from "./dashboardData";
import type { LiveInvoice } from "./liveOdoo";

export type ExportMode = "download" | "share";
export const numberAr = (value: number): string =>
  new Intl.NumberFormat("ar-YE", { maximumFractionDigits: 2 }).format(value);

export async function createDashboardPdf(
  snapshot: DashboardSnapshot, recentInvoices: LiveInvoice[], mode: ExportMode,
): Promise<"downloaded" | "shared"> {
  if (snapshot.salesStatus === "loading" || snapshot.stockStatus === "loading") {
    throw Error("DATA_LOADING");
  }
  if (snapshot.salesStatus !== "ready" && snapshot.stockStatus !== "ready") {
    throw Error("NO_AUTHORIZED_DATA");
  }
  // Browser rendering preserves Arabic shaping. No data is sent to a PDF service.
  const [{ default: html2canvas }, { jsPDF }] = await Promise.all([
    import("html2canvas"), import("jspdf"),
  ]);
  const paper = document.createElement("section");
  paper.setAttribute("dir", "rtl");
  paper.setAttribute("data-nasqo-pdf-report", "true");
  Object.assign(paper.style, {
    boxSizing: "border-box", position: "fixed", top: "0", left: "0",
    zIndex: "-1", pointerEvents: "none", width: "770px", padding: "36px",
    color: "#17304b", background: "#ffffff", fontFamily: "Tahoma, Arial, sans-serif",
    fontSize: "14px", lineHeight: "1.75",
  } satisfies Partial<CSSStyleDeclaration>);

  function title(text: string, large = false): void {
    const el = document.createElement(large ? "h1" : "h2");
    el.textContent = text;
    Object.assign(el.style, {
      color: "#0b5ca8", fontSize: large ? "24px" : "18px",
      margin: large ? "0 0 10px" : "24px 0 8px",
      borderBottom: large ? "3px solid #f39a16" : "1px solid #c8d8e8",
      paddingBottom: "8px",
    });
    paper.append(el);
  }
  function note(text: string): void {
    const el = document.createElement("p");
    el.textContent = text;
    el.style.margin = "6px 0";
    paper.append(el);
  }
  function table(headers: string[], rows: string[][]): void {
    const el = document.createElement("table");
    Object.assign(el.style, { width: "100%", borderCollapse: "collapse", fontSize: "12px", marginTop: "12px" });
    const thead = document.createElement("thead");
    const headerRow = document.createElement("tr");
    headers.forEach(label => {
      const th = document.createElement("th");
      th.textContent = label;
      Object.assign(th.style, { padding: "8px", border: "1px solid #d2dee9", background: "#eaf3fb", textAlign: "right" });
      headerRow.append(th);
    });
    thead.append(headerRow);
    el.append(thead);
    const tbody = document.createElement("tbody");
    rows.forEach(row => {
      const tr = document.createElement("tr");
      row.forEach(value => {
        const td = document.createElement("td");
        td.textContent = value;
        Object.assign(td.style, { padding: "7px", border: "1px solid #d2dee9", textAlign: "right", overflowWrap: "anywhere" });
        tr.append(td);
      });
      tbody.append(tr);
    });
    el.append(tbody);
    paper.append(el);
  }

  title("NASQO Pro · الملخص المالي والمخزون", true);
  note("تم إنشاء التقرير: " + new Date().toLocaleString("ar-YE"));
  note("فترة المبيعات: " + snapshot.start + " إلى " + snapshot.end);
  note("البيانات وفق صلاحيات حساب Odoo الحالي. جميع المبيعات صافية من مردودات الفواتير المرحّلة.");

  title("ملخص المبيعات (آخر سبعة أيام)");
  if (snapshot.salesStatus === "ready") {
    if (snapshot.sales.length) {
      table(["العملة", "إجمالي المبيعات الصافي", "عدد الفواتير والمردودات"], snapshot.sales.map(item =>
        [item.currency, numberAr(item.total), numberAr(item.count)]
      ));
      for (const item of snapshot.sales) {
        note("الاتجاه اليومي — " + item.currency);
        table(["اليوم", "المبيعات الصافية"], item.daily.map(day => [day.date, numberAr(day.amount)]));
      }
    } else note("لا توجد فواتير مبيعات مرحّلة خلال الفترة.");
  } else note("إجمالي المبيعات غير متاح حاليًا. لم تُعرض أرقام غير مكتملة.");

  title("الفواتير الأخيرة");
  if (recentInvoices.length) {
    table(["الفاتورة", "التاريخ", "الطرف", "المبلغ"], recentInvoices.slice(0, 8).map(invoice => [
      String(invoice.name || invoice.id),
      String(invoice.invoice_date || "—"),
      Array.isArray(invoice.partner_id) ? invoice.partner_id[1] : "—",
      numberAr(invoice.amount_total) + " " +
        (Array.isArray(invoice.currency_id) ? invoice.currency_id[1] : "عملة غير محددة"),
    ]));
  } else note("لا توجد فواتير متاحة للعرض ضمن الصلاحيات الحالية.");

  title("تنبيهات انخفاض المخزون");
  if (snapshot.stockStatus === "ready") {
    note("عدد قواعد إعادة الطلب المفحوصة: " + numberAr(snapshot.reorderCount));
    note("العناصر الأقل من الحد الأدنى: " + numberAr(snapshot.lowStock.length));
    if (snapshot.lowStock.length) {
      table(["الصنف", "الموقع", "المتوفر", "الحد الأدنى"], snapshot.lowStock.slice(0, 100).map(item => [
        item.name, item.location, numberAr(item.available) + " " + item.unit,
        numberAr(item.minimum) + " " + item.unit,
      ]));
      if (snapshot.lowStock.length > 100)
        note("يعرض التقرير أول 100 عنصر؛ بقي " + (snapshot.lowStock.length - 100) + " عنصر في شاشة NASQO.");
    } else note("لا توجد عناصر أدنى من الحدود المعرفة في قواعد إعادة الطلب المتاحة.");
  } else {
    note(snapshot.stockStatus === "denied"
      ? "قائمة المخزون المنخفض غير متاحة: حساب Odoo لا يملك صلاحية قراءة قواعد إعادة الطلب."
      : "تعذّر تحميل المخزون. لا تعتبر القائمة الفارغة دليلًا على توفر جميع الأصناف.");
  }
  note("تقرير صادر محليًا من المتصفح، للاطلاع والمشاركة المصرّح بها فقط.");

  document.body.append(paper);
  try {
    if (document.fonts?.ready) await document.fonts.ready;
    const canvas = await html2canvas(paper, {
      scale: 1.7, backgroundColor: "#ffffff", logging: false,
      useCORS: false, width: 770, windowWidth: 820,
      onclone: clonedDocument => {
        const clonedReport = clonedDocument.querySelector<HTMLElement>("[data-nasqo-pdf-report]");
        if (clonedReport) clonedReport.style.zIndex = "99999";
      },
    });
    if (!canvas.width || !canvas.height) throw Error("PDF_RENDER_FAILED");
    const pdf = new jsPDF({ orientation: "portrait", unit: "mm", format: "a4", compress: true });
    const pageWidth = 190, pageHeight = 277;
    const pixelsPerPage = Math.max(1, Math.floor(canvas.width * pageHeight / pageWidth));
    for (let y = 0, page = 0; y < canvas.height; y += pixelsPerPage, page++) {
      if (page) pdf.addPage();
      const partHeight = Math.min(pixelsPerPage, canvas.height - y);
      const part = document.createElement("canvas");
      part.width = canvas.width;
      part.height = partHeight;
      const context = part.getContext("2d");
      if (!context) throw Error("PDF_RENDER_FAILED");
      context.drawImage(canvas, 0, y, canvas.width, partHeight, 0, 0, part.width, partHeight);
      pdf.addImage(part.toDataURL("image/jpeg", 0.86), "JPEG", 10, 10,
        pageWidth, partHeight / canvas.width * pageWidth);
    }
    const blob = pdf.output("blob");
    const filename = "NASQO-report-" + snapshot.end + ".pdf";
    if (mode === "share" && typeof navigator.share === "function") {
      const file = new File([blob], filename, { type: "application/pdf" });
      if (navigator.canShare?.({ files: [file] })) {
        try {
          await navigator.share({ files: [file], title: "تقرير NASQO Pro" });
          return "shared";
        } catch (error) {
          // User cancellation must not silently download or share anything.
          if (error instanceof Error && error.name === "AbortError") throw error;
          // Browsers can lose transient share activation while building PDF.
          // Fall back to the normal download with an explicit UI message.
        }
      }
    }
    const url = URL.createObjectURL(blob);
    try {
      const a = document.createElement("a");
      a.href = url;
      a.download = filename;
      document.body.append(a);
      a.click();
      a.remove();
    } finally {
      window.setTimeout(() => URL.revokeObjectURL(url), 30_000);
    }
    return "downloaded";
  } finally {
    paper.remove();
  }
}
