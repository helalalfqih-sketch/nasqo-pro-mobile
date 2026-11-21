import type { ReactNode } from "react";
import { ArrowRightIcon, Cross2Icon } from "@radix-ui/react-icons";

export type ReportDestination = "cashboxes" | "trial-balance" | "movement" |
  "closing" | "by-category" | "stock-remaining" | "stock-expiry" | "invoice-profit" | "services" | "tax";

export function ReportsMenu({onSelect}: {onSelect: (id: ReportDestination) => void}) {
  const menu: { label: string; tone: "orange" | "blue"; run: () => void }[][] = [
    [
      { label: "حركة الصندوق", tone: "orange", run: () => onSelect("cashboxes") },
      { label: "تقرير الحسابات الختامية", tone: "blue", run: () => onSelect("closing") },
      { label: "تقرير اجمالي حسب التصنيف", tone: "orange", run: () => onSelect("by-category") },
      { label: "ميزان المراجعة", tone: "blue", run: () => onSelect("trial-balance") },
    ],
    [
      { label: "تقرير حركة المخزون والارباح", tone: "orange", run: () => onSelect("movement") },
      { label: "تقرير المخزون المتبقي وتاريخ الانتهاء", tone: "blue", run: () => onSelect("stock-expiry") },
      { label: "المخزون المتبقي", tone: "orange", run: () => onSelect("stock-remaining") },
      { label: "أرباح الفواتير", tone: "blue", run: () => onSelect("invoice-profit") },
      { label: "تقارير الخدمات", tone: "orange", run: () => onSelect("services") },
      { label: "تقارير ضريبية", tone: "blue", run: () => onSelect("tax") },
    ],
  ];
  const sectionTitles = ["التقارير المالية", "التقارير المخزنية"];

  return (
          <div className="reports-hub-menu" data-testid="reports-hub-menu">
            {menu.map((group, gi) => (
              <div key={sectionTitles[gi]}>
                <div className="reports-hub-section">{sectionTitles[gi]}</div>
                {group.map((item) => (
                  <button
                    key={item.label}
                    type="button"
                    className={`reports-hub-btn ${item.tone}`}
                    onClick={item.run}
                  >
                    {item.label}
                  </button>
                ))}
              </div>
            ))}
          </div>
  );
}

export function ReportsPanel({title, footer, onClose, onBack, children}: {
  title: string;
  footer: string;
  onClose: () => void;
  onBack?: () => void;
  children: ReactNode;
}) {
  return (
    <div className="center-modal-layer" data-testid="reports-hub-modal">
      <button className="center-modal-backdrop" onClick={onClose} aria-label="إغلاق التقارير" />
      <section
        className="account-groups-modal reports-hub-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="reports-hub-title"
      >
        <header className="smart-modal-header">
          <button type="button" className="smart-modal-close" onClick={onClose} aria-label="إغلاق">
            <Cross2Icon />
          </button>
          <h2 id="reports-hub-title">{title}</h2>
          {onBack ? (
            <button
              type="button"
              className="smart-modal-close"
              onClick={onBack}
              aria-label="رجوع إلى قائمة التقارير"
              data-testid="reports-back-btn"
            >
              <ArrowRightIcon />
            </button>
          ) : (
            <span className="smart-modal-spacer" aria-hidden="true" />
          )}
        </header>

        {children}
        <footer className="account-groups-footer">
          <span>{footer}</span>
          <button type="button" className="ag-btn close" onClick={onClose}>
            إغلاق
          </button>
        </footer>
      </section>
    </div>
  );
}
