import type { ReactNode } from "react";
import {
  DndContext, PointerSensor, TouchSensor, KeyboardSensor,
  closestCenter, useSensor, useSensors, type DragEndEvent,
} from "@dnd-kit/core";
import {
  SortableContext, rectSortingStrategy,
  sortableKeyboardCoordinates, useSortable,
} from "@dnd-kit/sortable";
import { reorderWithin } from "./dashboardReorderMath";
import { CSS } from "@dnd-kit/utilities";
import type { WidgetId } from "./dashboardPreferences";

const arabicNames: Record<string, string> = {
  sales: "المبيعات", invoices: "الفواتير", lowStock: "المخزون",
  notifications: "الإشعارات", favorites: "المفضلة", trend: "اتجاه المبيعات",
  quick: "الإجراءات السريعة", export: "التصدير", settings: "الإعدادات",
};
function SortableTile({ id, name, children, zone }: {
  id: string; name: string; children: ReactNode; zone: "summary" | "widget";
}) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id });
  return <div ref={setNodeRef} className={"nasqo-sort-tile " + (isDragging ? "is-dragging" : "")}
    data-zone={zone} data-id={id}
    style={{ transform: CSS.Transform.toString(transform), transition }}>
    <button type="button" className="nasqo-sort-handle" data-scroll-drag="ignore" title={"اسحب لإعادة ترتيب " + (arabicNames[name] ?? name)}
      aria-label={"إعادة ترتيب " + (arabicNames[name] ?? name)} {...attributes} {...listeners}>⠿</button>
    {children}
  </div>;
}
export function DashboardReorder({
  summaryOrder, widgetOrder, summaryCards, widgets,
  onSummary, onWidgets, haptic,
}: {
  summaryOrder: string[];
  widgetOrder: WidgetId[];
  summaryCards: Record<string, ReactNode>;
  widgets: Record<WidgetId, ReactNode>;
  onSummary: (next: string[]) => void;
  onWidgets: (next: WidgetId[]) => void;
  haptic: () => void;
}) {
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 180, tolerance: 6 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );
  const onDragEnd = (event: DragEndEvent) => {
    const source = String(event.active.id);
    const dest = String(event.over?.id ?? "");
    if (!dest || source === dest) return;
    if (source.startsWith("summary:") && dest.startsWith("summary:")) {
      onSummary(reorderWithin(summaryOrder, source.slice(8), dest.slice(8)));
      haptic();
    } else if (source.startsWith("widget:") && dest.startsWith("widget:")) {
      onWidgets(reorderWithin(widgetOrder, source.slice(7), dest.slice(7)) as WidgetId[]);
      haptic();
    }
  };
  return <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={onDragEnd}>
    <div className="insights-summary-grid" aria-label="بطاقات الملخص القابلة للترتيب">
      <SortableContext items={summaryOrder.map(x => "summary:" + x)} strategy={rectSortingStrategy}>
        {summaryOrder.map(key => <SortableTile key={key} id={"summary:" + key} name={key} zone="summary">
          {summaryCards[key]}
        </SortableTile>)}
      </SortableContext>
    </div>
    <div className="nasqo-widget-board" aria-label="أدوات لوحة التحكم القابلة للترتيب">
      <SortableContext items={widgetOrder.map(x => "widget:" + x)} strategy={rectSortingStrategy}>
        {widgetOrder.map(key => <SortableTile key={key} id={"widget:" + key} name={key} zone="widget">
          {widgets[key]}
        </SortableTile>)}
      </SortableContext>
    </div>
  </DndContext>;
}
