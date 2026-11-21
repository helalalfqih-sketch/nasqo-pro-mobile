// Reuse the reference JSX and zoom behavior, replacing network services with native actions.
export function documentComponents(sourceOf, replace) {
  const between = (source, first, next, text) => {
    const start = source.indexOf(first);
    const end = source.indexOf(next, start + first.length);
    if (start < 0 || end < 0) throw Error('Missing invoice reference integration point: ' + first);
    return source.slice(0, start) + text + source.slice(end);
  };
  let page = sourceOf('CashInvoicePreviewPage');
  page = between(page, '  const [downloadingPdf,', '  const fitScale',
    '  const generatedAt = useMemo(() => new Date(ctx.document.generatedAt), [ctx.document.generatedAt]);\n' +
    '  const invoiceLines = ctx.document.lines;\n');
  page = between(page, '  useEffect(() => {\n    if (!entry)', '  useEffect(() => {\n    const viewport',
    '');
  page = between(page, '  const handleDownloadPdf', '  if (!entry)', '');
  page = replace(page, 'onClick={() => triggerPrintWithLoader("جاري تجهيز طباعة الفاتورة...")}',
    'disabled={ctx.document.busy} onClick={() => ctx.documentAction("print")}');
  page = replace(page, 'disabled={downloadingPdf}', 'disabled={ctx.document.busy}');
  page = replace(page, 'onClick={() => void handleDownloadPdf()}', 'onClick={() => ctx.documentAction("pdf")}');
  page = replace(page, '{downloadingPdf ? "جارٍ الإنشاء..." : "تنزيل PDF"}', '{"حفظ PDF"}');
  page = replace(page, 'disabled={uploadingDrive}', 'disabled title="يتطلب مزوّد Google Drive"');
  page = replace(page, 'onClick={() => void handleUploadPdfToDrive()}', 'aria-description="غير متاح في المعاينة المحلية"');
  page = replace(page, '{uploadingDrive ? "جاري الرفع..." : "حفظ لـ Drive"}', '{"حفظ لـ Drive"}');
  page = replace(page,'تنزيل ملخص الفاتورة PDF','حفظ المستند PDF عبر Android');
  page = replace(page,'اضغط تنزيل PDF لحفظ ملخص الفاتورة أو طباعة PDF','يمكن طباعة المستند أو حفظه من مربع Android');
  let doc = sourceOf('CashInvoiceDocument');
  doc = between(doc, '  const lines = entry.details', '  const tafqeetText',
    '  const totalQuantity = invoiceLines.reduce((sum, line) => sum + line.quantity, 0);\n');
  doc = replace(doc,'Math.max(invoiceLines.length, lines.length, 1)','Math.max(invoiceLines.length, 1)');
  doc = between(doc, '          ) : lines.length > 1 ?', '        </tbody>',
    '          ) : <tr><td colSpan={5}>تفاصيل البنود غير متاحة</td></tr>}\n');
  doc = replace(doc,'{formatAmount(totalQuantity)}','{invoiceLines.length ? formatAmount(totalQuantity) : "—"}');
  doc = replace(doc,'        <p className="cash-invoice-number-flow">',
    '        {entry.documentNumber && <p>رقم المستند : <bdi>{entry.documentNumber}</bdi></p>}\n        <p className="cash-invoice-number-flow">');
  return [sourceOf('SimpleAppHeader'), doc, 'export '+page, 'export {SimpleAppHeader};'].join('\n');
}
