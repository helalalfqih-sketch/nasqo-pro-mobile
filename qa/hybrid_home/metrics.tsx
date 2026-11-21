import React, {useEffect, useLayoutEffect, useRef, useState} from 'react';
import {ArrowLeftIcon, ArrowRightIcon, CheckIcon, DrawingPinFilledIcon, DrawingPinIcon,
  EyeNoneIcon, PersonIcon, ResetIcon, RulerHorizontalIcon, RulerSquareIcon} from '@radix-ui/react-icons';
import {getVisibleOrderedHomeTiles, moveHomeTile, normalizeCardLayout, stepHomeTile,
  toggleHideHomeTile, togglePinHomeTile, toggleToneHomeTile, type CardLayout} from '../../src/utils/dashboardPrefs';
import {formatAmount} from '../../src/accounting';
import {send, triggerHaptic} from './workspace';

// Order and anatomy from qa/implementation-dashboard-v5.png.
const cards = {
  sales: ['المبيعات', PersonIcon], purchases: ['المشتريات', PersonIcon],
  clients: ['العملاء', PersonIcon], employees: ['الموظفين', PersonIcon],
  transfers: ['الحوالات', PersonIcon], shop: ['المحل', PersonIcon],
  measurements: ['تمييز ومقاسات', RulerHorizontalIcon], 'measurement-new': ['مقاس جديد', RulerSquareIcon],
} as const;
type Metric = keyof typeof cards;
const ids = Object.keys(cards) as Metric[];

export function HomeMetrics({balances, count, currency, initialLayout, onOpen, onEditing, backRef, tileEditing}) {
  const [layout,setLayout] = useState<CardLayout<Metric>>(()=>normalizeCardLayout(ids,initialLayout));
  const [selected,select] = useState<Metric | null>(null);
  const editing=selected!==null;
  const current=useRef(layout);
  const timer=useRef(0);
  const gesture=useRef<{id:Metric,x:number,y:number,last?:Metric} | null>(null);
  const suppressClick=useRef(false);
  const clearTimer=()=>window.clearTimeout(timer.current);
  const save=(next:CardLayout<Metric>)=>{
    if(next===current.current) return;
    current.current=next;
    setLayout(next);
    send('metricLayout',{value:next});
  };
  const edit=(id:Metric)=>{
    suppressClick.current=true;
    select(id);
    triggerHaptic('pin');
  };
  useEffect(()=>clearTimer,[]);
  useLayoutEffect(()=>{
    onEditing(editing);
    if (!editing) return;
    backRef.current=()=>{select(null);return true;};
    const escape=(e:KeyboardEvent)=>{if(e.key==='Escape') select(null);};
    window.addEventListener('keydown',escape);
    return ()=>{backRef.current=null;window.removeEventListener('keydown',escape);};
  },[editing]);
  useEffect(()=>{if(tileEditing) select(null);},[tileEditing]);

  const {allVisibleIds}=getVisibleOrderedHomeTiles(layout);
  return <section className="section-block metrics-section" aria-label="بطاقات الملخص">
    <div className="metrics-grid">
      {allVisibleIds.map(id=>{
        const [label,Icon]=cards[id], value=balances[id], financial=typeof value==='number';
        const tone=financial ? (value < -0.005 ? 'debit' : 'credit') : 'measurement';
        return <div key={id} className="home-metric-slot">
          <button type="button" data-metric={id}
            aria-label={financial ? label+' '+formatAmount(Math.abs(value))+' '+currency+' '+(Math.abs(value)<0.005?'متزن':value>0?'دائن':'مدين') :
              id==='measurements'?label+' '+count:label}
            data-scroll-drag={editing ? 'ignore' : undefined}
            data-selected={selected===id || undefined} data-editing={editing || undefined}
            data-accent={layout.toneOverrides[id]} className={'metric-card '+tone+' metric-card-'+id}
            onContextMenu={e=>{e.preventDefault();if(!tileEditing && !editing) edit(id);}}
            onKeyDown={e=>{if(e.key==='F2'&&!tileEditing){e.preventDefault();edit(id);}}}
            onPointerDown={e=>{
              if(e.button!==0 || tileEditing) return;
              clearTimer();suppressClick.current=false;
              gesture.current={id,x:e.clientX,y:e.clientY};
              if(editing) e.currentTarget.setPointerCapture(e.pointerId);
              else timer.current=window.setTimeout(()=>edit(id),450);
            }}
            onPointerMove={e=>{
              const g=gesture.current;
              if(!g || g.id!==id || Math.hypot(e.clientX-g.x,e.clientY-g.y)<9) return;
              clearTimer();
              if(!editing){gesture.current=null;return;}
              suppressClick.current=true;
              const over=document.elementFromPoint(e.clientX,e.clientY)?.closest<HTMLElement>('[data-metric]')?.dataset.metric as Metric|undefined;
              if(over && over!==id && over!==g.last){g.last=over;select(id);save(moveHomeTile(current.current,id,over));}
            }}
            onPointerUp={()=>{clearTimer();gesture.current=null;}}
            onPointerCancel={()=>{clearTimer();gesture.current=null;}}
            onPointerLeave={()=>{if(!editing) clearTimer();}}
            onClick={()=>{
              if(suppressClick.current){suppressClick.current=false;return;}
              if(editing){select(id);return;}
              onOpen(financial ? 'group-'+id : id);
            }}>
            {layout.pinned.includes(id) && <DrawingPinFilledIcon className="metric-pin" aria-label="مثبّتة"/>}
            <span className="metric-icon"><Icon/></span>
            <span className="metric-copy"><small>{label}</small>
              {financial ? <strong aria-label={formatAmount(Math.abs(value))+' '+currency}>
                <bdi>{value < -0.005 ? '−' : ''}{formatAmount(Math.abs(value))}</bdi>
              </strong> : id==='measurements' && count>0 ? <strong>{count}</strong> : null}
            </span>
          </button>
        </div>;
      })}
    </div>
    {selected && <div className="smart-edit-bar" role="region" aria-label="تخصيص بطاقات المؤشرات" data-testid="metric-editor">
      <div className="smart-edit-selected-strip">
        <strong>{cards[selected][0]}</strong>
        <div className="smart-edit-selected-btns">
          <button aria-label="تثبيت المؤشر" aria-pressed={layout.pinned.includes(selected)}
            onClick={()=>save(togglePinHomeTile(layout,selected))}><DrawingPinIcon/></button>
          <button aria-label="تقديم المؤشر" onClick={()=>save(stepHomeTile(layout,selected,-1))}><ArrowRightIcon/></button>
          <button aria-label="تأخير المؤشر" onClick={()=>save(stepHomeTile(layout,selected,1))}><ArrowLeftIcon/></button>
          <button onClick={()=>save(toggleToneHomeTile(layout,selected,'blue'))}>تبديل اللون</button>
          <button aria-label="إخفاء المؤشر" disabled={allVisibleIds.length<=2} onClick={()=>{
            const next=toggleHideHomeTile(layout,selected);save(next);select(getVisibleOrderedHomeTiles(next).allVisibleIds[0]);
          }}><EyeNoneIcon/></button>
        </div>
      </div>
      {layout.hidden.map(id=><button key={id} className="smart-hidden-chip" onClick={()=>save(toggleHideHomeTile(layout,id))}>إظهار {cards[id][0]}</button>)}
      <div className="smart-edit-bar-actions">
        <button className="smart-edit-btn secondary" onClick={()=>save(normalizeCardLayout(ids))}><ResetIcon/>افتراضي</button>
        <button className="smart-edit-btn primary" onClick={()=>select(null)}><CheckIcon/>تم</button>
      </div>
    </div>}
  </section>;
}
