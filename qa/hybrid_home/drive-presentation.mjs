// Keep the original Drive JSX, SVGs, CSS classes and touch targets. Only the
// file and authorization operations are replaced by native, allowlisted intents.
export function drivePresentation(source) {
  const start=source.indexOf('  return (\n    <div className="center-modal-layer" data-testid="google-drive-modal">');
  if(start<0)throw Error('Missing original Drive modal');
  let view=source.slice(start);
  function cut(from,until,replacement='') {
    const i=view.indexOf(from),j=view.indexOf(until,i+from.length);
    if(i<0||j<0)throw Error('Drive integration point changed: '+from);
    view=view.slice(0,i)+replacement+view.slice(j);
  }
  cut('                <button\n                  type="button"\n                  className="gdrive-chip-action"','                <button\n                  type="button"\n                  className="gdrive-chip-action danger"');
  cut('              <button\n                type="button"\n                className="gdrive-action-btn"','            <div className="gdrive-search-row">','            </div>\n');
  cut('            <div className="gdrive-tabs"', '            <MobileScroll');
  cut('                              <button\n                                type="button"\n                                className="gdrive-row-btn warn"', '                            </>');
  cut('                          {file.webViewLink ?', '                        </div>\n                      </li>');
  cut('                {pendingConfirm.kind === "trash" ?', '                <button\n                  type="button"\n                  className={');
  cut('                اربط حسابك', '              </p>', '                اربط حسابك لحفظ نسخ مساحة العمل واستعادتها. يعرض التطبيق ملفات النسخ التي مُنح حق الوصول إليها.\n');
  view=view.replace('ودمج بياناتها في مساحة عمل نسقو برو الحالية.', 'وفحصها في مساحة معزولة. تتطلب الاستعادة موافقة أخرى على الهاتف.');
  view=view.replaceAll('accessToken','connected');
  view=view.replace('{errorMsg ? (','{status && <div className="gdrive-alert" role="status">{status}</div>}{progress != null && <progress max="100" value={progress} aria-label="تقدم التنزيل"/>}{errorMsg ? (');
  return `
    import {useEffect,useState} from 'react';
    import {ArchiveIcon,CheckCircledIcon,Cross2Icon,DownloadIcon,ExclamationTriangleIcon,FileTextIcon,LayersIcon,MagnifyingGlassIcon,ReloadIcon,TableIcon} from '@radix-ui/react-icons';
    import {GoogleSignInButton} from './src/components/GoogleSignInButton';
    import {NasqoBrandLoader} from './src/components/NasqoBrandLoader';
    import {MobileScroll} from './src/mobile/MobileScroll';
    import {formatDriveFileSize,filterDriveFiles,getDriveMimeLabelAr,classifyDriveMimeType,DRIVE_FOLDER_MIME} from './src/services/googleDriveHelpers';
    import {send} from './qa/hybrid_home/workspace';
    const KeyboardInput='input';
    export function DrivePresentation({model}) {
      const {connected,files,busyAction,errorMsg,status,progress}=model;
      const [search,setSearch]=useState('');
      const [pendingConfirm,setPendingConfirm]=useState(null);
      const visibleFiles=filterDriveFiles(files,search,'backups');
      const loading=busyAction==='auth'||busyAction==='refresh';
      const connectedName='',connectedEmail='',quotaLimit=0,quotaPct=null,quotaUsed=0,currentFolder={id:null};
      const handleClose=()=>{if(!busyAction)send('close');};
      const handleAuthorizeDrive=()=>send('connect'),clearGoogleAccessToken=()=>send('disconnect'),onNotify=()=>{};
      const handleBackupWorkspaceNow=()=>send('backup'),loadDriveContents=()=>send('refresh');
      const handleDownloadFile=file=>send('download',{id:file.id});
      const executeConfirmedAction=()=>{const file=pendingConfirm.file;setPendingConfirm(null);send('inspect',{id:file.id});};
      useEffect(()=>{document.documentElement.classList.toggle('dark',model.dark);},[model.dark]);
      useEffect(()=>{send('overlay',{active:!!pendingConfirm});window.nasqoBack=()=>{if(pendingConfirm){setPendingConfirm(null);return true;}return false;};},[pendingConfirm]);
      useEffect(()=>{if(!connected)setPendingConfirm(null);},[connected]);
      useEffect(()=>{document.fonts.ready.then(()=>send('paint'));},[]);
  `+view;
}
