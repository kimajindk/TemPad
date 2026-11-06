import { createThermalMonitor, pointTemperature } from './thermal.js';

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const paths = {
  home:'<path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1z"/>',
  bell:'<path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M9 21h6"/>',
  sliders:'<path d="M3 6h6m4 0h8M3 12h10m4 0h4M3 18h3m4 0h11"/><circle cx="11" cy="6" r="2"/><circle cx="15" cy="12" r="2"/><circle cx="8" cy="18" r="2"/>',
  wave:'<path d="M1 12h4l2-7 3 15 3-18 3 15 2-5h5"/>',
  chevron:'<path d="m9 5 7 7-7 7"/>',
  back:'<path d="m15 5-7 7 7 7"/>',
  close:'<path d="m6 6 12 12M6 18 18 6"/>',
  expand:'<path d="M4 10V4h6M4 4l6 6m10 4v6h-6m6 0-6-6"/>',
  info:'<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7h.01"/>',
  thermometer:'<path d="M9 14.2V5a3 3 0 0 1 6 0v9.2a5 5 0 1 1-6 0Z"/><path d="M12 8v9m6-12h3m-3 4h2"/><circle cx="12" cy="18" r="1"/>',
  plus:'<path d="M12 5v14M5 12h14"/>',
  minus:'<path d="M5 12h14"/>',
  wifi:'<path d="M3 8a15 15 0 0 1 18 0M6 12a10 10 0 0 1 12 0M9 16a5 5 0 0 1 6 0M12 20h.01"/>',
};
const icon = name => `<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths[name] || paths.thermometer}</svg>`;
$$('[data-icon]').forEach(el => el.innerHTML = icon(el.dataset.icon));
const fmt = value => Number.isFinite(value) ? value.toFixed(1) : '—';
const clock = value => new Date(value).toLocaleTimeString('ko-KR', {hour:'numeric',minute:'2-digit'});
const shortClock = value => new Date(value).toLocaleTimeString('ko-KR', {hour:'2-digit',minute:'2-digit',hour12:false});
const dateLabel = value => new Date(value).toLocaleDateString('ko-KR', {month:'long',day:'numeric'});
const fullDate = value => `${dateLabel(value)} · ${clock(value)}`;
const dayStart = value => { const d = new Date(value); d.setHours(0,0,0,0); return +d; };
const nextDay = (value, offset = 1) => {const d = new Date(value); d.setDate(d.getDate()+offset); return +d;};
const average = list => list.length ? list.reduce((a,b)=>a+b,0)/list.length : NaN;
let settings = {low:36, high:38};
try {
  const saved = JSON.parse(localStorage.getItem('tempad.preferences.v1'));
  if(saved && Number.isFinite(saved.low) && Number.isFinite(saved.high) && saved.low >= 30 && saved.high <= 45 && saved.high-saved.low >= .999) settings = saved;
} catch {}
let draft = {...settings};
const startedAt = Date.now();
let tab = 'home';
let selected = null;
let latest = {date:startedAt,head:36.6,torso:36.8};
let lastIndex = -1;
let popup = null;
let activeEvent = null;
let shown = new Set();
let queued = [];
let events = [];
let samples = [];
let liveSamples = [];
let homeMonitor = null;
let expandedMonitor = null;
let sheetKind = null;
let sheetStack = [];
let eventId = null;
let history = {period:'day',region:'torso',anchor:startedAt,selection:null};
let tracking = {minutes:15,selection:null};
let storageIssue = false;
let lastFocused = null;
const main = $('#main'), sheet = $('#sheet'), alertDialog = $('#alert');

function inputAt(seconds) {
  let torso;
  if(seconds < 10) torso = 36.8;
  else if(seconds < 30) torso = 36.8 + .6 * (seconds-10)/20;
  else if(seconds < 60) torso = 37.4 + (seconds-30)/30;
  else if(seconds < 90) torso = 38.4 + .2*(seconds-60)/30;
  else torso = 38.5 + .1*Math.cos((seconds-90)/35);
  return {date:startedAt+seconds*1000,head:Math.round((torso-.2+1e-9)*10)/10,torso:Math.round((torso+1e-9)*10)/10};
}
function seedHistory() {
  samples = [];
  events = [];
  for(let offset=-86400;offset<0;offset+=60) samples.push({date:startedAt+offset*1000,head:36.6,torso:36.8});
  const seeds = [['rise',-24*60,37.3,36.8],['high',-2*3600,38.2,36.8],['connection',-5*3600,null,null],['rise',-19*3600,37.4,36.9]];
  seeds.forEach(([kind,offset,value,reference])=>{
    const date = startedAt+offset*1000;
    const event = {id:`past-${kind}-${date}`,kind,date,value,reference,low:36,high:38,ack:date+24000,resolved:date+(kind==='connection'?120000:600000)};
    events.push(event);shown.add(event.id);
    if(value===null)return;
    samples = samples.filter(s=>Math.abs(s.date-date)>600000);
    for(let second=-600;second<=600;second+=5){
      const baseline=reference;
      const temperature=second < -120 ? baseline : second < 0 ? baseline+(value-baseline)*(second+120)/120 : value+(36.8-value)*second/600;
      samples.push({date:date+second*1000,head:temperature-.2,torso:temperature});
    }
  });
  samples.sort((a,b)=>a.date-b.date);
}
function eventTitle(event) {return event.kind==='rise'?'온도 변화를 확인해 주세요':event.kind==='connection'?'온도 정보를 받지 못했어요':'온도를 확인해 주세요';}
function eventLabel(event) {return ({rise:'빠른 온도 상승',high:'상한 초과',low:'하한 미만',connection:'연결 확인'})[event.kind];}
function eventDescription(event) {
  if(event.kind==='rise')return `최근 ${fmt(event.reference)} °C에서 ${fmt(event.value)} °C로 올라갔어요. 아기의 상태를 확인해 주세요.`;
  if(event.kind==='high')return `${fmt(event.value)} °C가 감지되어 설정 상한 ${fmt(event.high)} °C를 넘었어요.`;
  if(event.kind==='low')return `${fmt(event.value)} °C가 감지되어 설정 하한 ${fmt(event.low)} °C보다 낮아요.`;
  return '새로운 온도 정보가 도착하지 않았어요. 패드 연결을 확인해 주세요.';
}
function receive(sample) {
  const value=Math.max(sample.head,sample.torso);
  const baseline=Math.min(...liveSamples.filter(s=>sample.date-s.date<=300000).map(s=>Math.max(s.head,s.torso)));
  const absolute=value>settings.high?'high':value<settings.low?'low':null;
  let kind=null;
  if(activeEvent){
    if(absolute && absolute!==activeEvent.kind){activeEvent.resolved=sample.date;activeEvent=null;kind=absolute;}
  }else if(absolute)kind=absolute;
  else if(Number.isFinite(baseline)&&value-baseline>=.5-1e-6)kind='rise';
  liveSamples.push(sample);samples.push(sample);latest=sample;
  if(kind){
    const event={id:`${kind}-${sample.date}`,kind,date:sample.date,value,reference:kind==='rise'?baseline:null,low:settings.low,high:settings.high,ack:null,resolved:null};
    activeEvent=event;events.push(event);queued.push(event.id);
  }
}
function tick(){
  const index=Math.floor((Date.now()-startedAt)/5000);
  for(let i=lastIndex+1;i<=index;i++) receive(inputAt(i*5));
  if(index!==lastIndex){lastIndex=index;updateReadings();updateSheetData();if(tab==='events')renderEvents();}
  const age=$('#reading-age');if(age)age.textContent=`${Math.max(0,Math.floor((Date.now()-latest.date)/1000))}초 전 갱신`;
  $('#alert-dot').hidden=!events.some(e=>!e.ack&&!e.resolved);
  presentNext();
}
function setPoint(point){selected=point;homeMonitor?.setSelected(point);expandedMonitor?.setSelected(point);tracking.selection=null;updateReadings();if(sheetKind==='expanded')renderTracking();}
function selectedValue(sample=latest){return pointTemperature(selected,sample);}
function warning(){return !!activeEvent||latest.torso>settings.high||latest.torso<settings.low;}
function renderHome(){
  main.innerHTML=`<div class="page-heading"><h1>모니터링</h1><time datetime="${new Date().toISOString()}">${dateLabel(Date.now())}</time></div>
    <section class="monitor-card" aria-label="아기 온도 모니터링">
      <div class="thermal-wrap"><div id="thermal-home" class="thermal-view"></div><button class="expand-button" id="expand-monitor" aria-label="모니터링 상세보기">${icon('expand')}</button></div>
      <div class="reading-card"><div><div class="reading-heading"><span id="reading-title">보정 온도</span><button class="info-button" id="measurement-info" aria-label="측정 방식 안내">${icon('info')}</button></div><div class="big-value"><span id="current-temperature"></span><span class="unit">°C</span></div></div>
      <div class="reading-state"><div id="reading-state" class="state-line"></div><small id="reading-age"></small></div></div>
    </section><button class="text-link" id="open-history">${icon('wave')}<span>온도 흐름 자세히 보기</span>${icon('chevron')}</button>`;
  homeMonitor=createThermalMonitor($('#thermal-home'),{onSelect:setPoint});homeMonitor.setSample(latest);homeMonitor.setSelected(selected);
  $('#expand-monitor').onclick=()=>openSheet('expanded');$('#measurement-info').onclick=()=>openSheet('info');$('#open-history').onclick=()=>openSheet('history');updateReadings();
}
function updateReadings(){
  homeMonitor?.setSample(latest);expandedMonitor?.setSample(latest);
  if(tab!=='home')return;
  $('#current-temperature').textContent=fmt(selectedValue());
  $('#reading-title').textContent=selected?'선택 지점':'보정 온도';
  $('#reading-state').innerHTML=selected?'<span class="muted tiny">빈 곳을 눌러 해제</span>':`<i class="status-dot${warning()?' warning':''}" aria-hidden="true"></i><span>${warning()?'온도 확인 필요':'설정 범위 안'}</span>`;
  $('#reading-age').textContent=`${Math.max(0,Math.floor((Date.now()-latest.date)/1000))}초 전 갱신`;
}
function eventCard(event){return `<button class="event-card" data-event="${event.id}"><span class="event-glyph">${icon(event.kind==='connection'?'wifi':'thermometer')}</span><span class="event-copy"><h3>${eventLabel(event)}</h3><p>${eventDescription(event)}</p><time>${fullDate(event.date)}</time></span><span class="event-status${!event.resolved?' active':''}">${event.resolved?'종료':event.ack?'확인함':'확인 필요'}</span></button>`;}
function bindEvents(root=document){$$('[data-event]',root).forEach(el=>el.onclick=()=>openSheet('event',el.dataset.event));}
function renderEvents(){
  main.innerHTML=`<div class="page-heading"><h1>알림 기록</h1></div><p class="page-subtitle">최근 알림을 확인하세요</p><p class="count-label">최근 7일 · ${events.length}건</p><div class="event-list">${events.slice().sort((a,b)=>b.date-a.date).map(eventCard).join('')}</div>`;bindEvents(main);
}
function renderSettings(){
  draft={...settings};
  main.innerHTML=`<div class="page-heading"><h1>설정</h1></div><p class="page-subtitle">알림과 모니터링 환경</p>
    <section class="section-card"><h2>${icon('thermometer')}온도 알림</h2><p class="small muted">설정 범위를 벗어나면 바로 알려드려요.</p><p class="settings-note">최근 5분 내 0.5°C 이상 상승해도 알려드려요.</p>${thresholdRow('high','상한 온도')}${thresholdRow('low','하한 온도')}<button class="primary-button" id="save-settings">변경사항 저장</button><p id="settings-error" class="warning-copy" role="status"></p></section>
    <section class="section-card"><h2>${icon('bell')}화면 알림</h2><p class="small muted">온도 변화가 감지되면 보고 있는 화면 위에 팝업으로 알려드려요.</p><div class="rule"></div><dl><div class="definition-row"><dt>온도 단위</dt><dd>섭씨 °C</dd></div><div class="definition-row"><dt>측정 간격</dt><dd>5초</dd></div></dl></section>
    <img class="settings-logo" src="./assets/logo.png" alt="TemPad"><p class="settings-version">TemPad</p>`;
  $$('[data-step]',main).forEach(button=>button.onclick=()=>{
    const field=button.dataset.field;
    let value=Math.round((draft[field]+Number(button.dataset.step))*10)/10;
    if(field==='high')value=Math.min(45,Math.max(draft.low+1,value));else value=Math.max(30,Math.min(draft.high-1,value));
    draft[field]=value;$(`#threshold-${field}`).textContent=`${fmt(value)}°`;$('#save-settings').textContent='변경사항 저장';
  });
  $('#save-settings').onclick=()=>{
    settings={...draft};
    try{localStorage.setItem('tempad.preferences.v1',JSON.stringify(settings));storageIssue=false;}catch{storageIssue=true;}
    if(activeEvent){activeEvent.resolved=Date.now();activeEvent=null;}queued=[];
    $('#save-settings').textContent=storageIssue?'이번 실행에 적용했어요':'저장했어요';
    $('#settings-error').textContent=storageIssue?'브라우저 저장 공간을 사용할 수 없어 재실행 후에는 유지되지 않아요.':'';
  };
}
function thresholdRow(field,title){return `<div class="threshold-row"><span class="row-title">${title}</span><button data-field="${field}" data-step="-0.1" aria-label="${title} 낮추기">${icon('minus')}</button><output id="threshold-${field}" aria-label="${title}">${fmt(draft[field])}°</output><button data-field="${field}" data-step="0.1" aria-label="${title} 높이기">${icon('plus')}</button></div>`;}
function setTab(value){
  homeMonitor?.destroy();homeMonitor=null;tab=value;
  $$('[data-tab]').forEach(button=>{if(button.dataset.tab===tab)button.setAttribute('aria-current','page');else button.removeAttribute('aria-current');});
  if(tab==='home')renderHome();if(tab==='events')renderEvents();if(tab==='settings')renderSettings();
  window.scrollTo({top:0,behavior:'instant'});
}
$$('[data-tab]').forEach(button=>button.onclick=()=>setTab(button.dataset.tab));

function sheetHeader(title){return `<header class="sheet-header"><h2 id="sheet-title">${title}</h2><button class="close-text" id="close-sheet" autofocus>닫기</button></header><div id="sheet-body" class="sheet-body"></div>`;}
function openSheet(kind,id=null){
  if(sheet.open){sheetStack.push({kind:sheetKind,eventId});}else{sheetStack=[];lastFocused=document.activeElement;}
  expandedMonitor?.destroy();expandedMonitor=null;sheetKind=kind;eventId=id;
  sheet.innerHTML=sheetHeader(({expanded:'온도 모니터링',history:'온도 기록',event:'알림 상세',info:'측정 방식'})[kind]);
  $('#close-sheet').onclick=closeSheet;
  if(kind==='expanded')renderExpanded();if(kind==='history')renderHistory();if(kind==='event')renderEventDetail();if(kind==='info')renderInfo();
  if(!sheet.open)sheet.showModal();
  $('#close-sheet').focus({preventScroll:true});sheet.scrollTop=0;
}
function closeSheet(){
  expandedMonitor?.destroy();expandedMonitor=null;
  if(sheetStack.length){const previous=sheetStack.pop();sheetKind=null;sheet.close();const saved=sheetStack.slice();openSheet(previous.kind,previous.eventId);sheetStack=saved;return;}
  sheetKind=null;sheet.close();if(lastFocused?.isConnected)lastFocused.focus({preventScroll:true});
}
sheet.addEventListener('cancel',event=>{event.preventDefault();closeSheet();});
function renderExpanded(){
  $('#sheet-body').innerHTML=`<section class="monitor-detail-card"><div class="thermal-wrap"><div id="thermal-expanded" class="thermal-view"></div></div><div class="tracking-panel"><div class="tracking-summary"><div><p id="tracking-title" class="eyebrow"></p><p class="tracking-number"><span id="tracking-value"></span><span class="unit">°C</span></p></div><div class="tracking-right"><span id="tracking-caption" class="tiny muted">실시간 추이</span><div class="segments compact" aria-label="실시간 기록 기간">${[[15,'15분'],[60,'1시간'],[1440,'24시간']].map(([m,title])=>`<button data-tracking="${m}" class="${tracking.minutes===m?'selected':''}">${title}</button>`).join('')}</div></div></div><div id="live-chart" class="chart" tabindex="0" aria-label="온도 추이. 눌러서 시각별 온도를 확인하세요"></div></div></section><p class="hint" id="monitor-hint"></p>`;
  expandedMonitor=createThermalMonitor($('#thermal-expanded'),{onSelect:setPoint});expandedMonitor.setSample(latest);expandedMonitor.setSelected(selected);
  $$('[data-tracking]',sheet).forEach(button=>button.onclick=()=>{tracking.minutes=Number(button.dataset.tracking);tracking.selection=null;$$('[data-tracking]',sheet).forEach(b=>b.classList.toggle('selected',b===button));renderTracking();});renderTracking();
}
function renderTracking(){
  if(sheetKind!=='expanded')return;
  const end=Date.now(),start=end-tracking.minutes*60000;
  const raw=samples.filter(s=>s.date>=start&&s.date<=end).map(s=>({date:s.date,v:pointTemperature(selected,s)}));
  const chosen=tracking.selection===null?null:nearest(raw,tracking.selection,75000);
  $('#tracking-title').textContent=selected?'선택 지점 온도':'대표 보정 온도';
  $('#tracking-value').textContent=fmt(tracking.selection===null?selectedValue():chosen?.v);
  $('#tracking-caption').textContent=tracking.selection===null?'실시간 추이':chosen?clock(chosen.date):'이 시각의 기록 없음';
  $('#monitor-hint').textContent=selected?'빈 곳을 누르면 기본 추적으로 돌아가요':'아기 위의 격자를 눌러 온도를 확인하세요';
  renderChart($('#live-chart'),raw,{start,end,chosen,onSelect:date=>{tracking.selection=date;renderTracking();}});
}
function interval(){
  const end=nextDay(dayStart(history.anchor));
  return history.period==='day'?{start:dayStart(history.anchor),end}:{start:nextDay(dayStart(history.anchor),-6),end};
}
function historyData(){
  const {start,end}=interval();const records=samples.filter(s=>s.date>=start&&s.date<end);const unit=history.period==='day'?300000:86400000;
  const bins=new Map(),minutes=new Map();
  records.forEach(s=>{const key=history.period==='day'?Math.floor(s.date/unit)*unit:dayStart(s.date);if(!bins.has(key))bins.set(key,[]);bins.get(key).push(s[history.region]);const minute=Math.floor(s.date/60000);if(!minutes.has(minute))minutes.set(minute,[]);minutes.get(minute).push(s[history.region]);});
  const points=[...bins].sort((a,b)=>a[0]-b[0]).map(([date,values])=>({date:history.period==='week'?date+43200000:date+150000,bucket:date,v:average(values),min:Math.min(...values),max:Math.max(...values)}));
  const values=records.map(s=>s[history.region]);
  let chosen=null;if(history.selection!==null){const bucket=history.period==='week'?dayStart(history.selection):Math.floor(history.selection/300000)*300000;chosen=points.find(p=>p.bucket===bucket)||null;}
  return {start,end,records,points,chosen,mean:average([...minutes.values()].map(average)),min:values.length?Math.min(...values):NaN,max:values.length?Math.max(...values):NaN};
}
function renderHistory(){
  $('#sheet-body').innerHTML=`<div class="history-controls"><select id="history-region" class="region-select" aria-label="관찰 영역"><option value="torso">몸통 영역</option><option value="head">머리 영역</option></select><div class="segments" aria-label="기록 기간"><button data-period="day">하루</button><button data-period="week">일주일</button></div></div><section class="history-card"><div class="date-navigation"><button id="previous-period" aria-label="이전 기간">${icon('back')}</button><p id="date-range" class="date-range"></p><button id="next-period" aria-label="다음 기간">${icon('chevron')}</button></div><div class="history-summary"><div class="summary-top"><div><p id="history-summary-title" class="eyebrow">평균</p><p class="big-value"><span id="history-value"></span><span class="unit">°C</span></p></div><button id="clear-history-selection" class="clear-selection" hidden>선택 해제</button></div><p id="history-caption" class="history-caption"></p></div><div id="history-chart" class="chart" tabindex="0" aria-label="기간별 온도 기록 그래프"></div><dl class="history-statistics"><div><dt>최저</dt><dd><b id="history-min"></b> <span>°C</span></dd></div><div><dt>최고</dt><dd><b id="history-max"></b> <span>°C</span></dd></div></dl></section><details class="disclosure"><summary id="history-event-count">알림</summary><div id="history-events" class="event-list"></div></details><details class="disclosure"><summary>최근 측정값</summary><dl id="history-readings" class="readings-list"></dl></details>`;
  $('#history-region').value=history.region;$('#history-region').onchange=event=>{history.region=event.target.value;history.selection=null;updateHistory();};
  $$('[data-period]',sheet).forEach(button=>button.onclick=()=>{history.period=button.dataset.period;history.selection=null;history.anchor=Date.now();updateHistory();});
  $('#previous-period').onclick=()=>{history.anchor=nextDay(history.anchor,history.period==='week'?-7:-1);history.selection=null;updateHistory();};
  $('#next-period').onclick=()=>{history.anchor=nextDay(history.anchor,history.period==='week'?7:1);history.selection=null;updateHistory();};
  $('#clear-history-selection').onclick=()=>{history.selection=null;updateHistory();};updateHistory();
}
function updateHistory(){
  if(sheetKind!=='history')return;
  const data=historyData();const choosing=history.selection!==null;
  $$('[data-period]',sheet).forEach(b=>b.classList.toggle('selected',b.dataset.period===history.period));
  $('#date-range').textContent=history.period==='day'?dateLabel(data.start):`${dateLabel(data.start)} – ${dateLabel(data.end-1)}`;
  $('#previous-period').disabled=data.start<=samples[0].date;
  $('#next-period').disabled=data.end>Date.now();
  $('#history-summary-title').textContent=choosing?(data.chosen?(history.period==='week'?'선택일 평균':'선택 구간 평균'):'이 시각의 기록 없음'):'평균';
  $('#history-value').textContent=fmt(choosing?data.chosen?.v:data.mean);
  $('#history-caption').textContent=choosing?(history.period==='week'?dateLabel(history.selection):`${shortClock(history.selection)} · 5분 구간`):(history.period==='week'?'날짜별 온도 범위와 평균':'5분 구간별 온도 흐름');
  $('#clear-history-selection').hidden=!choosing;$('#history-min').textContent=fmt(data.min);$('#history-max').textContent=fmt(data.max);
  renderChart($('#history-chart'),data.points,{start:data.start,end:data.end,chosen:data.chosen,week:history.period==='week',history:true,onSelect:date=>{history.selection=date;updateHistory();}});
  const relevant=events.filter(e=>e.date>=data.start&&e.date<data.end).sort((a,b)=>b.date-a.date);
  $('#history-event-count').textContent=`알림 ${relevant.length}건`;
  $('#history-events').innerHTML=relevant.length?relevant.map(eventCard).join(''):'<p class="small muted">이 기간에는 알림이 없어요.</p>';bindEvents($('#history-events'));
  $('#history-readings').innerHTML=data.records.slice(-8).reverse().map(s=>`<div class="definition-row"><dt>${clock(s.date)}</dt><dd>${fmt(s[history.region])} °C</dd></div>`).join('')||'<p class="small muted">이 기간에는 측정값이 없어요.</p>';
}
function renderEventDetail(){
  const event=events.find(e=>e.id===eventId);if(!event)return;
  $('#sheet-body').innerHTML=`<div class="event-detail-icon">${icon(event.kind==='connection'?'wifi':'thermometer')}</div><h3 class="event-detail-title">${eventTitle(event)}</h3><p class="event-detail-description">${eventDescription(event)}</p><section class="section-card"><dl id="event-facts"></dl></section><h3 class="chart-heading">당시 온도 변화</h3><div id="event-chart" class="chart" aria-label="알림 당시 온도 그래프"></div>`;updateEventDetail();
}
function updateEventDetail(){
  if(sheetKind!=='event')return;const event=events.find(e=>e.id===eventId);if(!event)return;
  const facts=[['발생',fullDate(event.date)],['확인',event.ack?clock(event.ack):'아직 확인하지 않음'],['종료',event.resolved?clock(event.resolved):'상태 확인 중'],...(event.reference?[['상승 기준',`${fmt(event.reference)} °C`]]:[]),['당시 기준',`${fmt(event.low)} – ${fmt(event.high)} °C`]];
  $('#event-facts').innerHTML=facts.map(([key,value])=>`<div class="definition-row"><dt>${key}</dt><dd>${value}</dd></div>`).join('');
  const start=event.date-300000,end=event.date+300000,points=samples.filter(s=>s.date>=start&&s.date<=end).map(s=>({date:s.date,v:Math.max(s.head,s.torso)}));renderChart($('#event-chart'),points,{start,end});
}
function renderInfo(){
  $('#sheet-body').innerHTML=`<section class="section-card info-copy"><h3>패드 위에서 살피는 온도</h3><p>아기가 누운 패드의 접촉 영역을 따라 온도를 살펴봅니다. 화면의 색과 격자는 관찰 중인 영역의 온도 분포를 보여줍니다.</p><h3>머리와 몸통 영역</h3><p>기본 화면은 머리와 몸통을 함께 보여줍니다. 아기의 자세에 따라 패드와 닿는 부위는 달라질 수 있어요. 다른 지점을 누르면 그 지점의 온도를 확인할 수 있습니다.</p><h3>작은 변화부터 확인해요</h3><p>설정 범위 이탈이나 빠른 상승이 감지되면 알려드려요. 알림을 받으면 아기의 상태를 확인해 주세요.</p></section>`;
}
function updateSheetData(){if(sheetKind==='expanded')renderTracking();if(sheetKind==='history')updateHistory();if(sheetKind==='event')updateEventDetail();}

function nearest(points,date,tolerance=Infinity){if(!points.length)return null;const point=points.reduce((a,b)=>Math.abs(a.date-date)<Math.abs(b.date-date)?a:b);return Math.abs(point.date-date)<=tolerance?point:null;}
function renderChart(element,points,options){
  if(!element)return;
  if(!points.length){element.innerHTML='<div class="empty-state">이 기간에는 온도 기록이 없어요</div>';element.onpointerdown=null;return;}
  const {start,end,chosen,week=false,onSelect}=options;
  const width=360,height=184,left=8,right=40,top=8,bottom=28,pw=width-left-right,ph=height-top-bottom;
  const low=Math.min(36,Math.floor((Math.min(...points.map(p=>p.min??p.v))-.15)*2)/2),high=Math.max(38.5,Math.ceil((Math.max(...points.map(p=>p.max??p.v))+.15)*2)/2);
  const x=date=>left+(date-start)/(end-start)*pw,y=v=>top+(high-v)/(high-low)*ph;
  let svg='';
  for(let i=0;i<4;i++){const value=low+(high-low)*i/3;const yy=y(value);svg+=`<line class="chart-axis" x1="${left}" y1="${yy}" x2="${width-right}" y2="${yy}"/><text class="chart-label" x="${width-right+8}" y="${yy+3}">${fmt(value)}</text>`;}
  if(week){
    for(let i=0;i<7;i++){const date=nextDay(start,i)+43200000;svg+=`<text class="chart-label" text-anchor="middle" x="${x(date)}" y="${height-4}">${new Date(date).toLocaleDateString('ko-KR',{weekday:'narrow'})}</text>`;}
    points.forEach(p=>{const yy=y(p.max),yy2=y(p.min);svg+=`<line x1="${x(p.date)}" y1="${yy}" x2="${x(p.date)}" y2="${yy2}" stroke="#a60031" stroke-opacity=".4" stroke-width="10" stroke-linecap="round"/><circle cx="${x(p.date)}" cy="${y(p.v)}" r="2.8" fill="#a60031"/>`;});
  }else{
    for(let i=0;i<4;i++){const date=start+(end-start)*i/3;svg+=`<text class="chart-label" text-anchor="${i===0?'start':i===3?'end':'middle'}" x="${x(date)}" y="${height-4}">${shortClock(date)}</text>`;}
    let groups=[],current=[];
    points.forEach(p=>{const previous=current.at(-1);if(previous&&p.date-previous.date>(options.history?600000:75000)){groups.push(current);current=[];}current.push(p);});if(current.length)groups.push(current);
    groups.forEach(group=>{
      const line=group.map((p,i)=>`${i?'L':'M'}${x(p.date).toFixed(2)},${y(p.v).toFixed(2)}`).join(' ');
      if(group.length>1){const area=`${line} L${x(group.at(-1).date)},${y(low)} L${x(group[0].date)},${y(low)}Z`;svg+=`<path class="chart-area" d="${area}"/><path class="chart-path" d="${line}"/>`;}else{svg+=`<circle cx="${x(group[0].date)}" cy="${y(group[0].v)}" r="2" fill="#a60031"/>`;}
      if(options.history&&group.length>1){const range=group.map((p,i)=>`${i?'L':'M'}${x(p.date)},${y(p.max)}`).join(' ')+group.slice().reverse().map(p=>`L${x(p.date)},${y(p.min)}`).join(' ')+'Z';svg+=`<path d="${range}" fill="#a6003112"/>`;}
    });
  }
  if(chosen)svg+=`<line x1="${x(chosen.date)}" y1="${top}" x2="${x(chosen.date)}" y2="${height-bottom}" stroke="#a60031" stroke-opacity=".25"/><circle cx="${x(chosen.date)}" cy="${y(chosen.v)}" r="4" fill="#a60031" stroke="white" stroke-width="2"/>`;
  element.innerHTML=`<svg viewBox="0 0 ${width} ${height}" aria-hidden="true">${svg}</svg>`;
  if(onSelect){
    const choose=event=>{const bounds=element.getBoundingClientRect();const xx=(event.clientX-bounds.left)/bounds.width*width;const date=start+Math.max(0,Math.min(1,(xx-left)/pw))*(end-start);onSelect(date);};
    element.onpointerdown=event=>{if(event.button===0){element.setPointerCapture?.(event.pointerId);choose(event);}};
    element.onpointermove=event=>{if(event.buttons===1)choose(event);};
    element.onkeydown=event=>{if(event.key==='ArrowLeft'||event.key==='ArrowRight'){event.preventDefault();const index=chosen?points.indexOf(chosen):(event.key==='ArrowLeft'?points.length: -1);const next=Math.max(0,Math.min(points.length-1,index+(event.key==='ArrowLeft'?-1:1)));onSelect(points[next].date);}};
  }
}
function presentNext(){
  if(popup||alertDialog.open)return;
  while(queued.length){const id=queued.shift();const event=events.find(e=>e.id===id);if(event&&!shown.has(id)){popup=event;shown.add(id);break;}}
  if(!popup)return;
  alertDialog.innerHTML=`<div class="alert-content"><span class="alert-emblem">${icon('thermometer')}</span><h2 id="alert-title">${eventTitle(popup)}</h2><p id="alert-description">${eventDescription(popup)}</p><time>${clock(popup.date)}</time><button class="primary-button" id="acknowledge-alert" autofocus>확인</button><button class="secondary-button" id="view-alert-record">기록 보기</button></div>`;
  $('#acknowledge-alert').onclick=()=>acknowledge(false);$('#view-alert-record').onclick=()=>acknowledge(true);alertDialog.showModal();
}
function acknowledge(detail){
  if(!popup)return;const event=popup;event.ack=Date.now();popup=null;alertDialog.close();
  if(detail)openSheet('event',event.id);if(tab==='events')renderEvents();updateSheetData();setTimeout(presentNext,200);
}
alertDialog.addEventListener('cancel',event=>{event.preventDefault();acknowledge(false);});
seedHistory();receive(inputAt(0));lastIndex=0;setTab('home');tick();
setInterval(tick,250);
document.addEventListener('visibilitychange',()=>{if(!document.hidden)tick();});
