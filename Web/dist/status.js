// Product status priorities; these labels describe readings, not diagnoses.
const STATUS = Object.freeze({
  urgent: {id:'urgent',label:'우선 확인',color:'#C8404B',soft:'#FCECEF',face:'concerned'},
  rising: {id:'rising',label:'온도 상승',color:'#BD6424',soft:'#FFF0E3',face:'worried'},
  check: {id:'check',label:'측정 확인',color:'#947009',soft:'#FFF6D5',face:'neutral'},
  stable: {id:'stable',label:'범위 안',color:'#2D855C',soft:'#EAF6EF',face:'smile'},
  info: {id:'info',label:'안내',color:'#477BAE',soft:'#EBF3FC',face:'resting'},
});

export function severityForEvent(event={}) {
  if(event.kind==='high'||event.kind==='low')return STATUS.urgent;
  if(event.kind==='rise')return STATUS.rising;
  if(event.kind==='connection'||event.kind==='motion')return STATUS.check;
  if(event.kind==='recovery'||event.kind==='normal')return {...STATUS.stable,label:'범위 복귀'};
  return STATUS.info;
}

export function statusForReading(sample,activeEvent,settings={low:36,high:38}) {
  if(sample?.contact===false)return {...STATUS.info,label:'측정 대기'};
  if(!Number.isFinite(sample?.head)||!Number.isFinite(sample?.torso))return {...STATUS.check,label:'측정 확인'};
  const value=Math.max(sample.head,sample.torso);
  if(value>settings.high||value<settings.low)return {...STATUS.urgent,label:'확인 필요'};
  if(activeEvent?.kind==='rise')return STATUS.rising;
  if(activeEvent&&['connection','motion'].includes(activeEvent.kind))return STATUS.check;
  if(value>=settings.high-.2||value<=settings.low+.2)return {...STATUS.check,label:'변화 관찰'};
  return STATUS.stable;
}

export function faceSVG(status) {
  const face=status?.face||'resting';
  const mouths={
    smile:'M10 18 Q16 24 22 18',
    neutral:'M11 20 H21',
    worried:'M11 21 Q16 17 21 21',
    concerned:'M10 22 Q16 15 22 22',
    resting:'M12 20 Q16 21 20 20',
  };
  const eyes=face==='resting'
    ?'<path d="M9.5 13.5q2 2 4 0m5 0q2 2 4 0" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>'
    :'<circle cx="11.5" cy="13.5" r="1.4" fill="currentColor"/><circle cx="20.5" cy="13.5" r="1.4" fill="currentColor"/>';
  return `<svg class="status-face-icon" viewBox="0 0 32 32" fill="none" aria-hidden="true"><circle cx="16" cy="16" r="14.5" fill="var(--status-soft,#EAF6EF)" stroke="currentColor" stroke-width="1.2"/>${eyes}<path d="${mouths[face]||mouths.resting}" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>`;
}

export function statusLegendHTML() {
  const items=[STATUS.urgent,STATUS.rising,STATUS.check,STATUS.stable,STATUS.info];
  return `<div class="status-legend" aria-label="알림 상태 색상">${items.map(s=>`<span style="--status-color:${s.color};--status-soft:${s.soft}"><i aria-hidden="true"></i>${s.label}</span>`).join('')}</div>`;
}
