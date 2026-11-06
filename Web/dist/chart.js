const MAX_COLOR = '#D64B4B';
const MIN_COLOR = '#2F9363';
const LINE_COLOR = '#a60031';
const fmt = value => Number.isFinite(value) ? value.toFixed(1) : '—';
const shortClock = value => new Date(value).toLocaleTimeString('ko-KR', {hour:'2-digit',minute:'2-digit',hour12:false});
const dayStart = value => {const date=new Date(value);date.setHours(0,0,0,0);return +date;};
const nextDay = value => {const date=new Date(value);date.setDate(date.getDate()+1);return +date;};
const minimum = point => Number.isFinite(point.min) ? point.min : point.v;
const maximum = point => Number.isFinite(point.max) ? point.max : point.v;

/** Compact trend beside the current reading, with contact gaps preserved. */
export function renderMiniChart(element, points, {start,end}) {
  if(!element)return;
  const valid=points.filter(point=>Number.isFinite(point.v)&&Number.isFinite(+point.date)&&point.date>=start&&point.date<=end);
  if(!valid.length){element.innerHTML='<span class="mini-empty">측정 없음</span>';element.setAttribute('aria-label','최근 6시간 측정 없음');return;}
  const width=160,height=64,left=4,right=36,top=8,bottom=8;
  const low=Math.min(36,Math.min(...valid.map(point=>point.v))-.2);
  const high=Math.max(39,Math.max(...valid.map(point=>point.v))+.2);
  const x=date=>left+(date-start)/Math.max(1,end-start)*(width-left-right);
  const y=value=>top+(high-value)/(high-low)*(height-top-bottom);
  const groups=[];let group=[];
  const flush=()=>{if(group.length)groups.push(group);group=[];};
  for(const point of points){
    if(!Number.isFinite(point.v)||!Number.isFinite(+point.date)||point.date<start||point.date>end){flush();continue;}
    const previous=group.at(-1);
    if(previous&&(point.segment!==previous.segment||point.date-previous.date>75000))flush();
    group.push(point);
  }
  flush();
  let svg='';
  for(const value of [low,(low+high)/2,high]){
    const yy=y(value);
    svg+=`<line x1="${left}" y1="${yy}" x2="${width-right}" y2="${yy}" stroke="#dedad4" stroke-width=".6" stroke-dasharray="2 3"/><text x="${width-right+8}" y="${yy+3}" fill="#96928c" font-size="9" font-variant-numeric="tabular-nums">${fmt(value)}°</text>`;
  }
  for(const segment of groups){
    const line=segment.map((point,index)=>`${index?'L':'M'}${x(point.date).toFixed(2)},${y(point.v).toFixed(2)}`).join(' ');
    if(segment.length>1){
      svg+=`<path d="${line} L${x(segment.at(-1).date)},${height-bottom} L${x(segment[0].date)},${height-bottom}Z" fill="#a6003109"/><path d="${line}" fill="none" stroke="${LINE_COLOR}" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round"/>`;
    }else svg+=`<circle cx="${x(segment[0].date)}" cy="${y(segment[0].v)}" r="1.5" fill="${LINE_COLOR}"/>`;
  }
  const last=valid.at(-1);
  if(end-last.date<=75000)svg+=`<circle cx="${x(last.date)}" cy="${y(last.v)}" r="2.5" fill="${LINE_COLOR}" stroke="white" stroke-width="1"/>`;
  element.innerHTML=`<svg viewBox="0 0 ${width} ${height}" aria-hidden="true">${svg}</svg>`;
  element.setAttribute('aria-label',`최근 6시간 온도 변화, ${fmt(valid[0].v)}도에서 ${fmt(last.v)}도`);
}

/** Shared plot for live readings, day segments and seven daily means. */
export function renderChart(element, points, options) {
  if(!element)return;
  const validPoints=points.filter(point=>Number.isFinite(point.v)&&Number.isFinite(+point.date));
  element.onpointerdown=null;element.onpointermove=null;element.onkeydown=null;
  if(!validPoints.length){
    element.innerHTML='<div class="empty-state">이 기간에는 온도 기록이 없어요</div>';
    return;
  }
  const {start,end,chosen,week=false,onSelect}=options;
  const width=360,height=216,left=8,right=40,top=40,bottom=28;
  const plotWidth=width-left-right,plotHeight=height-top-bottom;
  const observedMin=validPoints.reduce((value,point)=>Math.min(value,minimum(point)),Infinity);
  const observedMax=validPoints.reduce((value,point)=>Math.max(value,maximum(point)),-Infinity);
  const low=Math.min(36,Math.floor((observedMin-.15)*2)/2);
  const high=Math.max(38.5,Math.ceil((observedMax+.15)*2)/2);
  const duration=Math.max(1,end-start);
  const x=date=>left+(date-start)/duration*plotWidth;
  const y=value=>top+(high-value)/(high-low)*plotHeight;

  // The labels occupy separate slots rather than following nearly equal y-values.
  let svg=`<g class="chart-extrema-legend" font-size="12" font-weight="500" style="font-variant-numeric:tabular-nums">
    <line x1="${left}" y1="12" x2="${left+16}" y2="12" stroke="${MAX_COLOR}" stroke-width="1.5" stroke-dasharray="4 3"/>
    <text x="${left+24}" y="16" fill="${MAX_COLOR}">최고 ${fmt(observedMax)}°C</text>
    <line x1="${left+160}" y1="12" x2="${left+176}" y2="12" stroke="${MIN_COLOR}" stroke-width="1.5" stroke-dasharray="4 3"/>
    <text x="${left+184}" y="16" fill="${MIN_COLOR}">최저 ${fmt(observedMin)}°C</text>
  </g>`;
  for(let index=0;index<4;index++){
    const value=low+(high-low)*index/3,yy=y(value);
    svg+=`<line class="chart-axis" x1="${left}" y1="${yy}" x2="${width-right}" y2="${yy}"/><text class="chart-label" x="${width-right+8}" y="${yy+3}">${fmt(value)}</text>`;
  }
  if(week){
    let day=dayStart(start);
    for(let index=0;index<7;index++){
      const date=new Date(day);date.setHours(12,0,0,0);
      svg+=`<text class="chart-label" text-anchor="middle" x="${x(+date)}" y="${height-4}">${date.toLocaleDateString('ko-KR',{weekday:'narrow'})}</text>`;
      day=nextDay(day);
    }
  }else{
    for(let index=0;index<4;index++){
      const date=start+(end-start)*index/3;
      svg+=`<text class="chart-label" text-anchor="${index===0?'start':index===3?'end':'middle'}" x="${x(date)}" y="${height-4}">${shortClock(date)}</text>`;
    }
  }

  const groups=[];let current=[];
  const flush=()=>{if(current.length)groups.push(current);current=[];};
  points.forEach(point=>{
    if(!Number.isFinite(point.v)||!Number.isFinite(+point.date)){flush();return;}
    const previous=current.at(-1);
    const broken=previous&&(week
      ? dayStart(point.date)!==nextDay(dayStart(previous.date))
      : point.segment!==previous.segment||point.date-previous.date>(options.history?600000:75000));
    if(broken)flush();
    current.push(point);
  });
  flush();

  // Fill and uncertainty bands stop at the same contact gaps as the measured line.
  groups.forEach(group=>{
    if(group.length<2)return;
    const line=group.map((point,index)=>`${index?'L':'M'}${x(point.date).toFixed(2)},${y(point.v).toFixed(2)}`).join(' ');
    svg+=`<path class="chart-area" d="${line} L${x(group.at(-1).date)},${y(low)} L${x(group[0].date)},${y(low)}Z"/>`;
    if(options.history&&!week){
      const range=group.map((point,index)=>`${index?'L':'M'}${x(point.date)},${y(maximum(point))}`).join(' ')
        +group.slice().reverse().map(point=>`L${x(point.date)},${y(minimum(point))}`).join(' ')+'Z';
      svg+=`<path d="${range}" fill="#a6003112"/>`;
    }
  });

  groups.forEach(group=>{
    if(group.length>1){
      const line=group.map((point,index)=>`${index?'L':'M'}${x(point.date).toFixed(2)},${y(point.v).toFixed(2)}`).join(' ');
      svg+=`<path class="chart-path" d="${line}"/>`;
    }
    if(week||group.length===1)group.forEach(point=>{
      svg+=`<circle cx="${x(point.date)}" cy="${y(point.v)}" r="${week?2.8:2}" fill="${LINE_COLOR}"/>`;
    });
  });
  // These are range guides, not measured samples: retain a dashed pattern across the plot.
  // Equal extrema use alternating dashes at their true y-position so neither color disappears.
  const equal=Math.abs(observedMax-observedMin)<1e-9;
  svg+=`<line class="chart-maximum-guide" x1="${left}" y1="${y(observedMax)}" x2="${width-right}" y2="${y(observedMax)}" stroke="${MAX_COLOR}" stroke-width="1.25" stroke-dasharray="6 6"/>
    <line class="chart-minimum-guide" x1="${left}" y1="${y(observedMin)}" x2="${width-right}" y2="${y(observedMin)}" stroke="${MIN_COLOR}" stroke-width="1.25" stroke-dasharray="6 6" stroke-dashoffset="${equal?6:0}"/>`;
  if(chosen&&Number.isFinite(chosen.v)&&Number.isFinite(+chosen.date)){
    svg+=`<line x1="${x(chosen.date)}" y1="${top}" x2="${x(chosen.date)}" y2="${height-bottom}" stroke="${LINE_COLOR}" stroke-opacity=".25"/><circle cx="${x(chosen.date)}" cy="${y(chosen.v)}" r="4" fill="${LINE_COLOR}" stroke="white" stroke-width="2"/>`;
  }
  element.innerHTML=`<svg viewBox="0 0 ${width} ${height}" aria-hidden="true">${svg}</svg>`;
  if(!onSelect)return;
  const choose=event=>{
    const bounds=element.getBoundingClientRect();
    if(!bounds.width)return;
    const xx=(event.clientX-bounds.left)/bounds.width*width;
    const date=start+Math.max(0,Math.min(1,(xx-left)/plotWidth))*(end-start);
    onSelect(date);
  };
  element.onpointerdown=event=>{if(event.button===0){element.setPointerCapture?.(event.pointerId);choose(event);}};
  element.onpointermove=event=>{if(event.buttons===1)choose(event);};
  element.onkeydown=event=>{
    if(event.key!=='ArrowLeft'&&event.key!=='ArrowRight')return;
    event.preventDefault();
    const direction=event.key==='ArrowLeft'?-1:1;
    const selectedIndex=chosen?validPoints.findIndex(point=>point===chosen||point.date===chosen.date):-1;
    const index=selectedIndex>=0?selectedIndex:(direction<0?validPoints.length:-1);
    const next=Math.max(0,Math.min(validPoints.length-1,index+direction));
    onSelect(validPoints[next].date);
  };
}
