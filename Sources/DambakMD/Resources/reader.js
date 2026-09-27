'use strict';
const bridge = window.webkit.messageHandlers.reader;
let matches = [], matchIndex = -1;
function post(type, value) { bridge.postMessage({type, value}); }
function applySettings(settings) {
  document.documentElement.dataset.theme = settings.theme;
  document.documentElement.style.setProperty('--font-size', `${settings.fontSize}px`);
  document.documentElement.style.setProperty('--width', `${settings.width}px`);
}
function goTo(id) { const el = document.getElementById(id); if (el) el.scrollIntoView({block:'start'}); }
function position() {
  const hs = [...document.querySelectorAll('h1,h2,h3,h4,h5,h6')];
  let current = hs[0];
  for (const h of hs) { if (h.getBoundingClientRect().top <= 90) current = h; else break; }
  return {heading:current?.id || '', fraction: current ? Math.max(0, (scrollY - (current.offsetTop || 0)) / Math.max(1, document.documentElement.scrollHeight - current.offsetTop)) : scrollY / Math.max(1, document.documentElement.scrollHeight - innerHeight), y:scrollY};
}
function restorePosition(pos) {
  if (!pos) return;
  const h = document.getElementById(pos.heading);
  if (h) scrollTo(0, h.offsetTop + pos.fraction * Math.max(1, document.documentElement.scrollHeight - h.offsetTop));
  else scrollTo(0, pos.y || 0);
}
function clearSearch() { for (const mark of matches) { const p = mark.parentNode; if (p) { p.replaceChild(document.createTextNode(mark.textContent),mark); p.normalize(); } } matches=[]; matchIndex=-1; post('search',{count:0,index:0}); }
function search(query) {
  clearSearch(); if (!query) return;
  const walker=document.createTreeWalker(document.querySelector('main'),NodeFilter.SHOW_TEXT,{acceptNode(n){return n.parentElement.closest('script,style,mark') ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT;}});
  const nodes=[]; while(walker.nextNode()) nodes.push(walker.currentNode);
  for(const node of nodes) {
    const value=node.nodeValue, lower=value.toLocaleLowerCase(), target=query.toLocaleLowerCase(); let cursor=0, at;
    const offsets=[];
    while((at=lower.indexOf(target,cursor))!==-1) { offsets.push(at); cursor=at+target.length; }
    for(const offset of offsets.reverse()) { const range=document.createRange(); range.setStart(node,offset); range.setEnd(node,offset+target.length); const mark=document.createElement('mark'); mark.className='dambak-match'; range.surroundContents(mark); matches.unshift(mark); }
  }
  if(matches.length) stepSearch(1); else post('search',{count:0,index:0});
}
function stepSearch(direction) { if(!matches.length)return; if(matchIndex>=0) matches[matchIndex].classList.remove('dambak-current'); matchIndex=(matchIndex+direction+matches.length)%matches.length; const m=matches[matchIndex]; m.classList.add('dambak-current'); m.scrollIntoView({block:'center'}); post('search',{count:matches.length,index:matchIndex+1}); }
document.addEventListener('click',event=>{ const link=event.target.closest('a'); if(link){ event.preventDefault(); post('link',link.getAttribute('href')); return; } const copy=event.target.closest('.copy'); if(copy){ const code=copy.parentElement.querySelector('code'); post('copy',code?.textContent||''); copy.textContent='복사됨'; setTimeout(()=>copy.textContent='복사',1200); } });
let scrollTimer; addEventListener('scroll',()=>{ clearTimeout(scrollTimer); scrollTimer=setTimeout(()=>{const p=position();post('position',p);post('heading',p.heading);},120); },{passive:true});
addEventListener('load',()=>{ if(window.hljs) document.querySelectorAll('pre code').forEach(el=>hljs.highlightElement(el)); post('ready',true); });
