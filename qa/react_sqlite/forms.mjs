// Exercise the actual React controls mounted by the installed Android APK.
// Only the subsequent, independent readback uses the production native bridge.
export async function exerciseForms(view, until, snapshot) {
  const accountName='مورد اختبار الواجهة';
  const itemName='صنف اختبار الواجهة';
  async function control(selector, operation, value, label) {
    function act(selector, operation, value, label) {
      const node=[...document.querySelectorAll(selector)].find(el=>
        (!label || (el.getAttribute('aria-label')||el.textContent).trim()===label) && !el.disabled);
      if (!node) return false;
      if (operation==='click') { node.scrollIntoView({block:'nearest'}); node.click(); }
      if (operation==='fill') {
        const proto=node.tagName==='SELECT' ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
        Object.getOwnPropertyDescriptor(proto,'value').set.call(node,value);
        node.dispatchEvent(new Event(node.tagName==='SELECT'?'change':'input',{bubbles:true}));
      }
      return true;
    }
    const args=[selector,operation,value,label].map(v=>JSON.stringify(v??null)).join(',');
    await until(()=>view.evaluate('('+act.toString()+')('+args+')'),'React control missing: '+selector+' '+(label||''),10000);
  }
  const click=(selector,label)=>control(selector,'click',null,label);
  const fill=(selector,value)=>control(selector,'fill',value);
  async function menu(label) {
    await click('button','إضافة');
    await click('[role=menuitem]',label);
  }
  async function saved(selector, name) {
    await until(()=>view.evaluate("!document.querySelector("+JSON.stringify(selector)+")"),name+' form did not complete',15000);
  }
  await menu('إضافة حساب جديد');
  await fill('#extended-account-name',accountName);
  await click('[data-testid=account-form-extended] button.save');
  await saved('[data-testid=account-form-extended]','account');
  const acc=(await snapshot()).accounts.find(a=>a.name===accountName);
  if (!acc) throw Error('React account form did not persist');
  await menu('إضافة صنف للمخزن');
  await fill('[data-testid=inventory-item-modal] [aria-label="اسم الصنف"]',itemName);
  await fill('[data-testid=inventory-item-modal] [aria-label="الكمية"]','10');
  await fill('[data-testid=inventory-item-modal] [aria-label="متوسط التكلفة"]','2');
  await click('[data-testid=inventory-item-save-btn]');
  await saved('[data-testid=inventory-item-modal]','stock');
  const item=(await snapshot()).inventory.find(i=>i.name===itemName);
  if (!item||item.quantity!==10) throw Error('React inventory form did not persist');
  await menu('فاتورة جديدة');
  await click('label','فاتورة شراء');
  await click('label','أصناف');
  await click('label','آجل');
  await fill('select[aria-label="حساب الفاتورة"]',acc.id);
  await fill('[data-testid=invoice-item-search]',itemName);
  await click('[aria-label="نتائج الأصناف"] [role=option]');
  await fill('[aria-label="كمية الصنف"]','3');
  await fill('[aria-label="سعر الصنف"]','5');
  await fill('[aria-label="رقم مستند الفاتورة"]','UI-1');
  await click('[data-testid=invoice-save-btn]');
  await saved('[data-testid=invoice-save-btn]','invoice');
  await menu('سند جديد');
  await fill('select[aria-label="حساب السند"]',acc.id);
  await fill('#new-transaction-amount','4');
  await click('.transaction-radio-row.direction-row label.debit');
  await click('[data-testid=transaction-modal] button.save');
  await saved('[data-testid=transaction-modal]','voucher');
  const snap=await snapshot();
  const entries=snap.ledger.filter(e=>e.accountId===acc.id);
  const invoice=entries.find(e=>e.kind==='invoice'&&e.amount===15&&e.direction==='credit');
  const voucher=entries.find(e=>e.kind==='voucher'&&e.amount===4&&e.direction==='debit');
  if (entries.length!==2||!invoice||!voucher||snap.inventory.find(i=>i.id===item.id).quantity!==13)
    throw Error('React forms did not persist the expected native totals');
  return [acc.id,item.id,invoice.id,voucher.id];
}
