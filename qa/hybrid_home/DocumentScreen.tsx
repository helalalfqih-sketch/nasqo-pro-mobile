import React, {useLayoutEffect, useMemo} from 'react';
import {CashInvoicePreviewPage, SimpleAppHeader} from 'dashboard:presentation';
import {Workspace, send} from './workspace';

export function DocumentScreen({data}) {
  const close = () => send('documentClose');
  const flow = useMemo(() => ({pop: close}), []);
  useLayoutEffect(() => {
    document.documentElement.classList.toggle('dark', data.dark);
    send('documentPaint');
  }, [data.dark]);
  const ctx = {
    flowRef: {current: flow},
    ledger: [data.entry],
    workspace: {companyName: data.company},
    extendedSettings: {},
    document: data,
    documentAction: (op: 'print'|'pdf') => send('documentOutput', {op}),
  };
  return <Workspace.Provider value={ctx}>
    <div className="flow-stack hybrid-document">
      <div className="flow-fixed-header"><SimpleAppHeader title="معاينة المستند" onBack={close}/></div>
      <div className="flow-scenes"><div className="flow-screen">
        <CashInvoicePreviewPage entryId={data.entry.id} flow={flow}/>
      </div></div>
    </div>
  </Workspace.Provider>;
}
