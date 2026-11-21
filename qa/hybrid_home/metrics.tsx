import React from 'react';
import {
  BarChartIcon, PersonIcon, RulerHorizontalIcon, RulerSquareIcon, SwitchIcon,
} from '@radix-ui/react-icons';
import {CartIcon, PeopleIcon, ShopIcon} from 'dashboard:presentation';
import {formatAmount} from '../../src/accounting';

// The eight-card design uses the historical metric-card markup and the two
// measurement destinations specified for Android in AGENTS.md.
const cards = [
  ['sales', 'المبيعات', BarChartIcon], ['purchases', 'المشتريات', CartIcon],
  ['clients', 'العملاء', PeopleIcon], ['employees', 'الموظفين', PersonIcon],
  ['transfers', 'الحوالات', SwitchIcon], ['shop', 'المحل', ShopIcon],
  ['measurements', 'تمييز ومقاسات', RulerHorizontalIcon],
  ['measurement-new', 'مقاس جديد', RulerSquareIcon],
] as const;

export function HomeMetrics({balances, count, currency, onOpen}) {
  return <section className="section-block metrics-section" aria-label="بطاقات الملخص">
    <div className="metrics-grid">
      {cards.map(([id, label, Icon]) => {
        const value = balances[id];
        const financial = typeof value === 'number';
        const tone = financial ? (value >= 0 ? 'credit' : 'debit') : 'measurement';
        return <div key={id} className="home-metric-slot">
          <button type="button" data-metric={id} className={`metric-card ${tone} metric-card-${id}`}
            onClick={() => onOpen(financial ? 'group-' + id : id)}>
            <span className="metric-icon"><Icon /></span>
            <span className="metric-copy"><small>{label}</small>
              {financial ? <strong aria-label={`${formatAmount(Math.abs(value))} ${currency}`}>
                <bdi>{value < -0.005 ? '−' : ''}{formatAmount(Math.abs(value))}</bdi>
              </strong> : id === 'measurements' ? <strong>{count}</strong> : null}
            </span>
          </button>
        </div>;
      })}
    </div>
  </section>;
}
