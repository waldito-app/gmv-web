// Integrated reader controller: bounded page downloads; no PDF or public URL.
// Visual adapter can later use StPageFlip after license and performance review.
import {privatePages} from './private-pages.js';
export function createReader(db, root) {
 const transport=privatePages(db);
 let epoch=0, pages=[], book=null, current=1, urls=[], email='', busy=false;
 const media=matchMedia('(max-width: 700px)');
 const el=(tag,label)=>{const n=document.createElement(tag);if(label)n.textContent=label;return n};
 const prev=el('button','Anterior'), next=el('button','Siguiente'), jump=el('input'), go=el('button','Ir'), status=el('p'), spread=el('div'), mark=el('p');
 jump.type='number';jump.min='1';jump.setAttribute('aria-label','Número de página');
 status.setAttribute('role','status');spread.style.cssText='display:flex;justify-content:center;gap:4px;align-items:flex-start';
 root.replaceChildren(prev,next,jump,go,status,spread,mark);
 function key(){return 'gmv:bookmark:'+book.userId+':'+book.id}
 function save(){try{localStorage.setItem(key(),String(current))}catch{}}
 function release(){for(const u of urls)transport.release(u);urls=[];spread.replaceChildren()}
 function close(){epoch++;transport.clear();release();book=null;pages=[];email='';mark.textContent='';status.textContent='';busy=false;current=1;prev.disabled=next.disabled=go.disabled=true}
 function visible(n){return media.matches||n===1||n===pages.length?[n]:[n,...(n+1<pages.length?[n+1]:[])]}
 async function show(n){
  if(!book||!Number.isInteger(n)||n<1||n>pages.length)return;
  if(!media.matches&&n>1&&n<pages.length)n-=n%2;
  const g=++epoch;transport.clear();release();busy=true;prev.disabled=next.disabled=go.disabled=true;status.textContent='Cargando páginas…';
  const selected=visible(n), id=book.id;
  try{
   const results=await Promise.allSettled(selected.map(p=>transport.page(id,p)));
   const loaded=results.filter(r=>r.status==='fulfilled').map(r=>r.value);
   if(g!==epoch){loaded.forEach(transport.release);return}
   if(results.some(r=>r.status==='rejected')){loaded.forEach(transport.release);throw Error('Page unavailable')}
   urls=loaded;
   const images=urls.map((u,i)=>{const img=el('img');img.src=u;img.alt='Página '+selected[i];img.style.cssText='min-width:0;width:'+ (selected.length===2?'calc(50% - 2px)':'100%') +';max-width:100%;max-height:78vh;object-fit:contain;flex:0 1 auto';return img});
   const watermark=el('div','Lectura personal · '+email);watermark.setAttribute('aria-hidden','true');watermark.style.cssText='position:absolute;inset:0;display:flex;align-items:center;justify-content:center;pointer-events:none;overflow:hidden;color:rgba(70,70,70,.28);font:600 clamp(12px,2vw,22px) sans-serif;overflow-wrap:anywhere;text-align:center;transform:rotate(-18deg)';spread.style.position='relative';spread.replaceChildren(...images,watermark);if(!matchMedia('(prefers-reduced-motion: reduce)').matches&&typeof spread.animate==='function')spread.animate([{opacity:0.55,transform:'perspective(1200px) rotateY(-4deg)'},{opacity:1,transform:'perspective(1200px) rotateY(0deg)'}],{duration:220,easing:'ease-out'});current=n;jump.value=String(n);status.textContent='Página '+selected.join('–')+' de '+pages.length;save();
  }catch{if(g===epoch){release();status.textContent='No se pudo cargar la página. Verificá tu acceso.'}}
  finally{if(g===epoch){busy=false;prev.disabled=current<=1;next.disabled=current>=pages.length;go.disabled=false}}
 }
 async function open(id,session){
  close();if(!session?.user?.id)throw Error('Authentication required');
  const g=epoch;book={id,userId:session.user.id};email=session.user.email||session.user.id;
  try{const data=await transport.manifest(id);if(g!==epoch)return;pages=data;jump.max=String(pages.length);mark.textContent='Lectura personal · '+email;let n=1;try{n=Number(localStorage.getItem(key()))||1}catch{};await show(Math.max(1,Math.min(pages.length,Math.trunc(n))))}catch(e){if(g===epoch)close();throw e}
 }
 prev.onclick=()=>show(media.matches?Math.max(1,current-1):current===pages.length&&current>2?Math.max(1,2*Math.floor((current-2)/2)):Math.max(1,current-2));
 next.onclick=()=>show(Math.min(pages.length,current+visible(current).length));
 go.onclick=()=>show(Number(jump.value));
 const resize=()=>{if(book&&pages.length)void show(current)};
 media.addEventListener('change',resize);
 const {data:{subscription}}=db.auth.onAuthStateChange((_event,session)=>{if(book&&session?.user?.id!==book.userId)close()});
 close();
 return {open,close,destroy(){subscription.unsubscribe();close();media.removeEventListener('change',resize);root.replaceChildren()}};
}
