/* TemPad body projection. The image, grid and markers share one deformation field. */
const COLUMNS = 52, ROWS = 30;
const DEFAULT_POINTS = [{column:11,row:13},{column:22,row:16}];
const POINTS = Array.from({length:COLUMNS*ROWS},(_,i)=>({column:i%COLUMNS,row:Math.floor(i/COLUMNS)}));
const MOTION_START = performance.now();
const clamp = (value, low=0, high=1) => Math.min(high, Math.max(low,value));
const position = point => ({x:(point.column+.5)/COLUMNS,y:(point.row+.5)/ROWS});
const samePoint = (a,b) => a?.column === b?.column && a?.row === b?.row;

export function pointTemperature(point, sample) {
  if (!sample || !Number.isFinite(sample.head) || !Number.isFinite(sample.torso)) return null;
  if (!point) return Math.max(sample.head,sample.torso);
  if (samePoint(point,DEFAULT_POINTS[0])) return sample.head;
  if (samePoint(point,DEFAULT_POINTS[1])) return sample.torso;
  const p=position(point), blend=clamp((p.x-.30)/.10), smooth=blend*blend*(3-2*blend);
  const headHot=Math.exp(-(((p.x-.23)/.14)**2+((p.y-.47)/.23)**2));
  const torsoHot=Math.exp(-(((p.x-.44)/.17)**2+((p.y-.55)/.20)**2));
  const cooling=.35*(1-Math.max(headHot,torsoHot));
  return Math.min(Math.max(sample.head,sample.torso),sample.head*(1-smooth)+sample.torso*smooth-cooling);
}

// This is the same gentle breathing / resting-pose field used by the iPhone app.
export function bodyMotion(point,time,reduced=false) {
  const intensity=reduced?.1:1, aspect=16/9;
  const breath=(1-Math.cos(time*2*Math.PI/4.8))*.5*intensity;
  const elapsed=Math.max(0,time-5), cycle=elapsed%15;
  const gesture=start=>{const p=(cycle-start)/2.8;return p>=0&&p<=1?Math.sin(Math.PI*p)**2:0;};
  const smoothStep=value=>{const t=clamp(value);return t*t*(3-2*t);};
  const arm=gesture(0),head=gesture(5),otherArm=gesture(10),phase=elapsed%24;
  const rest=phase<3?smoothStep(phase/3):phase<12?1:phase<15?1-smoothStep((phase-12)/3):0;
  const chest=Math.exp(-(((point.x-.52)/.19)**2+((point.y-.54)/.22)**2));
  const body=Math.exp(-(((point.x-.51)/.45)**2+((point.y-.53)/.38)**2));
  const out={...point},lean=-.014*rest,dx=point.x-.50,dy=point.y-.54;
  out.x+=(dx*Math.cos(lean)-dy*Math.sin(lean)/aspect-dx)*body*intensity;
  out.y+=(dx*Math.sin(lean)*aspect+dy*Math.cos(lean)-dy)*body*intensity;
  out.x+=.0045*chest*rest*intensity+(point.x-.52)*.012*chest*breath;
  out.y-=.002*chest*rest*intensity;
  out.y+=(point.y-.54)*.05*chest*breath;
  const zones=[
    [.32,.50,.23,.48,.14,.18,head*.105-rest*.025],
    [.40,.43,.37,.28,.10,.13,arm*.27+rest*.03],
    [.40,.65,.45,.78,.11,.10,-otherArm*.243+rest*.025],
    [.61,.51,.77,.36,.14,.14,Math.sin(time*.35)*.006+rest*.016],
    [.61,.63,.77,.70,.15,.09,Math.sin(time*.40)*.006-rest*.012]
  ];
  for(const [px,py,cx,cy,sx,sy,angle] of zones){
    const weight=Math.exp(-(((point.x-cx)/sx)**2+((point.y-cy)/sy)**2))*intensity;
    const x=point.x-px,y=point.y-py;
    out.x+=(x*Math.cos(angle)-y*Math.sin(angle)/aspect-x)*weight;
    out.y+=(x*Math.sin(angle)*aspect+y*Math.cos(angle)-y)*weight;
  }
  return {x:clamp(out.x),y:clamp(out.y)};
}

function installStyles(){
  if(document.getElementById('tempad-thermal-styles'))return;
  const style=document.createElement('style');style.id='tempad-thermal-styles';
  style.textContent=`
  .tp-thermal-root{position:absolute;inset:0;isolation:isolate;overflow:hidden;outline:none;background:radial-gradient(ellipse at 50% 48%,#a9d5e8 0%,#c5e2e9 44%,#e4ebe6 77%,#f6f5ed 100%);touch-action:pan-y;-webkit-tap-highlight-color:transparent;user-select:none}
  .tp-thermal-root:focus-visible{outline:2px solid #a60031;outline-offset:-4px}
  .tp-thermal-root canvas{position:absolute;inset:0;display:block;width:100%;height:100%;pointer-events:none}
  .tp-thermal-label{position:absolute;z-index:2;transform:translate(-50%,-50%);padding:8px;background:rgba(255,255,255,.91);border-radius:8px;color:#30292b;pointer-events:none;white-space:nowrap;line-height:1.25;min-width:64px;box-sizing:border-box}
  .tp-thermal-label[hidden]{display:none}
  .tp-thermal-label-title{display:flex;align-items:center;gap:8px;font-size:10px;font-weight:600;margin-bottom:8px;letter-spacing:-.02em}
  .tp-thermal-led{width:8px;height:8px;border-radius:50%;background:#38b36e;box-shadow:0 0 5px #38b36e55;display:inline-block;flex:none}
  .tp-thermal-led[data-live="false"]{background:#969892;box-shadow:none}
  .tp-thermal-value{font-size:18px;font-weight:500;font-variant-numeric:tabular-nums;letter-spacing:-.025em}
  .tp-thermal-scale{position:absolute;left:16px;top:16px;z-index:2;width:64px;height:4px;border-radius:99px;background:linear-gradient(90deg,#8bdbff,#ffe86a,#ffac3f,#ff5058);pointer-events:none}
  .tp-thermal-sr{position:absolute!important;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0}
  .tp-thermal-error{position:absolute;inset:0;display:grid;place-items:center;padding:24px;text-align:center;font-size:13px;color:#6e6c67}
  `;document.head.append(style);
}

function makeGLRenderer(canvas,image){
  const gl=canvas.getContext('webgl',{alpha:true,antialias:true,premultipliedAlpha:true});
  if(!gl)return null;
  const shader=(type,source)=>{const s=gl.createShader(type);gl.shaderSource(s,source);gl.compileShader(s);if(!gl.getShaderParameter(s,gl.COMPILE_STATUS)){gl.deleteShader(s);throw new Error('Thermal shader unavailable');}return s;};
  const vertex=shader(gl.VERTEX_SHADER,`attribute vec2 a_position;attribute vec2 a_uv;varying vec2 v_uv;void main(){gl_Position=vec4(a_position,0.0,1.0);v_uv=a_uv;}`);
  const fragment=shader(gl.FRAGMENT_SHADER,`precision mediump float;uniform sampler2D u_image;uniform vec2 u_heat;varying vec2 v_uv;void main(){vec4 c=texture2D(u_image,v_uv);float delta=mix(u_heat.x,u_heat.y,smoothstep(.34,.48,v_uv.x));vec3 rgb=c.rgb;rgb.g=clamp(rgb.g-delta*.22,.04,1.0);rgb.b=clamp(rgb.b-delta*.12,.02,1.0);if(delta<-.8)rgb=mix(rgb,vec3(.35,.78,1.0),min(.85,-delta*.35));gl_FragColor=vec4(rgb*c.a,c.a);}`);
  const program=gl.createProgram();gl.attachShader(program,vertex);gl.attachShader(program,fragment);gl.linkProgram(program);
  if(!gl.getProgramParameter(program,gl.LINK_STATUS))throw new Error('Thermal shader unavailable');
  gl.useProgram(program);gl.deleteShader(vertex);gl.deleteShader(fragment);
  const texture=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,texture);
  gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL,false);
  gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL,false);
  gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,image);
  gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
  const columns=16,rows=10,vertices=new Float32Array((columns+1)*(rows+1)*4),indices=[];
  for(let y=0;y<rows;y++)for(let x=0;x<columns;x++){
    const a=y*(columns+1)+x,b=a+1,c=a+columns+1,d=c+1;indices.push(a,c,b,b,c,d);
  }
  const vertexBuffer=gl.createBuffer(),indexBuffer=gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER,vertexBuffer);gl.bufferData(gl.ARRAY_BUFFER,vertices.byteLength,gl.DYNAMIC_DRAW);
  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,indexBuffer);gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,new Uint16Array(indices),gl.STATIC_DRAW);
  const pos=gl.getAttribLocation(program,'a_position'),uv=gl.getAttribLocation(program,'a_uv');
  gl.enableVertexAttribArray(pos);gl.vertexAttribPointer(pos,2,gl.FLOAT,false,16,0);
  gl.enableVertexAttribArray(uv);gl.vertexAttribPointer(uv,2,gl.FLOAT,false,16,8);
  const heat=gl.getUniformLocation(program,'u_heat');gl.uniform1i(gl.getUniformLocation(program,'u_image'),0);
  gl.enable(gl.BLEND);gl.blendFunc(gl.ONE,gl.ONE_MINUS_SRC_ALPHA);gl.clearColor(0,0,0,0);
  return {
    draw(frame,time,reduced,sample){
      gl.viewport(0,0,canvas.width,canvas.height);gl.clear(gl.COLOR_BUFFER_BIT);
      let index=0;
      for(let y=0;y<=rows;y++)for(let x=0;x<=columns;x++){
        const u=x/columns,v=y/rows,p=bodyMotion({x:u,y:v},time,reduced);
        vertices[index++]=2*(frame.x+p.x*frame.width)/frame.containerWidth-1;
        vertices[index++]=1-2*(frame.y+p.y*frame.height)/frame.containerHeight;
        vertices[index++]=u;vertices[index++]=v;
      }
      gl.bindBuffer(gl.ARRAY_BUFFER,vertexBuffer);gl.bufferSubData(gl.ARRAY_BUFFER,0,vertices);
      gl.uniform2f(heat,sample.head-36.8,sample.torso-37.1);gl.drawElements(gl.TRIANGLES,indices.length,gl.UNSIGNED_SHORT,0);
    },
    destroy(){gl.deleteBuffer(vertexBuffer);gl.deleteBuffer(indexBuffer);gl.deleteTexture(texture);gl.deleteProgram(program);}
  };
}

function makeCanvasRenderer(canvas,image){
  const context=canvas.getContext('2d'),heatCanvas=document.createElement('canvas');
  heatCanvas.width=836;heatCanvas.height=471;
  const hc=heatCanvas.getContext('2d',{willReadFrequently:true});hc.drawImage(image,0,0,836,471);
  const original=hc.getImageData(0,0,836,471),output=hc.createImageData(836,471);let previous='';
  function updateHeat(sample){
    const key=`${sample.head}:${sample.torso}`;if(previous===key)return;previous=key;
    for(let y=0;y<471;y++)for(let x=0;x<836;x++){
      const i=(y*836+x)*4,s=clamp((x/836-.34)/.14),mix=s*s*(3-2*s);
      const delta=(sample.head-36.8)*(1-mix)+(sample.torso-37.1)*mix;
      output.data[i]=original.data[i];output.data[i+1]=clamp(original.data[i+1]/255-delta*.22,.04,1)*255;
      output.data[i+2]=clamp(original.data[i+2]/255-delta*.12,.02,1)*255;output.data[i+3]=original.data[i+3];
    }hc.putImageData(output,0,0);
  }
  function triangle(source,destination){
    const [s0,s1,s2]=source,[d0,d1,d2]=destination;
    const den=s0.x*(s1.y-s2.y)+s1.x*(s2.y-s0.y)+s2.x*(s0.y-s1.y);if(!den)return;
    const a=(d0.x*(s1.y-s2.y)+d1.x*(s2.y-s0.y)+d2.x*(s0.y-s1.y))/den;
    const b=(d0.y*(s1.y-s2.y)+d1.y*(s2.y-s0.y)+d2.y*(s0.y-s1.y))/den;
    const c=(d0.x*(s2.x-s1.x)+d1.x*(s0.x-s2.x)+d2.x*(s1.x-s0.x))/den;
    const d=(d0.y*(s2.x-s1.x)+d1.y*(s0.x-s2.x)+d2.y*(s1.x-s0.x))/den;
    const e=d0.x-a*s0.x-c*s0.y,f=d0.y-b*s0.x-d*s0.y;
    context.save();context.beginPath();context.moveTo(d0.x,d0.y);context.lineTo(d1.x,d1.y);context.lineTo(d2.x,d2.y);context.closePath();context.clip();context.transform(a,b,c,d,e,f);context.drawImage(heatCanvas,0,0);context.restore();
  }
  return {draw(frame,time,reduced,sample){
    updateHeat(sample);context.setTransform(frame.dpr,0,0,frame.dpr,0,0);context.clearRect(0,0,frame.containerWidth,frame.containerHeight);
    const columns=16,rows=10,source=[],destination=[];
    for(let y=0;y<=rows;y++)for(let x=0;x<=columns;x++){
      const p=bodyMotion({x:x/columns,y:y/rows},time,reduced);
      source.push({x:x/columns*836,y:y/rows*471});destination.push({x:frame.x+p.x*frame.width,y:frame.y+p.y*frame.height});
    }
    for(let y=0;y<rows;y++)for(let x=0;x<columns;x++){
      const a=y*(columns+1)+x,b=a+1,c=a+columns+1,d=c+1;
      triangle([source[a],source[c],source[b]],[destination[a],destination[c],destination[b]]);
      triangle([source[b],source[c],source[d]],[destination[b],destination[c],destination[d]]);
    }
  },destroy(){}};
}

export function createThermalMonitor(container,{onSelect=()=>{}}={}) {
  installStyles();
  if(getComputedStyle(container).position==='static')container.style.position='relative';
  const root=document.createElement('div');root.className='tp-thermal-root';root.tabIndex=0;
  root.setAttribute('role','group');root.setAttribute('aria-label','아기 온도 모니터링. 지점을 눌러 온도를 확인하세요. 방향키로 지점 이동, Escape로 기본 추적');
  let imageCanvas=document.createElement('canvas');const overlay=document.createElement('canvas');
  imageCanvas.setAttribute('aria-hidden','true');overlay.setAttribute('aria-hidden','true');
  const legend=document.createElement('span');legend.className='tp-thermal-scale';legend.setAttribute('aria-hidden','true');
  const status=document.createElement('span');status.className='tp-thermal-sr';status.setAttribute('aria-live','polite');
  root.append(imageCanvas,overlay,legend,status);container.append(root);
  const labels=Array.from({length:2},()=>{
    const element=document.createElement('div');element.className='tp-thermal-label';
    const title=document.createElement('div');title.className='tp-thermal-label-title';
    const name=document.createElement('span'),led=document.createElement('span');led.className='tp-thermal-led';led.setAttribute('aria-label','추적 중');
    const value=document.createElement('div');value.className='tp-thermal-value';title.append(name,led);element.append(title,value);root.append(element);return {element,name,led,value};
  });
  const context=overlay.getContext('2d'),image=new Image(),media=matchMedia('(prefers-reduced-motion: reduce)');
  let renderer=null,selected=null,sample={head:36.6,torso:36.8},lastSample=performance.now(),disposed=false;
  let frame={x:0,y:0,width:0,height:0,containerWidth:0,containerHeight:0,dpr:1};
  let covered=new Set(),projected=[],lastDraw=-Infinity,raf=0,pointer=null;
  const resize=()=>{
    const bounds=root.getBoundingClientRect(),width=bounds.width,height=bounds.height,dpr=Math.min(devicePixelRatio||1,2);
    frame={containerWidth:width,containerHeight:height,width:Math.min(width,height*16/9),height:Math.min(width*9/16,height),dpr};
    frame.x=(width-frame.width)/2;frame.y=(height-frame.height)/2;
    for(const canvas of [imageCanvas,overlay]){canvas.width=Math.max(1,Math.round(width*dpr));canvas.height=Math.max(1,Math.round(height*dpr));}
    lastDraw=-Infinity;
  };
  const observer=new ResizeObserver(resize);observer.observe(root);resize();
  image.onload=()=>{
    if(disposed)return;
    const mask=document.createElement('canvas');mask.width=COLUMNS;mask.height=ROWS;
    const m=mask.getContext('2d',{willReadFrequently:true});m.drawImage(image,0,0,COLUMNS,ROWS);
    const pixels=m.getImageData(0,0,COLUMNS,ROWS).data;
    covered=new Set(POINTS.map((p,i)=>pixels[i*4+3]>64?i:-1).filter(i=>i>=0));
    try{renderer=makeGLRenderer(imageCanvas,image);}catch{renderer=null;}
    if(!renderer){
      const replacement=document.createElement('canvas');replacement.setAttribute('aria-hidden','true');imageCanvas.replaceWith(replacement);imageCanvas=replacement;resize();renderer=makeCanvasRenderer(imageCanvas,image);
    }
    root.dataset.ready='true';
  };
  image.onerror=()=>{if(disposed)return;const text=document.createElement('div');text.className='tp-thermal-error';text.textContent='아기 모습을 불러오지 못했어요. 새로고침해 주세요.';root.append(text);};
  image.src=new URL('./assets/baby.png',import.meta.url).href;
  function draw(now){
    if(disposed)return;raf=requestAnimationFrame(draw);
    if(document.hidden||!renderer||!frame.width||!frame.height||now-lastDraw<1000/30)return;lastDraw=now;
    const time=(now-MOTION_START)/1000,reduced=media.matches;
    renderer.draw(frame,time,reduced,sample);
    context.setTransform(frame.dpr,0,0,frame.dpr,0,0);context.clearRect(0,0,frame.containerWidth,frame.containerHeight);
    projected=POINTS.map((point,index)=>{
      const p=bodyMotion(position(point),time,reduced),x=frame.x+p.x*frame.width,y=frame.y+p.y*frame.height;
      context.fillStyle=covered.has(index)?'rgba(255,255,255,.94)':'rgba(255,255,255,.55)';context.beginPath();context.arc(x,y,.6,0,Math.PI*2);context.fill();return {point,index,x,y};
    });
    const tracking=now-lastSample<15000,shown=selected?[selected]:DEFAULT_POINTS;
    for(let i=0;i<2;i++){
      const label=labels[i],point=shown[i];label.element.hidden=!point;if(!point)continue;
      const original=position(point),p=bodyMotion(original,time,reduced),x=frame.x+p.x*frame.width,y=frame.y+p.y*frame.height;
      context.fillStyle=tracking?'#a60031':'#777a74';context.beginPath();context.arc(x,y,3.5,0,Math.PI*2);context.fill();context.strokeStyle='rgba(255,255,255,.97)';context.lineWidth=1.5;context.stroke();
      const defaultX=frame.x+(i===0?.21:.52)*frame.width+(p.x-original.x)*frame.width;
      const labelX=clamp(selected?x:defaultX,48,frame.containerWidth-48);
      const labelY=selected?(y<72?y+48:y-48):Math.max(40,y-64);
      label.element.style.left=`${labelX}px`;label.element.style.top=`${clamp(labelY,36,frame.containerHeight-36)}px`;
      label.name.textContent=selected?'선택 지점':i===0?'머리':'몸통';label.led.hidden=!!selected;label.led.dataset.live=String(tracking);label.led.setAttribute('aria-label',tracking?'추적 중':'추적 대기');
      const temperature=pointTemperature(point,sample);label.value.textContent=`${temperature===null?'--.-':temperature.toFixed(1)}°C`;
    }
  }
  function select(point,notify=true){
    if(samePoint(point,selected)||(!point&&!selected))return;
    selected=point?{column:clamp(Math.round(point.column),0,COLUMNS-1),row:clamp(Math.round(point.row),0,ROWS-1)}:null;
    status.textContent=selected?`선택 지점 ${pointTemperature(selected,sample)?.toFixed(1)}도. 빈 곳을 누르면 기본 추적으로 돌아갑니다.`:'머리와 몸통을 추적합니다.';
    if(notify)onSelect(selected?{...selected}:null);
  }
  function hit(event){
    if(!projected.length)return null;
    const bounds=root.getBoundingClientRect(),x=event.clientX-bounds.left,y=event.clientY-bounds.top;
    if(x<frame.x||x>frame.x+frame.width||y<frame.y||y>frame.y+frame.height)return null;
    let nearest=null,distance=Infinity;
    for(const p of projected){const d=(p.x-x)**2+(p.y-y)**2;if(d<distance){distance=d;nearest=p;}}
    return nearest&&covered.has(nearest.index)?nearest.point:null;
  }
  const down=event=>{if(event.isPrimary===false||event.button>0)return;pointer=event.pointerId;root.setPointerCapture?.(pointer);select(hit(event));};
  const move=event=>{if(event.pointerId!==pointer)return;const point=hit(event);if(point)select(point);};
  const up=event=>{if(event.pointerId!==pointer)return;if(!hit(event))select(null);pointer=null;};
  const cancel=()=>{pointer=null;};
  const keydown=event=>{
    if(event.key==='Escape'){event.preventDefault();select(null);return;}
    const steps={ArrowLeft:[-1,0],ArrowRight:[1,0],ArrowUp:[0,-1],ArrowDown:[0,1]};
    if(event.key==='Enter'||event.key===' '){event.preventDefault();select(selected?null:DEFAULT_POINTS[1]);return;}
    if(!steps[event.key])return;event.preventDefault();
    const [dx,dy]=steps[event.key],start=selected||DEFAULT_POINTS[1];
    for(let distance=1;distance<Math.max(COLUMNS,ROWS);distance++){
      const candidate={column:start.column+dx*distance,row:start.row+dy*distance};
      if(candidate.column<0||candidate.column>=COLUMNS||candidate.row<0||candidate.row>=ROWS)break;
      if(covered.has(candidate.row*COLUMNS+candidate.column)){select(candidate);break;}
    }
  };
  root.addEventListener('pointerdown',down);root.addEventListener('pointermove',move);root.addEventListener('pointerup',up);root.addEventListener('pointercancel',cancel);root.addEventListener('keydown',keydown);
  raf=requestAnimationFrame(draw);
  return {
    setSample(value){if(value&&Number.isFinite(value.head)&&Number.isFinite(value.torso)){sample={head:value.head,torso:value.torso};lastSample=performance.now();}},
    setSelected(point){select(point,false);},
    destroy(){disposed=true;cancelAnimationFrame(raf);observer.disconnect();renderer?.destroy();root.remove();}
  };
}
