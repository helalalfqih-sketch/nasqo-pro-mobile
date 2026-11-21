.bail on
PRAGMA foreign_keys=ON;
BEGIN;
INSERT INTO accounts(id,name,category,phone,creditLimit,currency,isCashAccount,note,openingBalance,openingDirection,codeNumber)
VALUES ('qa-review-usd','عميل المراجعة','clients','',0,'usd',0,'fixture',90.25,'debit',91014);
INSERT INTO ledger_entries(id,accountId,accountName,kind,typeLabel,payment,direction,amount,currency,exchangeRate,details,documentNumber,warehouseId,warehouseName,expenseCategory,entryNumber,deleted,entryDate)
VALUES ('qa-review-invoice','qa-review-usd','عميل المراجعة','invoice','ف.مبيعات آجل','credit','debit',12.5,'usd',1,'fixture','QA-INV-14','wh_1','المخزن الرئيسي','',91014,0,'2026-11-21');
INSERT INTO sale_lines(entryId,position,itemId,itemName,unit,quantity,unitPrice)
SELECT 'qa-review-invoice',0,id,name,unit,1.25,10 FROM inventory_items WHERE id='inv_1';
INSERT INTO nonposting_documents(type,revision,date,currency,customerName,accountId,notes)
VALUES('quote',1,'2026-11-21','usd','عميل المراجعة','qa-review-usd','qa-review-10014');
INSERT INTO nonposting_lines(documentId,position,itemId,description,quantity,unitPrice)
VALUES(last_insert_rowid(),0,'inv_1','بند عرض سعر تجريبي',2.5,8.25);
COMMIT;
