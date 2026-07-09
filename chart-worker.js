// Stoma Alert — reference-chart reader, BACKGROUND worker (OpenCV.js) — EXPERIMENTAL
// Runs the full chart pipeline off the main thread so a slow/pathological read can never
// freeze the UI. The page owns a hard timeout that terminates this worker if it ever stalls.
// The CV functions below are byte-identical to the former in-page pipeline.
//
// Protocol:
//   page → worker : { type:'read', img:{ buf:ArrayBuffer(RGBA), w, h } }   (buf transferred)
//   worker → page : { type:'progress', text }                              (stage updates)
//                   { type:'fail', text }                                  (graceful failure)
//                   { type:'result', measured:{equiv,maxd,area,ell}|null,
//                                    rot, meanErr, npair,
//                                    disp:{ buf:ArrayBuffer(RGBA), w, h } } (buf transferred)

// Load OpenCV.js at worker startup (also warms it while the user is still framing the shot).
// CRITICAL: use the single-threaded @techstark build via jsDelivr, NOT docs.opencv.org.
// The docs.opencv.org build is a pthreads build — once its runtime initialises it hijacks the
// worker's message channel and the worker can no longer receive our image messages (verified the
// hard way). The @techstark build is single-threaded and worker-safe, exposes the same `cv` API,
// and jsDelivr is a production CDN (docs.opencv.org is a docs host, not built for asset serving).
let _cvLoaded = true;
try { importScripts('https://cdn.jsdelivr.net/npm/@techstark/opencv-js@4.11.0-release.1/dist/opencv.js'); }
catch(e){ _cvLoaded = false; }

let _cvReady = null;
// The build still signals "ready" inconsistently (cv.Mat immediate | cv is a thenable). We unwrap
// any thenable AND poll self.cv for a usable Mat, whichever wins, with a timeout. (The page also
// hard-terminates a stuck worker after 25s, so a stalled load can never freeze the UI.)
function ensureCv(){
  if(_cvReady) return _cvReady;
  _cvReady = new Promise((resolve, reject) => {
    if(!_cvLoaded){ reject(new Error('download failed')); return; }
    let settled = false;
    const usable = c => c && c.Mat && typeof c.Mat === 'function';
    const finish = c => { if(settled) return; settled = true; clearInterval(iv); resolve(c); };
    const g = self.cv;
    if(usable(g)) return resolve(g);
    if(g && typeof g.then === 'function'){ g.then(c => { self.cv = c; if(usable(c)) finish(c); }); }   // newer builds: cv is a Promise
    const t0 = Date.now();
    const iv = setInterval(() => {
      if(settled) return;
      const c = self.cv;
      if(usable(c)) return finish(c);
      if(Date.now() - t0 > 20000){ settled = true; clearInterval(iv); reject(new Error('did not initialise')); }
    }, 30);
  });
  return _cvReady;
}

const CHART_PATCHES=[[0.1242,0.1242,255,255,255],[0.0547,0.2452,224,163,46],[0.1011,0.2452,8,133,161],[0.1474,0.2452,103,189,170],[0.0547,0.2915,157,188,64],[0.1011,0.2915,187,86,149],[0.1474,0.2915,133,128,177],[0.0547,0.3378,94,60,108],[0.1011,0.3378,231,199,31],[0.1474,0.3378,87,108,67],[0.0547,0.3842,193,90,99],[0.1011,0.3842,175,54,60],[0.1474,0.3842,98,122,157],[0.0547,0.4305,80,91,166],[0.1011,0.4305,70,148,73],[0.1474,0.4305,194,150,130],[0.0547,0.4768,214,126,44],[0.1011,0.4768,56,61,150],[0.1474,0.4768,115,82,68],[0.0547,0.5232,255,0,0],[0.1011,0.5232,207,41,41],[0.1474,0.5232,52,52,52],[0.0547,0.5695,0,255,0],[0.1011,0.5695,166,33,33],[0.1474,0.5695,85,85,85],[0.0547,0.6158,0,0,255],[0.1011,0.6158,124,25,25],[0.1474,0.6158,122,122,122],[0.0547,0.6621,0,174,239],[0.1011,0.6621,226,127,127],[0.1474,0.6621,160,160,160],[0.0547,0.7085,236,0,140],[0.1011,0.7085,255,229,180],[0.1474,0.7085,200,200,200],[0.0547,0.7548,255,242,0],[0.1011,0.7548,255,221,180],[0.1474,0.7548,243,243,242],[0.1242,0.8758,255,255,255],[0.8758,0.1242,255,255,255],[0.8526,0.2452,224,163,46],[0.8989,0.2452,8,133,161],[0.9453,0.2452,103,189,170],[0.8526,0.2915,157,188,64],[0.8989,0.2915,187,86,149],[0.9453,0.2915,133,128,177],[0.8526,0.3378,94,60,108],[0.8989,0.3378,231,199,31],[0.9453,0.3378,87,108,67],[0.8526,0.3842,193,90,99],[0.8989,0.3842,175,54,60],[0.9453,0.3842,98,122,157],[0.8526,0.4305,80,91,166],[0.8989,0.4305,70,148,73],[0.9453,0.4305,194,150,130],[0.8526,0.4768,214,126,44],[0.8989,0.4768,56,61,150],[0.9453,0.4768,115,82,68],[0.8526,0.5232,255,0,0],[0.8989,0.5232,207,41,41],[0.9453,0.5232,52,52,52],[0.8526,0.5695,0,255,0],[0.8989,0.5695,166,33,33],[0.9453,0.5695,85,85,85],[0.8526,0.6158,0,0,255],[0.8989,0.6158,124,25,25],[0.9453,0.6158,122,122,122],[0.8526,0.6621,0,174,239],[0.8989,0.6621,226,127,127],[0.9453,0.6621,160,160,160],[0.8526,0.7085,236,0,140],[0.8989,0.7085,255,229,180],[0.9453,0.7085,200,200,200],[0.8526,0.7548,255,242,0],[0.8989,0.7548,255,221,180],[0.9453,0.7548,243,243,242],[0.8758,0.8758,255,255,255]];
const CHART = { CANON:900, ROI_R_NORM:0.3089, ROI_DIAM_MM:120 };       // window = 340.2pt = 120mm
CHART.MM_PER_PX = CHART.ROI_DIAM_MM / (2 * CHART.ROI_R_NORM * CHART.CANON);   // ~0.2158 mm/px
const CHART_XY = CHART_PATCHES.map(p => [p[0]*CHART.CANON, p[1]*CHART.CANON]);
const CHART_NEUTRAL = CHART_PATCHES.filter(p => Math.max(p[2],p[3],p[4]) - Math.min(p[2],p[3],p[4]) <= 4);
const _med = a => { if(!a.length) return 0; a.sort((x,y)=>x-y); return a[a.length>>1]; };

// median RGB in a (±half) box around normalised (xn,yn) of an RGBA mat
function cvSampleRGB(mat, xn, yn, half){
  const W=mat.cols, H=mat.rows, d=mat.data, x=Math.round(xn*W), y=Math.round(yn*H);
  const rs=[],gs=[],bs=[];
  for(let j=Math.max(0,y-half); j<Math.min(H,y+half); j++)
    for(let i=Math.max(0,x-half); i<Math.min(W,x+half); i++){ const o=(j*W+i)*4; rs.push(d[o]); gs.push(d[o+1]); bs.push(d[o+2]); }
  return [_med(rs),_med(gs),_med(bs)];
}
// detect square swatch centres + median colour in an RGBA mat → [{x,y,rgb}]
function cvSwatches(cv, mat){
  const out=[], gray=new cv.Mat(), edges=new cv.Mat(), k=cv.Mat.ones(3,3,cv.CV_8U),
        contours=new cv.MatVector(), hier=new cv.Mat();
  try{
    cv.cvtColor(mat, gray, cv.COLOR_RGBA2GRAY);
    cv.Canny(gray, edges, 40, 120); cv.dilate(edges, edges, k);
    cv.findContours(edges, contours, hier, cv.RETR_LIST, cv.CHAIN_APPROX_SIMPLE);
    const fa=mat.cols*mat.rows, d=mat.data, W=mat.cols;
    for(let c=0;c<contours.size();c++){
      const cnt=contours.get(c), a=cv.contourArea(cnt);
      if(a>=fa*3e-4 && a<=fa*5e-3){
        const r=cv.boundingRect(cnt), ar=r.width/r.height, fill=a/(r.width*r.height);
        if(ar>0.6 && ar<1.7 && fill>0.6){
          const rs=[],gs=[],bs=[], x0=r.x+(r.width>>2), x1=r.x+3*(r.width>>2), y0=r.y+(r.height>>2), y1=r.y+3*(r.height>>2);
          for(let j=y0;j<y1;j++) for(let i=x0;i<x1;i++){ const o=(j*W+i)*4; rs.push(d[o]); gs.push(d[o+1]); bs.push(d[o+2]); }
          out.push({x:r.x+r.width/2, y:r.y+r.height/2, rgb:[_med(rs),_med(gs),_med(bs)]});
        }
      }
      cnt.delete();
    }
  } finally { gray.delete(); edges.delete(); k.delete(); contours.delete(); hier.delete(); }
  return out;
}
function orderQuad(q){
  const sum=q.map(p=>p[0]+p[1]), diff=q.map(p=>p[1]-p[0]);
  return [ q[sum.indexOf(Math.min(...sum))], q[diff.indexOf(Math.min(...diff))],
           q[sum.indexOf(Math.max(...sum))], q[diff.indexOf(Math.max(...diff))] ];   // tl,tr,br,bl
}
// swatch point-cloud → oriented card quad (rotation-safe; ignores bright skin/bedsheet)
function cvDetectCard(cv, mat){
  const sw=cvSwatches(cv, mat);
  if(sw.length<20) return null;
  const cx=sw.reduce((s,p)=>s+p.x,0)/sw.length, cy=sw.reduce((s,p)=>s+p.y,0)/sw.length;
  const dist=sw.map(p=>Math.hypot(p.x-cx,p.y-cy));
  const md=_med([...dist]), mad=_med(dist.map(x=>Math.abs(x-md)));
  let keep=sw.filter((p,i)=>dist[i] < md + 2.5*(mad+1e-6));
  if(keep.length<20) keep=sw;
  const pts=cv.matFromArray(keep.length,1,cv.CV_32FC2, keep.flatMap(p=>[p.x,p.y]));
  const rot=cv.minAreaRect(pts); pts.delete();
  rot.size.width*=1.16; rot.size.height*=1.16;
  const box=cv.boxPoints(rot);                     // OpenCV.js returns [{x,y}×4], not a Mat
  return orderQuad(box.map(p=>[p.x,p.y]));
}
function cvRectify(cv, mat, quad, S, mats){
  const s=cv.matFromArray(4,1,cv.CV_32FC2, quad.flat()); mats.push(s);
  const dp=cv.matFromArray(4,1,cv.CV_32FC2, [0,0,S,0,S,S,0,S]); mats.push(dp);
  const Mx=cv.getPerspectiveTransform(s,dp); mats.push(Mx);
  const out=new cv.Mat(); mats.push(out);
  cv.warpPerspective(mat,out,Mx,new cv.Size(S,S)); return out;
}
// try 4 rotations, keep the one whose swatches best match the template, then RANSAC-refine
function cvRegister(cv, rect, mats){
  const S=CHART.CANON, codes=[null, cv.ROTATE_90_CLOCKWISE, cv.ROTATE_180, cv.ROTATE_90_COUNTERCLOCKWISE];
  let best=null;
  for(let k=0;k<4;k++){
    const rotM=new cv.Mat();
    if(k===0) rect.copyTo(rotM); else cv.rotate(rect,rotM,codes[k]);
    const sw=cvSwatches(cv,rotM);
    if(sw.length<20){ rotM.delete(); continue; }
    const pairs=[], used=new Set();
    for(const p of sw){
      let bj=-1,bd=1e18;
      for(let j=0;j<CHART_XY.length;j++){ const dx=CHART_XY[j][0]-p.x, dy=CHART_XY[j][1]-p.y, dd=dx*dx+dy*dy; if(dd<bd){bd=dd;bj=j;} }
      if(bj>=0 && Math.sqrt(bd)<0.06*S && !used.has(bj)){ used.add(bj); pairs.push([p,bj]); }
    }
    if(pairs.length<20){ rotM.delete(); continue; }
    let de=0; for(const [p,j] of pairs){ const t=CHART_PATCHES[j]; de+=Math.hypot(p.rgb[0]-t[2],p.rgb[1]-t[3],p.rgb[2]-t[4]); } de/=pairs.length;
    if(!best || de<best.de){ if(best) best.rotM.delete(); best={de,k,rotM,pairs}; } else rotM.delete();
  }
  if(!best) return null;
  const src=cv.matFromArray(best.pairs.length,1,cv.CV_32FC2, best.pairs.flatMap(([p])=>[p.x,p.y]));
  const dst=cv.matFromArray(best.pairs.length,1,cv.CV_32FC2, best.pairs.flatMap(([,j])=>CHART_XY[j]));
  const Hm=cv.findHomography(src,dst,cv.RANSAC,5.0), reg=new cv.Mat();
  cv.warpPerspective(best.rotM,reg,Hm,new cv.Size(S,S));
  src.delete(); dst.delete(); Hm.delete(); best.rotM.delete(); mats.push(reg);
  return {reg, rot:best.k*90, npair:best.pairs.length, de:+best.de.toFixed(1)};
}
// per-channel linear fit true = g·obs + o over the neutral (grey-ramp) patches
function cvWhiteBalance(cv, reg, mats){
  const obs=[[],[],[]], tru=[[],[],[]];
  for(const p of CHART_NEUTRAL){ const s=cvSampleRGB(reg,p[0],p[1],6); for(let c=0;c<3;c++){ obs[c].push(s[c]); tru[c].push(p[2+c]); } }
  const fit=(xs,ys)=>{ const n=xs.length; let sx=0,sy=0,sxx=0,sxy=0; for(let i=0;i<n;i++){sx+=xs[i];sy+=ys[i];sxx+=xs[i]*xs[i];sxy+=xs[i]*ys[i];} const dn=(n*sxx-sx*sx)||1e-6; const g=(n*sxy-sx*sy)/dn; return [g,(sy-g*sx)/n]; };
  const planes=new cv.MatVector(); cv.split(reg, planes);
  const outv=new cv.MatVector(), gains=[];
  for(let c=0;c<planes.size();c++){
    const pl=planes.get(c);
    if(c<3){ const [g,o]=fit(obs[c],tru[c]); const adj=new cv.Mat(); pl.convertTo(adj,-1,g,o); outv.push_back(adj); adj.delete(); gains.push([+g.toFixed(3),+o.toFixed(1)]); }
    else outv.push_back(pl);
    pl.delete();
  }
  const wb=new cv.Mat(); mats.push(wb); cv.merge(outv, wb); planes.delete(); outv.delete();
  // measure residual colour error on all patches (honest quality read)
  let e=0; for(const p of CHART_PATCHES){ const s=cvSampleRGB(wb,p[0],p[1],6); e+=Math.hypot(s[0]-p[2],s[1]-p[3],s[2]-p[4]); }
  return {wb, gains, meanErr:+(e/CHART_PATCHES.length).toFixed(1)};
}
// cut 120mm ROI, segment the stoma (colour-true HSV), measure in mm
function cvMeasure(cv, wb, mats){
  const S=CHART.CANON, cx=S/2, cy=S/2, R=CHART.ROI_R_NORM*S, MM=CHART.MM_PER_PX;
  const rgb=new cv.Mat(), hsv=new cv.Mat(); mats.push(rgb,hsv);
  cv.cvtColor(wb, rgb, cv.COLOR_RGBA2RGB); cv.cvtColor(rgb, hsv, cv.COLOR_RGB2HSV);
  const hd=hsv.data, rd=rgb.data, mask=cv.Mat.zeros(S,S,cv.CV_8UC1); mats.push(mask);
  const mdata=mask.data, rr=(R*0.98)*(R*0.98);
  for(let j=0;j<S;j++) for(let i=0;i<S;i++){
    const dx=i-cx, dy=j-cy; if(dx*dx+dy*dy>rr) continue;
    const o=(j*S+i)*3, Hh=hd[o], Ss=hd[o+1], Vv=hd[o+2], Rr=rd[o], Gg=rd[o+1];
    if(((Hh<15)||(Hh>160)) && Ss>140 && Vv<190 && (Rr-Gg)>85) mdata[j*S+i]=255;
  }
  const k1=cv.Mat.ones(5,5,cv.CV_8U), k2=cv.Mat.ones(15,15,cv.CV_8U);
  cv.morphologyEx(mask,mask,cv.MORPH_OPEN,k1); cv.morphologyEx(mask,mask,cv.MORPH_CLOSE,k2);
  k1.delete(); k2.delete();
  const contours=new cv.MatVector(), hier=new cv.Mat(); mats.push(hier);
  cv.findContours(mask,contours,hier,cv.RETR_EXTERNAL,cv.CHAIN_APPROX_SIMPLE);
  let best=null;
  for(let c=0;c<contours.size();c++){
    const cnt=contours.get(c), a=cv.contourArea(cnt), M=cv.moments(cnt);
    if(M.m00>0 && a>200){ const dist=Math.hypot(M.m10/M.m00-cx, M.m01/M.m00-cy), sc=a-dist*30;
      if(!best||sc>best.sc){ if(best) best.cnt.delete(); best={sc,a,cnt}; } else cnt.delete();
    } else cnt.delete();
  }
  contours.delete();
  if(!best) return null;
  const mec=cv.minEnclosingCircle(best.cnt);
  const res={ equiv:2*Math.sqrt(best.a/Math.PI)*MM, maxd:2*mec.radius*MM, area:best.a*MM*MM, cnt:best.cnt, mec };
  if(best.cnt.rows>=5){ const e=cv.fitEllipse(best.cnt); res.ell=[Math.max(e.size.width,e.size.height)*MM, Math.min(e.size.width,e.size.height)*MM]; }
  return res;   // caller deletes res.cnt
}

// ---- driver: mirrors the old runChartReader try-block, but posts messages instead of touching the DOM ----
self.onmessage = async (ev) => {
  const msg = ev.data || {};
  if(msg.type !== 'read') return;
  const post = (o, transfer) => self.postMessage(o, transfer || []);

  let cv;
  try { cv = await ensureCv(); }
  catch(e){ post({ type:'fail', text:'Could not load the vision module — check your connection. The card-free colour above still applies.' }); return; }

  const imgData = new ImageData(new Uint8ClampedArray(msg.img.buf), msg.img.w, msg.img.h);
  const mats = [];
  let measured = null;
  try {
    const mat = cv.matFromImageData(imgData); mats.push(mat);   // RGBA (CV_8UC4)
    const quad = cvDetectCard(cv, mat);
    if(!quad){ post({ type:'fail', text:'Could not find the chart. Lay the whole card flat with all colour panels and both checker bars in frame, then retake. (Card-free colour above still applies.)' }); return; }
    post({ type:'progress', text:'Straightening…' });
    const rect = cvRectify(cv, mat, quad, CHART.CANON, mats);
    const reg = cvRegister(cv, rect, mats);
    if(!reg){ post({ type:'fail', text:'Found the chart but could not lock onto the colour patches — try again with even light, no glare, whole card in frame. (Card-free colour above still applies.)' }); return; }
    post({ type:'progress', text:'Correcting colour…' });
    const { wb, meanErr } = cvWhiteBalance(cv, reg.reg, mats);
    post({ type:'progress', text:'Measuring…' });
    measured = cvMeasure(cv, wb, mats);
    // overlay measurement on the corrected chart (RGBA disp for the UI)
    const disp = new cv.Mat(); mats.push(disp); wb.copyTo(disp);
    const yellow = new cv.Scalar(255,220,0,255), green = new cv.Scalar(0,220,0,255), red = new cv.Scalar(255,0,0,255);
    cv.circle(disp, new cv.Point(CHART.CANON/2, CHART.CANON/2), Math.round(CHART.ROI_R_NORM*CHART.CANON), yellow, 2);
    let out = null;
    if(measured){
      const cnts = new cv.MatVector(); cnts.push_back(measured.cnt);
      cv.drawContours(disp, cnts, 0, green, 3); cnts.delete();
      cv.circle(disp, new cv.Point(Math.round(measured.mec.center.x), Math.round(measured.mec.center.y)), Math.round(measured.mec.radius), red, 2);
      out = { equiv:measured.equiv, maxd:measured.maxd, area:measured.area, ell: measured.ell || null };
      measured.cnt.delete(); measured = null;   // freed here; keep it out of the catch double-free
    }
    const rgba = new Uint8ClampedArray(disp.data);   // copy RGBA out of the WASM heap → transferable
    post({ type:'result', measured: out, rot: reg.rot, meanErr, npair: reg.npair,
           disp: { buf: rgba.buffer, w: disp.cols, h: disp.rows } }, [rgba.buffer]);
  } catch(e){
    if(measured && measured.cnt){ try{ measured.cnt.delete(); }catch(_){} }
    post({ type:'fail', text:'Chart read failed: ' + ((e && e.message) || String(e)) + '. The card-free colour above still applies.' });
  } finally {
    mats.forEach(mm => { try { mm.delete(); } catch(_){} });
  }
};
