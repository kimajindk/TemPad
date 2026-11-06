import { createThermalMonitor, pointTemperature } from './thermal.js';
import { renderChart, renderMiniChart } from './chart.js';
import { severityForEvent, statusLegendHTML } from './status.js';

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
const fmt = value => Number.isFinite(value) ? value.toFixed(1) : '--.-';
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
let startedAt = Date.now();
let mode = 'steady';
let tab = 'home';
let selected = null;
let latest = {date:startedAt,head:36.6,torso:36.8,contact:true};
let lastIndex = -1;
let popup = null;
let activeEvent = null;
let shown = new Set();
let queued = [];
let events = [];
let samples = [];
let liveSamples = [];
let homeMonitor = null;
let sheetKind = null;
let sheetStack = [];
let eventId = null;
let history = {period:'day',region:'torso',anchor:startedAt,selection:null};
let tracking = {period:'60',selection:null};
let storageIssue = false;
let lastFocused = null;
const main = $('#main'), sheet = $('#sheet'), alertDialog = $('#alert');
const validSample = sample => sample?.contact !== false && Number.isFinite(sample?.head) && Number.isFinite(sample?.torso);

function inputAt(seconds) {
  let torso;
  if(mode === 'steady') torso = 36.8 + .08*Math.sin(seconds/37);
  else if(seconds < 10) torso = 36.8;
  else if(seconds < 30) torso = 36.8 + .6 * (seconds-10)/20;
  else if(seconds < 60) torso = 37.4 + (seconds-30)/30;
  else if(seconds < 90) torso = 38.4 + .2*(seconds-60)/30;
  else torso = 38.5 + .1*Math.cos((seconds-90)/35);
  return {date:startedAt+seconds*1000,head:Math.round((torso-.2+1e-9)*10)/10,torso:Math.round((torso+1e-9)*10)/10,contact:true};
}
function seedHistory() {
  samples = [];
  events = [];
  for(let offset=-7*86400;offset<0;offset+=60) {
    const torso=36.8+.08*Math.sin(offset/1800)+.06*Math.sin(Math.floor(offset/86400)*1.3);
    samples.push({date:startedAt+offset*1000,head:torso-.2,torso,contact:true});
  }
  const seeds = mode==='fever'?[['rise',-24*60,37.3,36.8],['high',-2*3600,38.2,36.8],['connection',-5*3600,null,null],['rise',-19*3600,37.4,36.9]]:[];
  seeds.forEach(([kind,offset,value,reference])=>{
    const date = startedAt+offset*1000;
    const event = {id:`past-${kind}-${date}`,kind,date,value,reference,low:36,high:38,ack:date+24000,resolved:date+(kind==='connection'?120000:600000)};
    events.push(event);shown.add(event.id);
    if(value===null)return;
    samples = samples.filter(s=>Math.abs(s.date-date)>600000);
    for(let second=-600;second<=600;second+=5){
      const baseline=reference;
      const temperature=second < -120 ? baseline : second < 0 ? baseline+(value-baseline)*(second+120)/120 : value+(36.8-value)*second/600;
      samples.push({date:date+second*1000,head:temperature-.2,torso:temperature,contact:true});
    }
  });
  const notices=[{kind:'info',offset:-4*3600,value:null}];
  if(mode==='fever')notices.push({kind:'recovery',offset:-2*3600+600,value:36.8});
  notices.forEach(({kind,offset,value})=>{
    const date=startedAt+offset*1000;
    const event={id:`past-${kind}-${date}`,kind,date,value,reference:null,low:36,high:38,ack:date+24000,resolved:date};
    events.push(event);shown.add(event.id);
  });
  samples.sort((a,b)=>a.date-b.date);
  const away=[[-21*3600,-20*3600-15*60],[-15*3600-30*60,-15*3600],[-9*3600,-8*3600-20*60],[-4*3600,-3*3600-20*60],[-12*60,-7*60]];
  samples=samples.map(sample=>{
    const offset=(sample.date-startedAt)/1000;
    const dayOffset=((offset%86400)+86400)%86400-86400;
    if(away.some(([start,end])=>dayOffset>=start&&dayOffset<end))return {...sample,head:null,torso:null,contact:false};
    if(mode==='fever'&&offset>=-5*3600&&offset<-5*3600+120)return {...sample,head:null,torso:null,contact:true};
    return sample;
  });
}
function eventTitle(event) {return event.kind==='rise'?'온도 변화를 확인해 주세요':event.kind==='connection'?'온도 정보를 받지 못했어요':event.kind==='recovery'?'설정 범위로 돌아왔어요':event.kind==='info'?'측정을 잠시 멈췄어요':'온도를 확인해 주세요';}
function eventLabel(event) {return ({rise:'빠른 온도 상승',high:'상한 초과',low:'하한 미만',connection:'연결 확인',recovery:'설정 범위 복귀',info:'측정 일시 중지'})[event.kind];}
function eventDescription(event) {
  if(event.kind==='rise')return `최근 ${fmt(event.reference)} °C에서 ${fmt(event.value)} °C로 올라갔어요. 아기의 상태를 확인해 주세요.`;
  if(event.kind==='high')return `${fmt(event.value)} °C가 감지되어 설정 상한 ${fmt(event.high)} °C를 넘었어요.`;
  if(event.kind==='low')return `${fmt(event.value)} °C가 감지되어 설정 하한 ${fmt(event.low)} °C보다 낮아요.`;
  if(event.kind==='recovery')return `${fmt(event.value)} °C로 설정 범위 안에 돌아왔어요. 온도 흐름을 계속 살펴볼게요.`;
  if(event.kind==='info')return '패드와의 접촉이 없어 측정을 잠시 멈췄어요.';
  return '새로운 온도 정보가 도착하지 않았어요. 패드 연결을 확인해 주세요.';
}
function receive(sample) {
  if(!validSample(sample)){
    latest=sample;samples.push(sample);liveSamples=[];
    if(activeEvent){activeEvent.resolved=sample.date;activeEvent.endReason='측정 중단';activeEvent=null;}
    if(popup){popup=null;if(alertDialog.open)alertDialog.close();}
    queued=[];return;
  }
  const value=Math.max(sample.head,sample.torso);
  const baseline=Math.min(...liveSamples.filter(s=>validSample(s)&&sample.date-s.date<=300000).map(s=>Math.max(s.head,s.torso)));
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
  $('#alert-dot').hidden=!events.some(e=>!e.ack&&!e.resolved);
  presentNext();
}
function setPoint(point){selected=point;homeMonitor?.setSelected(point);tracking.selection=null;history.selection=null;updateReadings();renderInlineChart();}
function selectedValue(sample=latest){return validSample(sample)?pointTemperature(selected,sample):null;}
function chartValue(sample){return validSample(sample)?(selected?pointTemperature(selected,sample):sample[history.region]):null;}
function renderHome(){
  main.innerHTML=`<div class="page-heading monitor-heading"><h1>모니터링</h1></div>
    <section class="monitor-card" aria-label="아기 온도 모니터링">
      <div class="thermal-wrap"><div id="thermal-home" class="thermal-view"></div><span class="live-indicator"><i aria-hidden="true"></i>실시간</span></div>
      <div class="reading-card"><div class="big-value"><span id="current-temperature"></span><span class="unit">°C</span></div><div class="mini-trend"><span class="mini-trend-label">최근 15분</span><div id="mini-chart" class="mini-chart" aria-label="최근 15분 온도 흐름"></div></div></div>
      <section class="inline-tracking" aria-label="온도 흐름"><div class="inline-chart-heading"><h2>온도 흐름</h2><select id="inline-region" class="region-select" aria-label="관찰 영역"><option value="torso">몸통 영역</option><option value="head">머리 영역</option><option value="point" hidden>선택 지점</option></select></div><div class="segments inline-periods" aria-label="기록 기간">${[['60','1시간'],['720','12시간'],['day','하루'],['week','일주일']].map(([period,title])=>`<button data-inline-period="${period}" aria-pressed="${tracking.period===period}" class="${tracking.period===period?'selected':''}">${title}</button>`).join('')}</div>
      <div class="date-navigation inline-date-navigation" id="inline-date-navigation" hidden><button id="previous-period" aria-label="이전 기간">${icon('back')}</button><p id="date-range" class="date-range"></p><button id="next-period" aria-label="다음 기간">${icon('chevron')}</button></div>
      <div id="inline-summary" class="inline-summary"><div><p id="inline-summary-title" class="eyebrow"></p><p class="inline-summary-value"><span id="inline-summary-value"></span><span class="unit">°C</span></p></div><button id="clear-inline-selection" class="clear-selection" hidden>선택 해제</button></div><div id="inline-chart" class="chart" tabindex="0" aria-label="온도 기록 그래프"></div><p id="inline-caption" class="inline-caption"></p></section>
    </section>`;
  homeMonitor=createThermalMonitor($('#thermal-home'),{onSelect:setPoint});homeMonitor.setSample(latest);homeMonitor.setSelected(selected);
  $('#inline-region').onchange=event=>{history.region=event.target.value;history.selection=null;tracking.selection=null;updateReadings();renderInlineChart();};
  $$('[data-inline-period]',main).forEach(button=>button.onclick=()=>{tracking.period=button.dataset.inlinePeriod;tracking.selection=null;history.selection=null;history.anchor=Date.now();if(['day','week'].includes(tracking.period))history.period=tracking.period;renderInlineChart();});
  $('#previous-period').onclick=()=>{history.anchor=nextDay(history.anchor,history.period==='week'?-7:-1);history.selection=null;renderInlineChart();};
  $('#next-period').onclick=()=>{history.anchor=nextDay(history.anchor,history.period==='week'?7:1);history.selection=null;renderInlineChart();};
  $('#clear-inline-selection').onclick=()=>{history.selection=null;tracking.selection=null;renderInlineChart();};
  updateReadings();renderInlineChart();
}
function updateReadings(){
  homeMonitor?.setSample(latest);
  if(tab!=='home')return;
  $('#current-temperature').textContent=fmt(selectedValue());
  $('#current-temperature').parentElement.setAttribute('aria-label',`${selected?'선택 지점':'현재 온도'} ${fmt(selectedValue())}도`);
  renderRecentTrend();
}
function renderRecentTrend(){
  const element=$('#mini-chart');if(tab!=='home'||!element)return;
  const end=Date.now(),start=end-15*60000;
  const points=segmentedSamples(samples.filter(sample=>sample.date>=start&&sample.date<=end)).map(sample=>({...sample,v:selectedValue(sample)}));
  element.setAttribute('aria-label',`최근 15분 ${selected?'선택 지점':'대표 온도'} 흐름`);
  renderMiniChart(element,points,{start,end});
}
function eventCard(event){const status=severityForEvent(event);return `<button class="event-card" data-event="${event.id}" style="--status-color:${status.color};--status-soft:${status.soft}"><span class="event-glyph">${icon(event.kind==='connection'?'wifi':'thermometer')}</span><span class="event-copy"><span class="event-heading"><h3>${eventLabel(event)}</h3><span class="status-label">${status.label}</span></span><p>${eventDescription(event)}</p><time>${fullDate(event.date)}</time></span><span class="event-status${!event.resolved?' active':''}">${event.resolved?'종료':event.ack?'확인함':'확인 필요'}</span></button>`;}
function bindEvents(root=document){$$('[data-event]',root).forEach(el=>el.onclick=()=>openSheet('event',el.dataset.event));}
function renderEvents(){
  main.innerHTML=`<div class="page-heading"><h1>알림 기록</h1></div><p class="page-subtitle">최근 알림을 확인하세요</p>${events.length?`<p class="count-label">최근 7일 · ${events.length}건</p><div class="event-list">${events.slice().sort((a,b)=>b.date-a.date).map(eventCard).join('')}</div>`:`<section class="empty-events"><span class="event-glyph">${icon('bell')}</span><h2>새로운 알림이 없어요</h2><p>온도 변화가 감지되면<br>이곳에서 확인할 수 있어요.</p></section>`}`;bindEvents(main);
}
function renderSettings(){
  draft={...settings};
  main.innerHTML=`<div class="page-heading"><h1>설정</h1></div><p class="page-subtitle">알림과 모니터링 환경</p>
    <section class="section-card"><h2>${icon('thermometer')}온도 알림</h2><p class="small muted">설정 범위를 벗어나면 바로 알려드려요.</p><p class="settings-note">최근 5분 내 0.5°C 이상 상승해도 알려드려요.</p>${thresholdRow('high','상한 온도')}${thresholdRow('low','하한 온도')}<button class="primary-button" id="save-settings">변경사항 저장</button><p id="settings-error" class="warning-copy" role="status"></p></section>
    <section class="section-card"><h2>${icon('bell')}화면 알림</h2><p class="small muted">온도 변화가 감지되면 화면 위에서 내려오는 알림으로 알려드려요.</p>${statusLegendHTML()}<div class="rule"></div><dl><div class="definition-row"><dt>온도 단위</dt><dd>섭씨 °C</dd></div><div class="definition-row"><dt>측정 간격</dt><dd>5초</dd></div></dl></section>
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
function switchMode(value){
  if(!['steady','fever'].includes(value))return;
  if(alertDialog.open)alertDialog.close();if(sheet.open)sheet.close();
  sheetKind=null;sheetStack=[];eventId=null;
  popup=null;activeEvent=null;queued=[];shown=new Set();liveSamples=[];selected=null;
  mode=value;startedAt=Date.now();lastIndex=0;
  history={period:'day',region:'torso',anchor:startedAt,selection:null};tracking={period:'60',selection:null};
  seedHistory();receive(inputAt(0));
  $$('[data-mode]').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.mode===mode)));
  setTab('home');tick();
}
$$('[data-mode]').forEach(button=>button.onclick=()=>switchMode(button.dataset.mode));

function sheetHeader(title){return `<header class="sheet-header"><h2 id="sheet-title">${title}</h2><button class="close-text" id="close-sheet" autofocus>닫기</button></header><div id="sheet-body" class="sheet-body"></div>`;}
function openSheet(kind,id=null){
  if(sheet.open){sheetStack.push({kind:sheetKind,eventId});}else{sheetStack=[];lastFocused=document.activeElement;}
  sheetKind=kind;eventId=id;
  sheet.innerHTML=sheetHeader(({event:'알림 상세',info:'측정 방식'})[kind]);
  $('#close-sheet').onclick=closeSheet;
  if(kind==='event')renderEventDetail();if(kind==='info')renderInfo();
  if(!sheet.open)sheet.showModal();
  $('#close-sheet').focus({preventScroll:true});sheet.scrollTop=0;
}
function closeSheet(){
  if(sheetStack.length){const previous=sheetStack.pop();sheetKind=null;sheet.close();const saved=sheetStack.slice();openSheet(previous.kind,previous.eventId);sheetStack=saved;return;}
  sheetKind=null;sheet.close();if(lastFocused?.isConnected)lastFocused.focus({preventScroll:true});
}
sheet.addEventListener('cancel',event=>{event.preventDefault();closeSheet();});
function renderInlineChart(){
  if(tab!=='home'||!$('#inline-chart'))return;
  const historical=['day','week'].includes(tracking.period);
  const region=$('#inline-region');region.disabled=!!selected;region.querySelector('[value="point"]').hidden=!selected;region.value=selected?'point':history.region;
  $$('[data-inline-period]',main).forEach(button=>{const current=button.dataset.inlinePeriod===tracking.period;button.classList.toggle('selected',current);button.setAttribute('aria-pressed',String(current));});
  $('#inline-date-navigation').hidden=!historical;
  let points,start,end,chosen,selection,summaryTitle,value,caption;
  if(historical){
    history.period=tracking.period;
    const data=historyData();({points,start,end,chosen}=data);selection=history.selection;
    $('#date-range').textContent=history.period==='day'?dateLabel(start):`${dateLabel(start)} – ${dateLabel(end-1)}`;
    $('#previous-period').disabled=start<=samples[0].date;$('#next-period').disabled=end>Date.now();
    summaryTitle=selection===null?'평균':chosen?(history.period==='week'?'선택일 평균':'선택 구간 평균'):'측정 없음';
    value=selection===null?data.mean:chosen?.v;
    caption=selection!==null?(history.period==='week'?`${dateLabel(selection)} · ${chosen?'일 평균':'측정 없음'}`:`${shortClock(selection)} · ${chosen?'5분 구간':'측정 없음'}`):(history.period==='week'?'날짜별 평균 온도':'5분 구간별 온도 · 미측정 구간은 선이 끊겨요');
  }else{
    end=Date.now();start=end-Number(tracking.period)*60000;
    points=segmentedSamples(samples.filter(s=>s.date>=start&&s.date<=end)).map(s=>({...s,v:chartValue(s)}));
    selection=tracking.selection;chosen=selection===null?null:readingAt(points,selection);
    summaryTitle=chosen?'선택 시각 온도':'측정 없음';value=chosen?.v;
    caption=selection!==null?`${shortClock(selection)} · ${chosen?'선택한 시각':'측정 없음'}`:validSample(latest)?'5초마다 갱신 · 미측정 구간은 선이 끊겨요':latest.contact===false?'패드에 아기가 없어요':'측정 대기';
  }
  $('#inline-summary').hidden=!historical&&selection===null;
  $('#inline-summary-title').textContent=summaryTitle;$('#inline-summary-value').textContent=fmt(value);
  $('#clear-inline-selection').hidden=selection===null;$('#inline-caption').textContent=caption;
  renderChart($('#inline-chart'),points,{start,end,chosen,week:tracking.period==='week',history:historical,low:settings.low,high:settings.high,onSelect:date=>{if(historical)history.selection=date;else tracking.selection=date;renderInlineChart();}});
}
function interval(){
  const end=nextDay(dayStart(history.anchor));
  return history.period==='day'?{start:dayStart(history.anchor),end}:{start:nextDay(dayStart(history.anchor),-6),end};
}
function historyData(){
  const {start,end}=interval();const records=segmentedSamples(samples.filter(s=>s.date>=start&&s.date<end));
  const bins=new Map(),minutes=new Map();
  records.filter(validSample).forEach(s=>{
    const bucket=history.period==='day'?Math.floor(s.date/300000)*300000:dayStart(s.date);
    const key=history.period==='day'?`${s.segment}:${bucket}`:String(bucket);
    if(!bins.has(key))bins.set(key,{bucket,segment:s.segment,readings:[]});bins.get(key).readings.push(s);
    const minute=Math.floor(s.date/60000);if(!minutes.has(minute))minutes.set(minute,[]);minutes.get(minute).push(chartValue(s));
  });
  const points=[...bins.values()].map(({bucket,segment,readings})=>{
    const values=readings.map(s=>chartValue(s));
    const minuteBins=new Map();readings.forEach(s=>{const minute=Math.floor(s.date/60000);if(!minuteBins.has(minute))minuteBins.set(minute,[]);minuteBins.get(minute).push(chartValue(s));});
    return {date:history.period==='week'?bucket+43200000:average(readings.map(s=>s.date)),bucket,segment:history.period==='week'?0:segment,v:average([...minuteBins.values()].map(average)),min:Math.min(...values),max:Math.max(...values)};
  }).sort((a,b)=>a.date-b.date);
  const values=records.filter(validSample).map(s=>chartValue(s));
  let chosen=null;
  if(history.selection!==null){
    const bucket=history.period==='week'?dayStart(history.selection):Math.floor(history.selection/300000)*300000;
    const reading=history.period==='day'?readingAt(records,history.selection):null;
    chosen=points.find(p=>p.bucket===bucket&&(history.period==='week'||(reading&&p.segment===reading.segment)))||null;
  }
  return {start,end,records,points,chosen,mean:average([...minutes.values()].map(average)),min:values.length?Math.min(...values):NaN,max:values.length?Math.max(...values):NaN};
}
function renderEventDetail(){
  const event=events.find(e=>e.id===eventId);if(!event)return;
  const status=severityForEvent(event);
  $('#sheet-body').style.setProperty('--status-color',status.color);$('#sheet-body').style.setProperty('--status-soft',status.soft);
  $('#sheet-body').innerHTML=`<div class="event-detail-heading"><div class="event-detail-icon">${icon(event.kind==='connection'?'wifi':'thermometer')}</div><span class="status-label">${status.label}</span></div><h3 class="event-detail-title">${eventTitle(event)}</h3><p class="event-detail-description">${eventDescription(event)}</p><section class="section-card"><dl id="event-facts"></dl></section><h3 class="chart-heading">당시 온도 변화</h3><div id="event-chart" class="chart" aria-label="알림 당시 온도 그래프"></div>`;updateEventDetail();
}
function updateEventDetail(){
  if(sheetKind!=='event')return;const event=events.find(e=>e.id===eventId);if(!event)return;
  const facts=[['발생',fullDate(event.date)],['확인',event.ack?clock(event.ack):'아직 확인하지 않음'],['종료',event.resolved?clock(event.resolved):'상태 확인 중'],...(event.endReason?[['종료 사유',event.endReason]]:[]),...(event.reference?[['상승 기준',`${fmt(event.reference)} °C`]]:[]),['당시 기준',`${fmt(event.low)} – ${fmt(event.high)} °C`]];
  $('#event-facts').innerHTML=facts.map(([key,value])=>`<div class="definition-row"><dt>${key}</dt><dd>${value}</dd></div>`).join('');
  const start=event.date-300000,end=event.date+300000,points=segmentedSamples(samples.filter(s=>s.date>=start&&s.date<=end)).map(s=>({...s,v:validSample(s)?Math.max(s.head,s.torso):null}));renderChart($('#event-chart'),points,{start,end,low:event.low,high:event.high});
}
function renderInfo(){
  $('#sheet-body').innerHTML=`<section class="section-card info-copy"><h3>패드 위에서 살피는 온도</h3><p>아기가 누운 패드의 접촉 영역을 따라 온도를 살펴봅니다. 화면의 색과 격자는 관찰 중인 영역의 온도 분포를 보여줍니다.</p><h3>머리와 몸통 영역</h3><p>기본 화면은 머리와 몸통을 함께 보여줍니다. 아기의 자세에 따라 패드와 닿는 부위는 달라질 수 있어요. 다른 지점을 누르면 그 지점의 온도를 확인할 수 있습니다.</p><h3>작은 변화부터 확인해요</h3><p>설정 범위 이탈이나 빠른 상승이 감지되면 알려드려요. 알림을 받으면 아기의 상태를 확인해 주세요.</p></section>`;
}
function updateSheetData(){renderInlineChart();if(sheetKind==='event')updateEventDetail();}

function segmentedSamples(records){
  let segment=0,previous=null;
  return records.map(sample=>{
    if(!validSample(sample)){segment++;previous=null;return {...sample,segment};}
    if(previous&&sample.date-previous.date>75000)segment++;
    previous=sample;return {...sample,segment};
  });
}
function readingAt(records,date){
  if(!records.length)return null;
  // A missing reading starts a gap that lasts until valid contact resumes.
  let before=null,after=null;
  for(const sample of records){if(sample.date<=date)before=sample;else{after=sample;break;}}
  if(before&&!validSample(before))return null;
  if(!before||date-before.date>75000)return null;
  if(after&&!validSample(after))return before;
  const result=after&&after.date-date<date-before.date?after:before;
  return validSample(result)?result:null;
}
function presentNext(){
  if(popup||alertDialog.open)return;
  while(queued.length){const id=queued.shift();const event=events.find(e=>e.id===id);if(event&&!shown.has(id)){popup=event;shown.add(id);break;}}
  if(!popup)return;
  const status=severityForEvent(popup);alertDialog.style.setProperty('--status-color',status.color);alertDialog.style.setProperty('--status-soft',status.soft);
  alertDialog.innerHTML=`<div class="alert-content"><div class="alert-topline"><span class="alert-emblem">${icon('thermometer')}</span><span class="status-label">${status.label}</span><time>${clock(popup.date)}</time></div><h2 id="alert-title">${eventTitle(popup)}</h2><p id="alert-description">${eventDescription(popup)}</p><div class="alert-actions"><button class="primary-button" id="acknowledge-alert" autofocus>확인</button><button class="secondary-button" id="view-alert-record">기록 보기</button></div></div>`;
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
