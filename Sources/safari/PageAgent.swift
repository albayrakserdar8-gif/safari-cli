enum PageAgent {
    /// Returned by the call wrapper when the agent is not in the page yet.
    static let absent = "__smcp_absent__"

    /// Runs in the page's own JavaScript world: hooks console, fetch and XHR, answers
    /// dialogs, and runs `js` code. It is the extension's main.js, injected at document_start
    /// in every frame; the agent reaches it through `__smcp_q`/`__smcp_r` events from the
    /// extension's isolated world.
    static let mainSource = #"""
    (function(){
    if(window.__smcpM)return;
    var M=window.__smcpM={con:null,net:null,slots:{}};
    // safari route for this tab's own fetch/XHR, kept per tab and site in sessionStorage so they
    // apply from the start of the next load. Network rules cannot be limited to one tab in
    // Safari, so the tab's fetch/XHR are routed here. A mocked request keeps its URL plus a
    // secret marker (mk); a network rule for that marker alone sends it to the daemon's mock
    // server. Fetching the http mock server directly would be blocked on https pages.
    M.routes=[];try{M.routes=JSON.parse(sessionStorage.getItem('__smcp_routes')||'[]')}catch(e){}
    function rx(p){if(p.slice(0,3)==='re:')return new RegExp(p.slice(3),'i');var l=p.toLowerCase();if(p.indexOf('*')<0)return{test:function(u){return u.toLowerCase().indexOf(l)>=0}};
      return new RegExp('^'+p.replace(/[.+?^${}()|[\]\\]/g,'\\$&').replace(/\*/g,'.*')+'$','i')}
    function route(u){if(!M.routes.length)return null;var abs;try{abs=new URL(u,location.href).href}catch(e){abs=String(u)}abs=abs.split('#')[0];
      for(var i=M.routes.length-1;i>=0;i--){var r=M.routes[i];try{if(!r.rx)r.rx=rx(r.p);if(r.rx.test(abs))return{r:r,abs:abs}}catch(e){}}return null}
    // Where a routed request goes instead: the mock server, the --redirect target, or null (unchanged).
    function dest(t){if(t.r.k==='redirect')return t.r.to;if(t.r.k!=='mock')return null;var u=t.abs.split('#')[0];return u+(u.indexOf('?')<0?'?':'&')+t.r.mk}
    // Same-origin frames share the tab's sessionStorage: pick up routes set after they loaded.
    addEventListener('storage',function(e){if(e.key==='__smcp_routes'){try{M.routes=JSON.parse(e.newValue||'[]')}catch(x){M.routes=[]}}});
    M.setRoutes=function(l){if(l!=null){M.routes=l;try{l.length?sessionStorage.setItem('__smcp_routes',JSON.stringify(l)):sessionStorage.removeItem('__smcp_routes')}catch(e){}}return M.routes.length};
    function hdrs(h,list){list.forEach(function(x){x[1]===''?h.delete(x[0]):h.set(x[0],x[1])});return h}
    // A CSS selector that finds e alone: test hooks and stable ids first, then a short path.
    function selOf(e){var root=e.getRootNode(),one=function(s){try{var m=root.querySelectorAll(s);return m.length===1&&m[0]===e}catch(x){return false}};
      var q=function(v){return'"'+String(v).replace(/\\/g,'\\\\').replace(/"/g,'\\"')+'"'};
      var auto=function(id){return!id||/\d{3,}|^\d|:|[0-9a-f]{8,}|^(ember|react|radix|headlessui|mui|rc_|uid|ext-gen)/i.test(id)};
      var tag=e.tagName.toLowerCase(),s=null;
      if(!auto(e.id)&&one('#'+CSS.escape(e.id)))return'#'+CSS.escape(e.id);
      ['data-testid','data-test','data-test-id','data-qa','data-cy','name','aria-label','placeholder','title','alt','href','for'].some(function(k){var v=e.getAttribute(k);
        if(v==null||v===''||v.length>80)return false;var c=tag+'['+k+'='+q(v)+']';if(one(c)){s=c;return true}return false});
      if(s)return s;
      var parts=[],n=e;
      for(var d=0;n&&n.nodeType===1&&d<10;d++,n=n.parentElement){var t=n.tagName.toLowerCase();
        if(n!==e&&!auto(n.id)&&root.querySelectorAll('#'+CSS.escape(n.id)).length===1){parts.unshift('#'+CSS.escape(n.id));if(one(parts.join(' > ')))break;parts.shift()}
        var same=n.parentElement?[].filter.call(n.parentElement.children,function(c){return c.tagName===n.tagName}):[];
        // A bare tag ("button") is unique only by luck; keep at least one parent for context.
        parts.unshift(same.length>1?t+':nth-of-type('+(same.indexOf(n)+1)+')':t);if((parts.length>1||/^(main|header|footer|nav|h1)$/.test(t))&&one(parts.join(' > ')))break}
      s=parts.join(' > ');return one(s)?s:null}
    M.loc=function(k){var e=document.querySelector('[data-smcp-el="'+k+'"]');if(!e)return null;e.removeAttribute('data-smcp-el');return selOf(e)};
    // safari record: what the user does in this tab, as safari commands. State lives in the
    // site's sessionStorage, so it carries over page loads within one site.
    M.rec=null;try{M.rec=JSON.parse(sessionStorage.getItem('__smcp_rec')||'null')}catch(e){}
    function rsave(){try{M.rec?sessionStorage.setItem('__smcp_rec',JSON.stringify(M.rec)):sessionStorage.removeItem('__smcp_rec')}catch(e){}}
    function rq(s){return"'"+String(s).replace(/'/g,"'\\''")+"'"}
    function radd(l,keep){var R=M.rec;if(!R||R.l.length>=500)return;R.l.push(l);if(!keep)R.la=Date.now();rsave()}
    function rsel(e){var s=selOf(e);return s?'--sel '+rq(s):null}
    function field(e){return e&&(e.tagName==='TEXTAREA'||(e.tagName==='INPUT'&&!/^(button|submit|reset|checkbox|radio|file|image|range|color|hidden)$/i.test(e.type)))}
    function rfill(e){var s=rsel(e);if(!s)return;var v=e.type==='password'?'"$PASSWORD"':rq(e.value);if(M.rec.v[s]===v)return;M.rec.v[s]=v;
      var L=M.rec.l,last=L[L.length-1];if(last&&last.indexOf('fill '+s+' ')===0)L.pop();radd('fill '+s+' '+v)}
    M.recStart=function(){M.rec={l:['go '+rq(location.href)],v:{}};rsave();return'recording in this tab: act in Safari, then `record --stop` prints the commands'};
    M.recStop=function(){var R=M.rec;M.rec=null;rsave();if(!R)throw new Error('not recording on this page (recording covers one site; it ends when the tab moves to another)');
      return'# replay: export SAFARI_TAB=<tab>; run each line\n'+R.l.map(function(l){return l.charAt(0)==='#'?l:'safari '+l}).join('\n')};
    if(window===top){
      if(M.rec){var R=M.rec,nav=R.bu&&R.la&&R.bu-R.la<4000;radd(nav?'# → '+location.href:'go '+rq(location.href),nav);R.bu=0;R.la=0;rsave()}
      addEventListener('beforeunload',function(){if(M.rec){M.rec.bu=Date.now();rsave()}},true);
      document.addEventListener('click',function(ev){if(!M.rec||!ev.isTrusted)return;
        var e=ev.target.closest&&ev.target.closest('a,button,input,select,textarea,label,summary,option,[role=button],[role=link],[role=tab],[role=menuitem],[role=option],[role=checkbox],[onclick],[tabindex]')||ev.target;
        if(field(e)||e.tagName==='SELECT'||e.tagName==='OPTION')return;
        // Enter in a form makes the browser click its submit button (a trusted click, detail 0): the recorded key covers it.
        if(ev.detail===0&&Date.now()-(M.rec.ke||0)<1000&&(e.type==='submit'||(e.tagName==='BUTTON'&&!e.getAttribute('type'))))return;var s=rsel(e);if(s)radd((ev.detail===2?'dblclick ':'click ')+s)},true);
      document.addEventListener('change',function(ev){if(!M.rec||!ev.isTrusted)return;var e=ev.target;
        if(e.tagName==='SELECT'){var s=rsel(e),o=e.options[e.selectedIndex];if(s&&o)radd('select '+s+' '+rq(o.text.trim()))}else if(field(e))rfill(e)},true);
      document.addEventListener('keydown',function(ev){if(!M.rec||!ev.isTrusted)return;var e=ev.target;
        if(ev.key==='Enter'&&(field(e)&&e.tagName!=='TEXTAREA'||e.tagName==='SELECT'||(e.tagName==='INPUT'&&/^(checkbox|radio)$/.test(e.type)))){M.rec.ke=Date.now();if(field(e))rfill(e);var s=rsel(e);if(s)radd('key Enter '+s)}else if(ev.key==='Escape')radd('key Escape')},true)}
    function clip(s,k){s=String(s==null?'':s).replace(/\s+/g,' ').trim();return s.length>k?s.slice(0,k-1)+'…':s}
    function fmt(v){if(typeof v==='string')return v;if(v instanceof Error)return v.name+': '+v.message;try{return JSON.stringify(v)}catch(e){return String(v)}}
    function push(arr,x){arr.push(x);arr.t=(arr.t||0)+1;if(arr.length>300)arr.shift()}
    // Bodies of text/JSON responses, kept for the last 50 requests.
    var BOD=new Map();
    function keep(id,ct,b){if(!/json|text|xml|javascript|html|csv/i.test(ct||''))return;BOD.set(id,{c:ct,b:String(b).slice(0,4000)});if(BOD.size>50)BOD.delete(BOD.keys().next().value)}
    function hook(){if(M.con)return false;M.con=[];M.net=[];M.nn=0;M.cur={};
      ['log','info','warn','error','debug'].forEach(function(l){var o=console[l];console[l]=function(){try{push(M.con,l+' '+[].map.call(arguments,fmt).join(' '))}catch(e){}return o.apply(console,arguments)}});
      addEventListener('error',function(e){push(M.con,'exception '+(e.message||(e.target&&(e.target.src||e.target.href))||'')+(e.filename?' @'+e.filename.split('/').pop()+':'+e.lineno:''))},true);
      addEventListener('unhandledrejection',function(e){push(M.con,'rejection '+fmt(e.reason))});
      var f=window.fetch;
      if(f)window.fetch=function(i,o){var u=typeof i==='string'?i:(i&&i.url)||String(i),m=(o&&o.method)||(i&&i.method)||'GET',t=performance.now(),id='n'+(++M.nn),args=arguments;
        var rt=route(u),tag='';if(rt){tag=' (mocked)';var k=rt.r.k;
          if(k==='block'){push(M.net,id+' '+m+' ERR '+u+' 0ms (blocked)');return Promise.reject(new TypeError('Load failed'))}
          var to=dest(rt);if(to)args=[i instanceof Request?new Request(to,i):to,o];
          if(rt.r.hq){var h=hdrs(new Headers((o&&o.headers)||(i instanceof Request?i.headers:undefined)),rt.r.hq);args=[args[0],Object.assign({},o,{headers:h})]}}
        var hs=rt&&rt.r.k==='headers'&&rt.r.hs;
        return f.apply(this,args).then(function(r){if(hs)r=new Response(r.body,{status:r.status,statusText:r.statusText,headers:hdrs(new Headers(r.headers),hs)});
          push(M.net,id+' '+m+' '+r.status+' '+u+' '+Math.round(performance.now()-t)+'ms'+tag);
          try{var ct=r.headers.get('content-type');if(/json|text|xml|javascript|html|csv/i.test(ct||''))r.clone().text().then(function(b){keep(id,ct,b)},function(){})}catch(e){}return r},
          function(e){push(M.net,id+' '+m+' ERR '+u+' '+e);throw e})};
      var xo=XMLHttpRequest.prototype.open,xs=XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open=function(m,u){this.__q=[m,u];var rt=route(u),a=[].slice.call(arguments);this.__rt=rt;
        if(rt){var to=dest(rt);if(to)a[1]=to}return xo.apply(this,a)};
      XMLHttpRequest.prototype.send=function(){var x=this,t=performance.now(),id='n'+(++M.nn),rt=x.__rt;
        if(rt&&rt.r.k==='block'){push(M.net,id+' '+x.__q[0]+' ERR '+x.__q[1]+' 0ms (blocked)');setTimeout(function(){['error','loadend'].forEach(function(e){x.dispatchEvent(new ProgressEvent(e))})},0);return}
        if(rt&&rt.r.hq)rt.r.hq.forEach(function(h){if(h[1]!=='')try{x.setRequestHeader(h[0],h[1])}catch(e){}});
        var q=x.__q;x.addEventListener('loadend',function(){if(!q)return;push(M.net,id+' '+q[0]+' '+(x.status||'ERR')+' '+q[1]+' '+Math.round(performance.now()-t)+'ms'+(rt?' (mocked)':''));
          try{if(x.responseType===''||x.responseType==='text')keep(id,x.getResponseHeader('content-type'),x.responseText)}catch(e){}},{once:true});return xs.apply(this,arguments)};
      return true}
    var STATIC=/^(img|css|link|script|font|video|audio|image|icon|stylesheet|media)$/;
    function logs(a){var fresh=hook(),net=a.kind==='network'||!!a.id,kind=net?'net':'con',arr=net?M.net:M.con,note='';
      if(net&&a.id){var b=BOD.get(a.id),l=M.net.find(function(x){return x.indexOf(a.id+' ')===0});
        if(!l)return'no request '+a.id+' in the log';
        return clip(l,300)+(b?'\n'+b.c+'\n'+b.b.slice(0,(a.limit||40)*100):'\n(no body kept: only text/JSON bodies of the last 50 requests)')}
      var from=a.new&&M.cur[kind]!=null?arr.length-Math.min(arr.length,arr.t-M.cur[kind]):0;M.cur[kind]=arr.t||0;arr=arr.slice(from);
      // With the extension, wr is every request of the tab since it started loading (from webRequest).
      if(net&&a.wr){var all=a.wr,from0=a.new?Math.min(M.wrc||0,all.length):0,hid=0;M.wrc=all.length;
        var w=all.slice(from0).filter(function(l){var t=l.split(' ')[0];if(/^(xmlhttprequest|fetch|ping|beacon)$/.test(t))return false;if(!a.pattern&&STATIC.test(t)){hid++;return false}return true});
        arr=w.concat(arr);if(hid)note='('+hid+' images/scripts/styles hidden; pass -p to include them)\n'}
      else if(net&&!M.nseen){M.nseen=1;var hid=0,res=performance.getEntriesByType('resource').filter(function(e){if(!a.pattern&&STATIC.test(e.initiatorType)){hid++;return false}return true});
        arr=res.map(function(e){return(e.initiatorType||'res')+' '+(e.responseStatus||'-')+' '+e.name+' '+Math.round(e.duration)+'ms'}).concat(arr);
        note='(lines without an id were loaded before safari first touched this page; no bodies'+(hid?'; '+hid+' images/scripts/styles hidden, pass -p to include them':'')+')\n'}
      else if(fresh)note='(capture starts now; earlier console output is not available)\n';
      if(!net&&a.level){var lv=a.level==='error'?/^(error|exception|rejection) /:/^(error|exception|rejection|warn) /;arr=arr.filter(function(l){return lv.test(l)})}
      if(a.pattern){var re;try{re=new RegExp(a.pattern,'i')}catch(e){}var p=a.pattern.toLowerCase();arr=arr.filter(function(l){return re?re.test(l):l.toLowerCase().indexOf(p)>=0})}
      var out=arr.slice(-(a.limit||30)).map(function(l){return clip(l,180)}).join('\n');
      if(a.clear){M.con.length=0;M.net.length=0;BOD.clear()}
      return note+(out||(a.new?'(nothing new)':'(no entries)'))}

    // Page dialogs would block every call until someone clicks them. Answer them here instead:
    // alert is acknowledged; confirm and prompt are dismissed unless act dialog chose otherwise.
    // Only pages the server works in are armed: everywhere else (the user's own browsing)
    // dialogs stay Safari's own. Arming reaches child frames by postMessage, and their
    // answered dialogs are reported back to the top frame.
    // The flag survives same-site navigations in the tab, so a dialog during the next load is answered too.
    M.dlg=[];M.dp=null;M.armed=false;try{M.armed=sessionStorage.getItem('__smcp_armed')==='1'}catch(e){}
    function arm(dp){M.armed=true;try{sessionStorage.setItem('__smcp_armed','1')}catch(e){}if(dp!==undefined)M.dp=dp;for(var i=0;i<frames.length;i++)try{frames[i].postMessage({__smcp:'arm',dp:dp},'*')}catch(e){}}
    addEventListener('message',function(e){var d=e.data;if(!d||typeof d!=='object')return;
      if(d.__smcp==='arm'&&e.source===parent&&window!==top)arm(d.dp);
      else if(d.__smcp==='dlg'&&window===top&&typeof d.r==='string')M.dlg.push(d.r)});
    ['alert','confirm','prompt'].forEach(function(t){var orig=window[t];window[t]=function(m,d){if(!M.armed)return orig.apply(window,arguments);
      var p=M.dp,acc=t==='alert'||(p!=null&&p!=='dismiss'),v;M.dp=null;
      if(t==='confirm')v=acc;else if(t==='prompt')v=acc?(p&&p!=='accept'?p:d==null?'':String(d)):null;
      var r=t+' '+JSON.stringify(clip(m,120))+' \u2192 '+(t==='prompt'&&acc?JSON.stringify(v):acc?'accepted':'dismissed');
      if(window===top)M.dlg.push(r);else try{top.postMessage({__smcp:'dlg',r:'(frame) '+r},'*')}catch(e){}
      return v}});
    M.arm=function(){if(!M.armed)arm()};
    function ser(v){if(v===undefined)return'undefined';if(v instanceof Element)return el(v);if(typeof v==='function')return String(v).slice(0,200);
      try{var j=JSON.stringify(v,function(k,x){return x instanceof Element?el(x):typeof x==='bigint'?String(x):x});return j===undefined?String(v):j}catch(e){return String(v)}}
    function el(e){return'<'+e.tagName.toLowerCase()+(e.id?'#'+e.id:'')+'> '+JSON.stringify(clip(e.innerText||e.textContent||e.value||'',50))}
    M.logs=logs;
    M.dlgTake=function(){return M.dlg.splice(0)};
    // Requests answered with 4xx/5xx since the counter was n, for act results.
    M.ncount=function(){return M.net?M.net.t||0:0};
    // fetch/XHR requests started after request n0 and not answered yet (older long polls do not count).
    M.nn0=function(){return M.nn||0};
    M.pend=function(n0){if(!M.net)return 0;var done=0;for(var i=M.net.length-1;i>=0;i--){var k=+M.net[i].slice(1,M.net[i].indexOf(' '));if(k>n0)done++}
      return Math.max(0,(M.nn||0)-n0-done)};
    M.fails=function(n){if(!M.net)return'';var k=Math.min(M.net.length,(M.net.t||0)-n);if(k<=0)return'';
      // Only HTTP errors: ERR (no response) is mostly an aborted beacon or a blocked tracker.
      return M.net.slice(-k).map(function(l){var p=l.split(' '),u;try{u=new URL(p[3],location.href)}catch(e){return null}
          var own=u.origin===location.origin;if(!(+p[2]>=400))return null;
          return p[0]+' '+p[1]+' '+p[2]+' '+clip(own?u.pathname+u.search:u.host+u.pathname,70)}).filter(Boolean).slice(-3).join(', ')};
    M.policy=function(p){arm(p)};
    // Page CSP may forbid compiling code here; the caller then runs it in its own world.
    M.run=function(id,code){var f;try{f=new Function('return(async function(){'+code+'\n})()')}catch(e){return e instanceof SyntaxError?'syntax: '+e.message:'csp'}
      var s=M.slots[id]={d:0};try{f().then(function(v){s.d=1;s.v=ser(v)},function(e){s.d=1;s.e=String(e)})}catch(e){s.d=1;s.e=String(e)}return'ok'};
    M.take=function(id){var s=M.slots[id];if(!s)return'{"x":1}';if(!s.d)return'{"p":1}';delete M.slots[id];return JSON.stringify(s.e?{e:s.e}:{v:s.v})};
    document.addEventListener('__smcp_q',function(e){var r;try{var q=JSON.parse(e.detail);M.arm();r={v:M[q.op].apply(null,q.a||[])}}catch(x){r={e:String(x&&x.message||x)}}
      document.dispatchEvent(new CustomEvent('__smcp_r',{detail:JSON.stringify(r)}))});
    hook();
    })()
    """#

    /// Injected once per page. Everything the tools need from the DOM lives here so a
    /// normal call is a single extension message carrying a few bytes.
    static let source = #"""
    (function(){
    if(window.__smcp)return;
    var S=window.__smcp={h:'',slots:{},con:null,net:null,last:{}};
    var R=new Map(),W=new WeakMap(),n=0;
    function ref(el){var id=W.get(el);if(!id){id='e'+(++n);W.set(el,id);R.set(id,new WeakRef(el))}return id}
    function get(id){var w=R.get(id),el=w&&w.deref();if(!w&&!(+String(id).slice(1)<=n))throw new Error('ref '+id+' is not from this page (refs die when the page changes); read again');if(!el||!el.isConnected)throw new Error('ref '+id+' is stale (page changed or element removed); call read again');return el}
    function clip(s,k){s=String(s==null?'':s).replace(/\s+/g,' ').trim();return s.length>k?s.slice(0,k-1)+'\u2026':s}
    var IR=/^(button|link|checkbox|radio|tab|menuitem|menuitemcheckbox|menuitemradio|option|switch|combobox|textbox|searchbox|slider|spinbutton|treeitem)$/;
    var SKIP={SCRIPT:1,STYLE:1,NOSCRIPT:1,TEMPLATE:1,HEAD:1,LINK:1,META:1,svg:1,SVG:1};
    var PROSE={P:1,BLOCKQUOTE:1,PRE:1,FIGCAPTION:1,DD:1,LI:2,TD:2,TH:2,DT:2};
    var TR={BUTTON:'button',SELECT:'combobox',TEXTAREA:'textbox',SUMMARY:'button',A:'link'};
    function ceRoot(el){return el.isContentEditable&&!(el.parentElement&&el.parentElement.isContentEditable)}
    function role(el){var r=el.getAttribute('role');if(r)return r;var t=el.tagName;if(ceRoot(el))return'textbox';
      if(t==='INPUT'){var y=(el.type||'text').toLowerCase();return y==='checkbox'||y==='radio'||y==='file'?y:/^(submit|button|reset|image)$/.test(y)?'button':y==='range'?'slider':y==='search'?'searchbox':'textbox'}
      return TR[t]||t.toLowerCase()}
    function native(el){var t=el.tagName;return t==='BUTTON'||t==='SELECT'||t==='TEXTAREA'||t==='SUMMARY'||(t==='A'&&el.hasAttribute('href'))||(t==='INPUT'&&el.type!=='hidden')}
    function secret(el){return (el.type||'').toLowerCase()==='password'||/cc-|one-time|password/.test(el.getAttribute('autocomplete')||'')}
    function sib(el,fwd){var s='',d=fwd?'nextSibling':'previousSibling';
      for(var n=el[d];n;n=n[d]){if(n.nodeType===1&&(/^(INPUT|BR|SELECT|TEXTAREA|BUTTON)$/.test(n.tagName)||n.querySelector('input,select,textarea,button')))break;
        if(n.nodeType===1||n.nodeType===3)s=fwd?s+n.textContent:n.textContent+s;if(s.trim().length>80)break}
      return s.replace(/\s+/g,' ').trim()}
    function name(el,k){var a=el.getAttribute('aria-label');if(a)return clip(a,k);
      var lb=el.getAttribute('aria-labelledby');if(lb){var s=lb.split(/\s+/).map(function(i){var e=document.getElementById(i);return e?e.textContent:''}).join(' ');if(s.trim())return clip(s,k)}
      var t=el.tagName;
      if(ceRoot(el))return clip(el.getAttribute('aria-placeholder')||el.getAttribute('data-placeholder')||el.title||'',k);
      if(t==='INPUT'&&/^(submit|button|reset)$/.test(el.type))return clip(el.value,k);
      if(t==='INPUT'||t==='SELECT'||t==='TEXTAREA'){if(el.labels&&el.labels[0])return clip(el.labels[0].textContent,k);
        if(el.placeholder||el.title)return clip(el.placeholder||el.title,k);
        // Unlabelled: the text right after the box (or before it), else the parent's if it holds only this box.
        if(/^(checkbox|radio)$/.test(el.type)){var sx=sib(el,1)||sib(el,0);if(sx)return clip(sx,k);
          var pe=el.parentElement,px=pe&&(pe.innerText||'').trim();if(px&&px.length<=80&&pe.querySelectorAll('input').length===1)return clip(px,k)}
        return clip(el.name||el.id||'',k)}
      if(t==='IMG')return clip(el.alt||el.title||'',k);
      var x=el.innerText||el.textContent||el.title;
      if(!x||!x.trim()){var im=el.querySelector('img[alt]');x=(im&&im.alt)||iconName(el)||(el.getAttribute('href')||'').split(/[?#]/)[0].split('/').filter(Boolean).pop()||el.id||String(el.getAttribute('class')||'').split(/\s+/)[0]||''}
      if(/(^|[\s_-])(danger|delete|remove|destroy|trash)([\s_-]|$)/i.test(String(el.getAttribute('class')||''))&&!/delete|remove|trash|danger/i.test(x))x+=' (danger)';
      return clip(x,k)}
    // A control with no text: what its icon or test hooks say (a trash icon, data-test="delete").
    var ICONSTOP=/^(solid|regular|light|thin|brands|duotone|sharp|fw|lg|xl|xs|sm|[0-9]+x|spin|pulse|inverse|border|pull|stack|outlined|round|filled|two|tone|icon|icons|fill|line)$/;
    function iconName(el){
      var d=el.querySelector('[aria-label],[title]');if(d){var v=d.getAttribute('aria-label')||d.getAttribute('title');if(v&&v.trim())return v}
      var st=el.querySelector('svg title');if(st&&st.textContent.trim())return st.textContent;
      var dt=el.getAttribute('data-test')||el.getAttribute('data-testid')||el.getAttribute('data-qa')||el.getAttribute('data-cy');if(dt)return dt.replace(/[-_]+/g,' ');
      var cs=[el].concat([].slice.call(el.querySelectorAll('i,svg,span,use,em')));
      for(var i=0;i<cs.length&&i<12;i++){var c=cs[i],di=c.getAttribute('data-icon');if(di)return di.replace(/[-_]+/g,' ');
        var txt=String(c.getAttribute('class')||'')+' '+(c.getAttribute('href')||c.getAttribute('xlink:href')||''),re=/(?:^|[\s#])(?:fa[srlbdt]?|fas|far|bi|icon|icons|glyphicon|ti|ri|lucide|mdi|ion|feather|octicon|la|las)[-_]([a-z][a-z0-9-]*)/gi,m;
        while((m=re.exec(txt))){var w=m[1].toLowerCase();if(!ICONSTOP.test(w))return w.replace(/-/g,' ')}}
      return ''}
    function state(el){var t=el.tagName,s='';
      if(t==='INPUT'||t==='TEXTAREA'||t==='SELECT'){var y=(el.type||'').toLowerCase();
        if(y==='checkbox'||y==='radio'){if(el.checked)s+=' checked'}
        else if(!/^(submit|button|reset|image)$/.test(y)){var v;if(secret(el))v=el.value?'\u2022\u2022\u2022':'';else if(t==='SELECT'){var o=el.selectedOptions[0];v=o?o.text:''}else v=el.value;if(v)s+=' ='+JSON.stringify(VM>60?String(v).slice(0,VM):clip(v,VM))}}
      if(ceRoot(el)){var cv=clip(el.innerText,VM);s+=' ='+JSON.stringify(cv)}
      if(el.disabled||el.getAttribute('aria-disabled')==='true')s+=' disabled';
      var x=el.getAttribute('aria-expanded');if(x)s+=x==='true'?' expanded':' collapsed';
      if(el.getAttribute('aria-selected')==='true'||el.getAttribute('aria-checked')==='true'||el.getAttribute('aria-current'))s+=' selected';
      return s}
    function desc(el){return ref(el)+' '+role(el)+' '+JSON.stringify(name(el,50))}

    function scan(o){
      var out=[],c=0,all=o.mode==='all',vw=innerWidth,vh=innerHeight;
      function rec(el,inI,noText){
        if(++c>6000)return;
        var t=el.tagName;if(SKIP[t]||el.getAttribute('aria-hidden')==='true')return;
        var shown=true;
        if(el.checkVisibility&&!el.checkVisibility({visibilityProperty:true,checkVisibilityCSS:true})){if(getComputedStyle(el).display!=='contents')return;shown=false}
        var r=shown?el.getBoundingClientRect():null;
        var vis=shown&&(r.width>0||r.height>0),inv=vis&&r.bottom>0&&r.right>0&&r.top<vh&&r.left<vw,ok=vis&&(o.full||inv);
        var ro=el.getAttribute('role'),leaf=native(el)||(ro&&IR.test(ro)),ti=el.getAttribute('tabindex');
        // A role-only control that holds real ones (a menuitem <li> with its dropdown links): list those too.
        var hold=leaf&&!native(el)&&!!el.querySelector('a,button,input,select,textarea,[role=menuitem],[role=option],[role=link],[role=button]');if(hold)leaf=false;
        var I=hold||leaf||el.hasAttribute('onclick')||(ti!==null&&ti!=='-1')||(el.isContentEditable&&!(el.parentElement&&el.parentElement.isContentEditable));
        // A clickable-looking element; inside a listed control only an <a> without href (dropdown items).
        if(!I&&inI&&t==='A'&&ok)I=true;
        if(!I&&(!inI||t==='A')&&ok&&el.children.length<6&&t!=='BODY'&&t!=='HTML'&&getComputedStyle(el).cursor==='pointer')I=true;
        if(I&&vis&&!ok)o.off=(o.off||0)+1;
        if(I&&ok){var nm=name(el,leaf?80:50);out.push({el:el,inv:inv,k:role(el)+' '+nm,nm:nm,s:ref(el)+' '+role(el)+' '+JSON.stringify(nm)+state(el)});if(leaf)return;inI=true}
        else if(I&&leaf)return;
        else if(all&&ok&&/^H[1-6]$/.test(t)){out.push({el:el,inv:inv,s:ref(el)+' '+t.toLowerCase()+' '+JSON.stringify(name(el,120))});return}
        else if(all&&ok&&t==='IMG'){if(el.alt)out.push({s:'img '+JSON.stringify(clip(el.alt,80))});return}
        else if(all&&ok&&!inI&&!el.querySelector('slot')&&(PROSE[t]===1||(PROSE[t]===2&&!el.querySelector('a[href],button,input,select,textarea')))){var p=clip(el.innerText,400);if(p.length>1)out.push({s:p,tel:el});if(!o.links)return;noText=true}
        // A slot shows the host's children assigned to it (innerText of the shadow side is empty).
        var sl=t==='SLOT'&&el.assignedNodes({flatten:true}),kids=sl&&sl.length?sl:el.shadowRoot?el.shadowRoot.childNodes:el.childNodes;
        for(var i=0;i<kids.length;i++){var k=kids[i];
          if(k.nodeType===1)rec(k,inI,noText);
          else if(all&&ok&&!I&&!noText&&k.nodeType===3){var x=k.nodeValue.trim();if(x.length>1||/[0-9A-Za-z]/.test(x))out.push({s:clip(x,160),tel:el})}}
      }
      rec(o.root||document.body,false);ctx(out);return out}
    // Controls with the same role and name (three "Add to cart"): name the part of the page each is in,
    // from the first text line of its largest ancestor that holds no other one of them.
    function ctx(out){var g=new Map();out.forEach(function(x){if(x.k){var l=g.get(x.k);if(l)l.push(x);else g.set(x.k,[x])}});
      g.forEach(function(l){if(l.length<2||l.length>30)return;var els=l.map(function(x){return x.el});
        l.forEach(function(x){var card=null;for(var p=x.el.parentElement,i=0;p&&p!==document.body&&i<10;p=p.parentElement,i++){if(els.some(function(e){return e!==x.el&&p.contains(e)}))break;card=p}
          if(!card)return;var ln=(card.innerText||'').split('\n').map(function(t){return t.trim()}).filter(function(t){return t.length>1&&t!==x.nm})[0];
          if(ln)x.s+=' (in '+JSON.stringify(clip(ln,40))+')'})})}

    // Lines are matched by ref when they have one, else by their text.
    function dk(l){var m=/^(e\d+) /.exec(l);return m?m[1]:l}
    function diff(o,b){var om=new Map(),out=[],same=0;
      o.split('\n').forEach(function(l){var k=dk(l),v=om.get(k);if(v)v.push(l);else om.set(k,[l])});
      b.split('\n').forEach(function(l){var k=dk(l),v=om.get(k),p=v&&v.shift();if(v&&!v.length)om.delete(k);
        if(p===undefined)out.push('+ '+l);else if(p===l)same++;else out.push('~ '+l)});
      var gone=[];om.forEach(function(v,k){v.forEach(function(l){if(k===l)out.push('- '+clip(l,80));else gone.push(k)})});
      if(gone.length)out.push('- '+gone.join(' '));
      return(out.length?out.join('\n')+'\n':'no changes ')+'('+same+' unchanged)'}

    // Markdown of the readable content. Links become text[n] with the URLs listed once at the end.
    var BLK={P:1,DIV:1,SECTION:1,ARTICLE:1,MAIN:1,HEADER:1,FOOTER:1,NAV:1,ASIDE:1,FORM:1,FIELDSET:1,FIGURE:1,FIGCAPTION:1,BLOCKQUOTE:1,DL:1,DT:1,DD:1,ADDRESS:1,DETAILS:1,SUMMARY:1,HR:1,TR:1,CAPTION:1};
    var NOISE={NAV:1,HEADER:1,FOOTER:1,ASIDE:1,navigation:1,banner:1,contentinfo:1,complementary:1,search:1};
    function short(h){var u;try{u=new URL(h,location.href)}catch(e){return''}
      if(!/^(https?|file):$/.test(u.protocol))return'';return u.origin===location.origin?(u.pathname+u.search+u.hash):u.href}
    function md(root,fit){
      var lines=[],U=new Map(),buf='',pf='',ind='',c=0,il=0;
      function flush(){var t=buf.replace(/[ \t\n\r ]+/g,' ').trim();buf='';if(t){lines.push(pf+t);pf=ind}}
      var here=location.pathname+location.search;
      function url(h){var s=short(h);if(!s||s.indexOf(here+'#')===0||s[0]==='#')return 0;if(!U.has(s))U.set(s,U.size+1);return U.get(s)}
      function kids(el){var s=el.tagName==='SLOT'&&el.assignedNodes({flatten:true});return s&&s.length?s:el.shadowRoot?el.shadowRoot.childNodes:el.childNodes}
      function inner(el){var b=buf;buf='';il++;walk(el);il--;var t=buf.replace(/[ \t\n\r ]+/g,' ').trim();buf=b;return t}
      function walk(n){var ks=kids(n);for(var i=0;i<ks.length;i++)node(ks[i])}
      function node(n){
        if(n.nodeType===3){buf+=n.nodeValue;return}
        if(n.nodeType!==1||++c>20000)return;
        var t=n.tagName,ro=n.getAttribute('role');
        // Field values, so a cart's quantities or a form's contents show in the text.
        if((t==='INPUT'||t==='SELECT'||t==='TEXTAREA')&&(!n.checkVisibility||n.checkVisibility())){var y=(n.type||'').toLowerCase();
          if(y==='checkbox'||y==='radio')buf+=n.checked?' [x] ':' [ ] ';
          else if(!/^(hidden|submit|button|reset|image|file)$/.test(y)){var v=secret(n)?(n.value?'\u2022\u2022\u2022':''):t==='SELECT'?(n.selectedOptions[0]?n.selectedOptions[0].text:''):n.value;if(v)buf+=' [='+clip(v,40)+'] '}
          return}
        if(SKIP[t]||/^(INPUT|SELECT|TEXTAREA|BUTTON|OPTION|IFRAME|CANVAS|VIDEO|AUDIO|DIALOG)$/.test(t)||n.getAttribute('aria-hidden')==='true')return;
        if(n.checkVisibility&&!n.checkVisibility({visibilityProperty:true,checkVisibilityCSS:true})&&getComputedStyle(n).display!=='contents')return;
        if(n!==root&&(t==='NAV'||ro==='navigation'))return;
        if(fit&&(NOISE[t]||NOISE[ro]))return;
        // Formatting inside editors, so bold or italic set there can be checked with text.
        var FM=n.isContentEditable&&{STRONG:['**','**'],B:['**','**'],EM:['_','_'],I:['_','_'],U:['<u>','</u>'],S:['~~','~~']}[t];
        if(FM){buf+=FM[0];walk(n);buf+=FM[1];return}
        if(il){if(t==='IMG'){if(n.alt)buf+=' '+n.alt+' '}else{walk(n);if(BLK[t]||/^(LI|TD|TH)$/.test(t))buf+=' '}return}
        var h=/^H([1-6])$/.exec(t);
        if(h){flush();pf=ind+'#'.repeat(+h[1])+' ';walk(n);flush();pf=ind;return}
        if(t==='BR'){buf+=' ';return}
        if(t==='IMG'){if(n.alt&&n.closest('a'))buf+=' '+n.alt+' ';return}
        if(t==='PRE'){flush();lines.push(ind+'```');String(n.innerText).slice(0,3000).replace(/\n+$/,'').split('\n').forEach(function(l){lines.push(ind+l)});lines.push(ind+'```');return}
        if(t==='CODE'){var x=n.textContent.trim();if(x)buf+=' `'+clip(x,200)+'` ';return}
        if(t==='A'&&n.hasAttribute('href')){var b=inner(n),k=b&&url(n.getAttribute('href'));buf+=' '+b+(k?'['+k+']':'')+' ';return}
        if(t==='UL'||t==='OL'){flush();var sv=ind,j=0,ks=kids(n);
          for(var i=0;i<ks.length;i++){var li=ks[i];if(li.nodeType!==1)continue;if(li.tagName!=='LI'){node(li);continue}
            j++;pf=sv+(t==='OL'?j+'. ':'- ');ind=sv+'  ';walk(li);flush();ind=sv;pf=sv}
          return}
        if(t==='TABLE'&&!n.querySelector('table')&&!layout(n)){flush();var rows=[].slice.call(n.rows),cols=0;
          rows.slice(0,60).forEach(function(r,ri){var cs=[].map.call(r.cells,function(x){return clip(inner(x),200).replace(/\|/g,'\\|')});
            if(!cs.join(''))return;lines.push(ind+'| '+cs.join(' | ')+' |');if(!cols){cols=cs.length;lines.push(ind+'|'+' --- |'.repeat(cols))}});
          if(rows.length>60)lines.push(ind+'(… '+(rows.length-60)+' more rows)');return}
        var blk=BLK[t]||t==='LI'||(t.indexOf('-')>0&&/^(block|flex|grid|list-item|table)/.test(getComputedStyle(n).display));
        if(blk)flush();walk(n);if(blk)flush();else if(t==='TD'||t==='TH')buf+=' '}
      node(root);flush();return{lines:lines,urls:[...U.keys()]}}
    // A table used for page layout (long cells holding paragraphs, as on Hacker News) is read
    // as text, so its cells are not cut short like data cells.
    function layout(n){return [].some.call(n.querySelectorAll('td,th'),function(c){return c.textContent.length>200&&!!c.querySelector('div,p,ul,ol,pre,blockquote')})}
    function text(root){
      if(root)return md(root,false);
      // One article is the content; several (search results, feeds) are items of a list.
      var m=document.querySelector('main,[role=main]'),as=m?[]:document.querySelectorAll('article');
      if(!m&&as.length===1)m=as[0];
      var r=m&&md(m,false);
      if(r&&r.lines.join('').length>=200)return r;
      r=md(document.body,true);return r.lines.join('').length>=200?r:md(document.body,false)}
    function foot(m,used){var f=[];m.urls.forEach(function(u,i){if(!used||used.has(i+1))f.push('['+(i+1)+']: '+u)});return f.length?'\n\n'+f.join('\n'):''}
    // BM25 over the markdown lines; the best ones are returned in page order, each under its nearest heading.
    // -q "/re/flags" is a regular expression; anything else is words.
    function qshow(q){return /^\/.+\/[a-z]*$/s.test(q||'')?q:JSON.stringify(q)}
    function qre(q){var m=/^\/(.+)\/([a-z]*)$/s.exec(q||'');if(!m)return null;try{return new RegExp(m[1],m[2].replace(/[gy]/g,''))}catch(e){throw new Error('bad regular expression '+q+': '+e.message)}}
    function rank(m,q,max){
      var tok=function(s){return s.toLowerCase().match(/[\p{L}\p{N}]+/gu)||[]},L=m.lines,N=L.length,df={},docs=[],avg=0;
      L.forEach(function(l){var tf={},ts=tok(l);ts.forEach(function(w){tf[w]=(tf[w]||0)+1});for(var w in tf)df[w]=(df[w]||0)+1;docs.push({tf:tf,n:ts.length});avg+=ts.length});
      avg=avg/Math.max(N,1)||1;var qs=tok(q),sc=[],re=qre(q),lim=re?500:30;
      if(re)L.forEach(function(l,i){if(re.test(l))sc.push({i:i,s:1})});else docs.forEach(function(d,i){var s=0;if(/^\s*#/.test(L[i]))return;qs.forEach(function(w){var f=d.tf[w];if(!f)return;var idf=Math.log(1+(N-df[w]+0.5)/(df[w]+0.5));s+=idf*f*2.2/(f+1.2*(0.25+0.75*d.n/avg))});if(s>0)sc.push({i:i,s:s})});
      if(!sc.length)return'no text matches '+qshow(q);
      if(!re)sc.sort(function(x,y){return y.s-x.s});
      var pick=new Set(),size=0;
      for(var k=0;k<sc.length&&k<lim;k++){var len=L[sc[k].i].length;if(size+len>max&&pick.size)break;pick.add(sc[k].i);size+=len}
      var out=[],hd=-1,prev=-2;
      [...pick].sort(function(x,y){return x-y}).forEach(function(i){
        for(var h=i;h>=0;h--)if(/^\s*#/.test(L[h]))break;
        if(h>=0&&h!==hd&&h!==i){out.push(L[h]);hd=h}else if(prev>=0&&i!==prev+1)out.push('…');
        out.push(L[i]);prev=i});
      return out.join('\n')}
    function links(root,q){
      var seen=new Set(),inn=[],re=qre(q),ws=q&&!re?q.toLowerCase().split(/\s+/).filter(Boolean):[];
      root.querySelectorAll('a[href]').forEach(function(el){var u=short(el.getAttribute('href'));if(!u||seen.has(u))return;
        if(el.checkVisibility&&!el.checkVisibility({visibilityProperty:true,checkVisibilityCSS:true}))return;
        var nm=name(el,60),hay=(nm+' '+u).toLowerCase();if(re?!re.test(nm+' '+u):ws.some(function(w){return hay.indexOf(w)<0}))return;
        seen.add(u);inn.push(ref(el)+' '+JSON.stringify(nm)+' '+u)});
      return inn.join('\n')||(q?'no link matches '+qshow(q):'(no links)')}

    // One window of a long result. The continuation note starts with \x1e: the client prints
    // such lines to stderr, so data piped to a file stays clean. max_chars 0 = everything.
    function chunk(body,a){var off=a.offset||0,max=a.max_chars===0?1/0:(a.max_chars||6000),tot=body.length,cut=body.slice(off,off+max);
      if(off+max<tot){var nl=cut.lastIndexOf('\n');if(nl>max*0.6)cut=cut.slice(0,nl);cut+='\n\x1e… '+(tot-off-cut.length)+' more chars; --offset '+(off+cut.length)+' (or --max 0, -o FILE)'}
      return cut}

    // Rows of the biggest visible table (or of --rows matches) as TSV or JSON, with each row's
    // first link and data-id when it has them.
    function table(a){
      var root=a.ref?get(a.ref):a.selector?document.querySelector(a.selector):null;
      if(a.selector&&!root)throw new Error('selector matched nothing');
      function vis(e){return e.getClientRects().length>0}
      // Cell text; a cut-off link text ("A Light in the ...") is completed from its title attribute.
      // Buttons inside a cell (Add to basket, Star) are left out; noscript markup never counts.
      function ct(e){var t=(e.innerText!=null?e.innerText:e.textContent||'').replace(/\s+/g,' ').trim();
        if(t&&!/^(BUTTON|SELECT)$/.test(e.tagName))e.querySelectorAll('button,[role=button],input[type=submit],input[type=button]').forEach(function(b){
          var v=(b.innerText||b.value||'').replace(/\s+/g,' ').trim();if(v)t=t.replace(v,'').replace(/\s+/g,' ').trim()});
        if(/(\.\.\.|…)/.test(t))e.querySelectorAll('[title]').forEach(function(x){var v=(x.innerText||'').replace(/\s+/g,' ').trim(),b=v.replace(/\s*(\.\.\.|…)$/,''),ti=x.getAttribute('title').replace(/\s+/g,' ').trim();
          if(b&&b!==v&&ti.indexOf(b)===0&&t.indexOf(v)>=0)t=t.replace(v,ti)});
        return t}
      function cells(el){var c=[].filter.call(el.children,vis);return(c.length?c:[el]).map(ct)}
      // Siblings sharing tag and first class (a product grid, search results), each followed down
      // through single-child wrappers (li > article). Menus fall out: one cell, short text, or nav.
      function cards(){var skip='nav,header,footer,select,[role=navigation],[role=menu],[role=menubar],[role=tablist]',top=null;
        function sig(e){var c=e.classList&&e.classList[0];return e.tagName.toLowerCase()+(c?'.'+CSS.escape(c):'')}
        function down(e){for(var c;(c=[].filter.call(e.children,vis)).length===1&&c[0].children.length;)e=c[0];return e}
        [root||document.body].concat([].slice.call((root||document.body).querySelectorAll('*'))).forEach(function(p){
          if(p.children.length<3)return;var g={},big=null;
          [].forEach.call(p.children,function(c){var k=sig(c);(g[k]=g[k]||[]).push(c);if(!big||g[k].length>g[big].length)big=k});
          var its=g[big].filter(vis);if(its.length<3||p.closest(skip))return;
          var rs=its.map(function(it){var el=down(it);return{el:el,it:it,c:cells(el)}}),full=0,ln=0,lk=0;
          rs.forEach(function(r){var n=r.c.filter(Boolean).length;if(n>=2)full++;ln+=r.c.join(' ').length;if(r.el.querySelector('a[href]')||r.el.closest('a[href]'))lk++});
          if(full*2<=rs.length||ln/rs.length<8)return;
          var sc=rs.length*Math.min(6,rs.reduce(function(s,r){return s+r.c.filter(Boolean).length},0)/rs.length)*(lk*2>rs.length?1.5:1);
          if(!top||sc>top.sc)top={sc:sc,rows:rs,p:p}});
        if(!top)return null;
        // A selector for --rows / crawl that matches these cards and nothing else.
        var e0=top.rows[0].el,it=top.rows[0].it,n=top.rows.length,pin=false,sel=sig(e0);
        function cnt(q){try{return[].filter.call(document.querySelectorAll(q),vis).length}catch(x){return-1}}
        if(cnt(sel)!==n){var q=sig(top.p)+' > '+sig(it)+(it!==e0?' > '+sig(e0):'');if(cnt(q)===n)sel=q;else sel=null}
        if(sel)pin=true;else sel=sig(e0);
        return{rows:top.rows,sel:sel,pin:pin}}
      var head=null,rows=[],src;
      if(a.rows){
        var els=[].filter.call((root||document).querySelectorAll(a.rows),vis);
        if(!els.length)throw new Error('no visible element matches '+a.rows);
        rows=els.map(function(el){return{el:el,c:cells(el)}});src=a.rows;
      }else{
        var t=root&&root.tagName==='TABLE'?root:null,best=0,cs;
        if(!t)(root||document).querySelectorAll('table').forEach(function(x){var n=[].filter.call(x.rows,vis).length;if(n>best){best=n;t=x}});
        // A real table wins; without one (or with only a tiny one), repeated cards.
        if(!t||best<3&&!(root&&root.tagName==='TABLE'))cs=cards();
        if(cs){rows=cs.rows;src='cards '+cs.sel+(cs.pin?' (guessed; pin with --rows \''+cs.sel+'\')':' (guessed)')}
        else if(!t)throw new Error('no table or repeated cards here; give --rows CSS (one match per row)');
      }
      // Card columns are named after the first card's cells (h3, price_color), when those differ.
      if(src&&rows.length){var hn=[].filter.call(rows[0].el.children,vis).map(function(e){return(e.classList[0]||e.tagName.toLowerCase()).replace(/[\t\n]/g,'')});
        if(hn.length>1&&new Set(hn).size===hn.length)head=hn}
      if(!src){
        // Expand colspan and rowspan into a plain grid, so columns line up. Leading header rows
        // (in thead, or all th) are merged into one name per column ("Height m").
        var hold=[],heads=[];
        [].forEach.call(t.rows,function(tr){if(!vis(tr))return;var cs=[],col=0,n=tr.cells.length;
          function carry(){while(hold[col]&&hold[col].left>0){cs[col]=hold[col].t;hold[col].left--;n++;col++}}
          carry();[].forEach.call(tr.cells,function(td){var sp=Math.min(td.colSpan||1,50),rs=Math.min(td.rowSpan||1,1000),tx=ct(td);
            for(var k=0;k<sp;k++){cs[col]=tx;hold[col]=rs>1?{left:rs-1,t:tx}:null;col++;carry()}});
          if(!rows.length&&(tr.parentNode.tagName==='THEAD'||[].every.call(tr.cells,function(c){return c.tagName==='TH'})))heads.push(cs);else rows.push({el:tr,c:cs,n:n})});
        if(heads.length)head=[];heads.forEach(function(h){h.forEach(function(x,i){x=x.replace(/\[[^\]]{1,12}\]/g,'').trim();if(x&&head[i]!==x&&(head[i]||'').split(' ').pop()!==x)head[i]=head[i]?head[i]+' '+x:x})});
        src='table'+(t.id?'#'+t.id:t.className?'.'+String(t.className).trim().split(/\s+/)[0]:'');
      }
      // Separator and ad rows have far fewer cells than the usual row.
      var cnt={},w=0;rows.forEach(function(r){cnt[r.c.length]=(cnt[r.c.length]||0)+1});for(var k in cnt)if(!w||cnt[k]>cnt[w])w=+k;
      rows=rows.filter(function(r){return(r.n||r.c.length)*2>w&&r.c.some(Boolean)});
      if(!rows.length)throw new Error('the table has no data rows');
      rows.forEach(function(r){while(r.c.length<w)r.c.push('');r.c.length=w;
        var id=r.el.getAttribute('data-id')||'';if(!id)[].some.call(r.el.attributes,function(x){if(/^data-[\w-]*id$/i.test(x.name)&&x.value){id=x.value;return true}});r.id=id;
        var l=[].find.call(r.el.querySelectorAll('a[href]'),function(x){var h=x.getAttribute('href');return h&&h[0]!=='#'&&!/^javascript:/i.test(h)});r.l=l?l.href:''});
      head=(head||[]).slice(0,w);while(head.length<w)head.push('');
      // Columns empty in every row (images, checkboxes) are left out.
      var keep=[];for(var i=0;i<w;i++)if(rows.some(function(r){return r.c[i]}))keep.push(i);
      var names=keep.map(function(i,j){return head[i]||'c'+(j+1)}),hasId=rows.some(function(r){return r.id}),hasL=rows.some(function(r){return r.l});
      if(hasL)names.push('link');if(hasId)names.push('id');
      var out=rows.map(function(r){var v=keep.map(function(i){return r.c[i]});if(hasL)v.push(r.l);if(hasId)v.push(r.id);return v});
      var body;
      if(a.json)body=JSON.stringify(out.map(function(v){var o={};names.forEach(function(n,i){o[n]=v[i]});return o}));
      else body=[names].concat(out).map(function(v){return v.map(function(c){return String(c).replace(/[\t\r\n]+/g,' ')}).join('\t')}).join('\n');
      return chunk(body,a)+'\n\x1e'+rows.length+' rows from '+src}

    var VM=60;
    function read(a){
      var root=a.ref?get(a.ref):a.selector?document.querySelector(a.selector):null;
      if(a.selector&&!root)throw new Error('selector matched nothing');
      // A read scoped to one field shows its whole value; elsewhere values are cut at 60 chars.
      VM=root&&(/^(INPUT|TEXTAREA|SELECT)$/.test(root.tagName)||ceRoot(root))?20000:60;
      var body,md0=null,so=null,qm=a.query&&a.mode!=='text'&&a.mode!=='links';
      if(qm){
        var q=a.query.toLowerCase().trim(),ws=q.split(/\s+/).filter(Boolean),hits=[],re=qre(a.query);
        var wb=ws.map(function(w){return new RegExp('(^|[^a-z0-9])'+w.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+'($|[^a-z0-9])')});
        scan({mode:'all',full:true,links:true,root:root}).forEach(function(x){var el=x.el;if(!el&&!x.tel)return;
          var nm=x.s.toLowerCase(),at=!el?'':((el.id||'')+' '+(el.getAttribute('name')||'')+' '+(el.getAttribute('placeholder')||'')+' '+(el.getAttribute('href')||'').replace(/^[a-z]+:\/\/[^\/]+/i,'')+' '+(el.title||'')).toLowerCase();
          if(re){var nq=el&&/"((?:[^"\\]|\\.)*)"/.exec(x.s);if(!(nq&&re.test(nq[1]))&&!re.test(x.s)&&!(at&&re.test(at)))return;x.all=true;if(!el){var r0=x.tel.getBoundingClientRect();x.inv=r0.bottom>0&&r0.top<innerHeight}hits.push({sc:-hits.length,x:x});return}
          var sc=0,hit=0;ws.forEach(function(w,i){if(wb[i].test(nm)){sc+=3;hit++}else if(nm.indexOf(w)>=0){sc+=2;hit++}else if(at.indexOf(w)>=0){sc++;hit++}});
          if(!hit)return;if(nm.indexOf(q)>=0)sc+=2;if(nm.indexOf('"'+q+'"')>=0)sc+=4;x.all=hit===ws.length;
          if(!el){var r=x.tel.getBoundingClientRect();x.inv=r.bottom>0&&r.top<innerHeight;sc-=0.25}
          if(x.inv)sc+=0.5;hits.push({sc:sc,x:x})});
        if(hits.some(function(h){return h.x.all}))hits=hits.filter(function(h){return h.x.all});
        hits.sort(function(p,r){return r.sc-p.sc});
        body=hits.slice(0,10).map(function(h){var x=h.x;return(x.el?x.s:ref(x.tel)+' text '+JSON.stringify(clip(x.s,100)))+(x.inv?'':' (offscreen)')}).join('\n')||'no match for '+qshow(a.query);
      }else if(a.mode==='text'){
        md0=text(root);body=a.query?rank(md0,a.query,a.max_chars||6000):md0.lines.join('\n')||(root?'(no text there: try read --all, or shot for images and canvas)':'(no text on the page)');
      }else if(a.mode==='links'){
        body=links(root||document.body,a.query);
      }else{
        var so={mode:a.mode,full:a.full,root:root};
        body=scan(so).map(function(x){return x.s}).join('\n')||(a.full?'(nothing found)':'(nothing in viewport; scroll or use --full)');
      }
      if(!qm){
        var k=(a.mode||'interactive')+'|'+(a.ref||a.selector||'')+'|'+(a.full?1:0)+'|'+(a.query||''),old=S.last[k];S.last[k]=body;
        if(a.diff)body=old==null?'(first read of this page in this mode; full result)\n'+body:diff(old,body)}
      var cut=chunk(body,a);
      // Each chunk lists the URLs of the [n] links it contains.
      if(md0){var used=new Set();cut.replace(/\[(\d+)\]/g,function(_,n){used.add(+n)});cut+=foot(md0,used)}
      // Say what this read left out, so the model does not go looking for it with js.
      if(so&&so.off)cut+='\n(+'+so.off+' controls off-screen: --full or -q)';
      var de=document.documentElement;
      return(document.title?clip(document.title,80)+' | ':'')+location.href.slice(0,200)+' | scroll '+Math.round(scrollY)+'/'+Math.max(0,de.scrollHeight-innerHeight)+(document.readyState==='complete'?'':' | still loading')+'\n'+cut}

    function deep(x,y){var e=document.elementFromPoint(x,y);while(e&&e.shadowRoot){var n=e.shadowRoot.elementFromPoint(x,y);if(!n||n===e)break;e=n}return e}
    function inside(el,c){for(;c;c=c.parentNode||c.host)if(c===el)return true;return false}
    function target(a){var el;
      if(!a.ref&&a.selector){var ms=document.querySelectorAll(a.selector);el=ms[0];if(!el)throw new Error('no element matches '+a.selector);
        if(ms.length>1)S.note=' (1 of '+ms.length+' matches)';a.ref=ref(el)}
      if(a.ref){el=get(a.ref);var r=el.getBoundingClientRect();
        if(r.top<0||r.left<0||r.bottom>innerHeight||r.right>innerWidth){el.scrollIntoView({block:'center',inline:'center'});r=el.getBoundingClientRect()}
        // Events go to the innermost element under the pointer, as a real click would, so
        // a link or button nested in the referenced element still activates.
        var x=r.left+r.width/2,y=r.top+r.height/2,h=deep(x,y);
        return{el:el,to:h&&inside(el,h)?h:el,x:x,y:y,r:r}}
      if(a.x!=null&&a.y!=null){el=deep(a.x,a.y);if(!el)throw new Error('nothing at '+a.x+','+a.y);return{el:el,to:el,x:a.x,y:a.y}}
      return null}
    function need(a){var t=target(a);if(!t)throw new Error('pass a ref, --sel or --xy (find the element with read -q "…")'+(a.action==='click'&&a.text!=null?'; --answer on click only answers a dialog':''));return t}
    function mev(el,type,x,y,more){var P=type.indexOf('pointer')===0,C=P&&window.PointerEvent?PointerEvent:MouseEvent;
      var i={bubbles:!/enter|leave/.test(type),cancelable:true,composed:true,view:window,clientX:x,clientY:y,screenX:x+screenX,screenY:y+screenY,button:0,buttons:/down/.test(type)?1:0,detail:1};
      if(P){i.pointerId=1;i.pointerType='mouse';i.isPrimary=true}
      if(more)for(var k in more)i[k]=more[k];
      return el.dispatchEvent(new C(type,i))}
    function watch(){S.fx=0;var mo=new MutationObserver(hit),ev=['input','change','scroll','hashchange','submit'];
      function stop(){mo.disconnect();ev.forEach(function(e){removeEventListener(e,hit,true)})}
      function hit(){S.fx=1;stop()}
      mo.observe(document,{subtree:true,childList:true,attributes:true,characterData:true});ev.forEach(function(e){addEventListener(e,hit,true)});setTimeout(stop,3000)}
    // While Safari's window is in the background (the usual case here), focus() moves focus
    // without firing focus/blur. Forms that commit on blur (Angular) then never see the
    // value, so send those events ourselves, as moving focus would.
    // Like a real press, focus goes to the nearest focusable ancestor, or leaves the old element;
    // a cancelled mousedown (keep) moves nothing. p is the focus from before the action: the
    // page may have moved focus itself meanwhile (sliders do, in mousedown), silently too.
    function foc(el,p,keep){if(p===undefined)p=document.activeElement;
      if(!keep){var f=el;while(f&&!(f.tabIndex>=0||f.isContentEditable))f=f.parentElement||(f.getRootNode&&f.getRootNode().host);
        if(f!==document.activeElement){if(f)try{f.focus({preventScroll:true})}catch(e){}else if(p&&p.blur)p.blur()}}
      fsync(p)}
    // Fire the focus events a focus change from p to the current element would have fired.
    function fsync(p){var now=document.activeElement;if(document.hasFocus()||now===p)return;
      if(p&&p!==document.body){p.dispatchEvent(new FocusEvent('blur',{relatedTarget:now}));p.dispatchEvent(new FocusEvent('focusout',{bubbles:true,composed:true,relatedTarget:now}))}
      if(now&&now!==document.body){now.dispatchEvent(new FocusEvent('focus',{relatedTarget:p}));now.dispatchEvent(new FocusEvent('focusin',{bubbles:true,composed:true,relatedTarget:p}))}}
    function press(t,d){var el=t.to||t.el,p=document.activeElement;
      mev(el,'pointerdown',t.x,t.y,d);var go=mev(el,'mousedown',t.x,t.y,d);
      foc(el,p,!go);
      mev(el,'pointerup',t.x,t.y,d);mev(el,'mouseup',t.x,t.y,d);mev(el,'click',t.x,t.y,d)}
    function setv(el,v){var p=el.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;
      Object.getOwnPropertyDescriptor(p,'value').set.call(el,v);
      el.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:v}));el.dispatchEvent(new Event('change',{bubbles:true}))}
    function edit(a){var t=target(a),el=t?t.el:document.activeElement,fill=a.action==='fill',text=a.text==null?'':String(a.text);
      if(!t&&(!el||el===document.body))throw new Error('nothing is focused; pass a ref');
      var inp=el.tagName==='INPUT'||el.tagName==='TEXTAREA';
      if(!inp&&!el.isContentEditable)throw new Error(desc(el)+' is not editable');
      foc(el);
      if(fill){if(inp)el.select();else getSelection().selectAllChildren(el)}
      else if(inp)try{el.setSelectionRange(el.value.length,el.value.length)}catch(e){}
      else{var g=getSelection();g.selectAllChildren(el);g.collapseToEnd()}
      var before=inp?el.value:null,ok=false;
      try{ok=text?document.execCommand('insertText',false,text):(fill?document.execCommand('delete'):true)}catch(e){}
      if(inp){var want=fill?text:before+text;if(!ok||el.value!==want&&el.value===before)setv(el,want)}
      else if(!ok)el.textContent=(fill?'':el.textContent)+text;
      return(fill?'filled ':'typed into ')+desc(el)+(inp?state(el):' ='+JSON.stringify(clip(el.innerText,60)))}
    var KC={Enter:13,Tab:9,Escape:27,Backspace:8,Delete:46,' ':32,ArrowLeft:37,ArrowUp:38,ArrowRight:39,ArrowDown:40,Home:36,End:35,PageUp:33,PageDown:34};
    var KN={space:' ',return:'Enter',esc:'Escape',left:'ArrowLeft',right:'ArrowRight',up:'ArrowUp',down:'ArrowDown',del:'Delete',pgup:'PageUp',pgdn:'PageDown'};
    Object.keys(KC).forEach(function(k){KN[k.toLowerCase()]=k});
    function key(a){var t=target(a),el=t?t.el:(document.activeElement||document.body);
      if(t)foc(el);
      var ps=String(a.key||'').split('+'),k=ps.pop()||'+',i={bubbles:true,cancelable:true,composed:true,view:window};
      if(k.length>1)k=KN[k.toLowerCase()]||k;
      ps.forEach(function(p){p=p.toLowerCase();i[p==='cmd'||p==='meta'?'metaKey':p==='ctrl'?'ctrlKey':p==='alt'||p==='option'?'altKey':'shiftKey']=true});
      i.key=k;i.code=k===' '?'Space':k.length===1?(/[0-9]/.test(k)?'Digit'+k:'Key'+k.toUpperCase()):k;
      i.keyCode=i.which=KC[k]||(k.length===1?k.toUpperCase().charCodeAt(0):0);
      var go=el.dispatchEvent(new KeyboardEvent('keydown',i));
      if(go&&(k.length===1||k==='Enter'))go=el.dispatchEvent(new KeyboardEvent('keypress',i))&&go;
      if(go&&k==='Enter'&&el.tagName==='INPUT'&&el.form){if(el.form.requestSubmit)el.form.requestSubmit();else el.form.submit()}
      // Tab's default action, which a dispatched event does not perform: move focus on.
      var moved='';
      if(go&&k==='Tab'){var p0=document.activeElement,L=[].filter.call(document.querySelectorAll('a[href],button,input,select,textarea,[tabindex],[contenteditable]'),function(e){return e.tabIndex>=0&&!e.disabled&&(!e.checkVisibility||e.checkVisibility())});
        var j=L.indexOf(el),nx=L.length?L[(j+(i.shiftKey?-1:1)+L.length)%L.length]:null;
        if(nx){try{nx.focus({preventScroll:true})}catch(e){}fsync(p0);if(document.activeElement===nx)moved=' (focus: '+desc(nx)+')'}}
      // Sliders: report the value; a native range input also needs the key's default action.
      var sl=el.getAttribute('role')==='slider'||el.tagName==='INPUT'&&el.type==='range';S.slider=sl;
      if(sl&&go&&el.tagName==='INPUT')rangeKey(el,k,i);
      var ed=sl?' ='+JSON.stringify(clip(el.getAttribute('aria-valuetext')||el.getAttribute('aria-valuenow')||el.value||'',30)):k==='Tab'?'':go?keydef(el,k,i):/^(Backspace|Delete|Enter)$|^.$/.test(k)&&(el.isContentEditable||el.tagName==='TEXTAREA'||el.tagName==='INPUT')?fval(el)+(el.isContentEditable?fmt(k,i):''):'';if(ed)S.fx=1;
      el.dispatchEvent(new KeyboardEvent('keyup',i));
      return'key '+a.key+(go?'':' (handled by page)')+moved+ed}
    // Formatting shortcuts (cmd+b/i/u): the state at the selection afterwards.
    var FMT={b:'bold',i:'italic',u:'underline'};
    function fmt(k,i){var c=(i.metaKey||i.ctrlKey)&&!i.altKey&&FMT[k.toLowerCase()];if(!c)return'';
      var on;try{on=document.queryCommandState(c)}catch(e){}return on==null?'':' ('+c+(on?' on)':' off)')}
    function seltext(){var t=String(getSelection());return t?' (selected '+JSON.stringify(clip(t,60))+')':''}
    function fval(el){var inp=el.tagName==='INPUT'||el.tagName==='TEXTAREA';return' ='+JSON.stringify(inp&&secret(el)?(el.value?'\u2022\u2022\u2022':''):clip(inp?el.value:el.innerText,60))}
    function rangeKey(el,k,i){var mn=el.min===''?0:+el.min,mx=el.max===''?100:+el.max,st=!el.step||el.step==='any'?1:+el.step,v=+el.value,big=Math.max(st,(mx-mn)/10);
      var n={ArrowRight:v+st,ArrowUp:v+st,ArrowLeft:v-st,ArrowDown:v-st,PageUp:v+big,PageDown:v-big,Home:mn,End:mx}[k];if(n==null||i.metaKey||i.ctrlKey)return;
      n=Math.min(mx,Math.max(mn,n));if(n===v)return;
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(el,String(n));
      el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}))}
    // select on a text field or editor: select the first match of the text (case-insensitive fallback).
    function seltxt(el,want){if(!want)throw new Error('select needs the text to select in '+desc(el));
      foc(el);var inp=!el.isContentEditable,all,ns=[];
      if(inp)all=el.value;else{var w=document.createTreeWalker(el,NodeFilter.SHOW_TEXT),n;all='';while((n=w.nextNode())){ns.push([n,all.length]);all+=n.data}}
      var x=all.indexOf(want);if(x<0)x=all.toLowerCase().indexOf(want.toLowerCase());
      if(x<0)throw new Error('no text '+JSON.stringify(want)+' in '+desc(el)+' ='+JSON.stringify(clip(all,60)));
      if(inp){el.setSelectionRange(x,x+want.length);return'selected '+JSON.stringify(all.substr(x,want.length))+' in '+desc(el)}
      function at(o,end){for(var j=0;j<ns.length;j++){var s=ns[j][1],L=ns[j][0].data.length;if(end?o>s&&o<=s+L:o>=s&&o<s+L)return[ns[j][0],o-s]}}
      var p=at(x,false),q=at(x+want.length,true),r=document.createRange(),g=getSelection();
      r.setStart(p[0],p[1]);r.setEnd(q[0],q[1]);g.removeAllRanges();g.addRange(r);
      return'selected '+JSON.stringify(clip(String(g),60))+' in '+desc(el)}
    // Default actions of editing keys in fields, which dispatched key events do not perform.
    function keydef(el,k,i){var inp=el.tagName==='TEXTAREA'||el.tagName==='INPUT'&&!/^(checkbox|radio|file|range|color|submit|button|reset|image|hidden)$/i.test(el.type);
      if(!inp&&!el.isContentEditable)return'';
      var mod=i.metaKey||i.ctrlKey,sh=i.shiftKey,g=getSelection(),before=inp?el.value:el.innerHTML,ok=false;
      function val(){return fval(el)}
      if(!inp&&(!g.rangeCount||!inside(el,g.anchorNode))){g.selectAllChildren(el);g.collapseToEnd()}
      if(mod&&!i.altKey&&/^a$/i.test(k)){if(inp)el.select();else g.selectAllChildren(el);return' (all selected)'}
      // Formatting shortcuts the page left alone (an editor in a frame that cannot take focus).
      if(!inp&&mod&&!i.altKey&&FMT[k.toLowerCase()]){if(g.isCollapsed||!inside(el,g.anchorNode))return' (nothing selected: select R "text" first)';
        try{document.execCommand(FMT[k.toLowerCase()])}catch(e){}return val()+fmt(k,i)}
      if(mod||i.altKey){if(!/^Arrow/.test(k))return''}
      if(inp&&/^Arrow(Up|Down)$/.test(k))return'';
      if(k==='Backspace'||k==='Delete'){try{ok=document.execCommand(k==='Backspace'?'delete':'forwardDelete')}catch(e){}
        if(inp&&el.value===before){var s=el.selectionStart,e=el.selectionEnd;if(s==null)s=e=el.value.length;
          if(s===e){if(k==='Backspace')s=Math.max(0,s-1);else e=Math.min(el.value.length,e+1)}
          if(s!==e){setv(el,el.value.slice(0,s)+el.value.slice(e));try{el.setSelectionRange(s,s)}catch(x){}}}
        return val()}
      if(/^(Arrow(Left|Right|Up|Down)|Home|End)$/.test(k)){var back=/Left|Up|Home/.test(k),line=k==='Home'||k==='End'||i.metaKey,vert=/Up|Down/.test(k);
        if(!inp){try{g.modify(sh?'extend':'move',back?'backward':'forward',vert?(i.metaKey?'documentboundary':'line'):line?'lineboundary':i.altKey?'word':'character')}catch(e){}return sh?seltext():''}
        var L=el.value.length,s=el.selectionStart,e=el.selectionEnd;if(s==null)return'';
        var bw=el.selectionDirection==='backward',f=sh?(bw?s:e):(back?s:e),an=sh?(bw?e:s):null;
        if(sh||s===e||line)f=line?(back?0:L):Math.max(0,Math.min(L,f+(back?-1:1)));
        try{if(sh)el.setSelectionRange(Math.min(an,f),Math.max(an,f),f<an?'backward':'forward');else el.setSelectionRange(f,f)}catch(x){}
        return' (caret '+el.selectionStart+(el.selectionEnd!==el.selectionStart?'-'+el.selectionEnd:'')+'/'+L+')'}
      if(k==='Enter'){if(el.tagName==='INPUT')return'';try{ok=document.execCommand(inp?'insertText':'insertParagraph',false,'\n')}catch(e){}
        if(inp&&!ok)setv(el,el.value+'\n');return val()}
      if(k.length===1){try{ok=document.execCommand('insertText',false,k)}catch(e){}
        if(inp&&el.value===before){var s=el.selectionStart==null?el.value.length:el.selectionStart,e=el.selectionEnd==null?s:el.selectionEnd;setv(el,el.value.slice(0,s)+k+el.value.slice(e));try{el.setSelectionRange(s+1,s+1)}catch(x){}}
        return val()}
      return''}
    function pick(a){var el=need(a).el,want=String(a.text==null?'':a.text);
      if(el.tagName!=='SELECT'){if(el.isContentEditable||el.tagName==='TEXTAREA'||el.tagName==='INPUT'&&typeof el.selectionStart==='number')return seltxt(el,want);
        throw new Error(desc(el)+' is not a <select> or text field; click it instead')}
      var os=[].slice.call(el.options),o=os.find(function(o){return o.value===want||o.text.trim()===want})||os.find(function(o){return o.text.toLowerCase().indexOf(want.toLowerCase())>=0});
      if(!o){var tx=os.map(function(o){return o.text.trim()});throw new Error('no option '+JSON.stringify(want)+'; '+tx.length+' options: '+(tx.length>20?tx.slice(0,10).join(' | ')+' | … | '+tx.slice(-5).join(' | '):tx.join(' | ')))}
      foc(el);
      // The prototype setter, so frameworks that track the value (React) see a change.
      Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype,'value').set.call(el,o.value);
      el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));
      var now=el.selectedOptions[0];
      if(el.value!==o.value)return'tried '+JSON.stringify(o.text.trim())+' but the page kept '+JSON.stringify(now?now.text.trim():el.value)+' in '+desc(el);
      return'selected '+JSON.stringify(o.text.trim())+' in '+desc(el)}
    function scroll(a){var de=document.documentElement,pos=function(){return'scroll '+Math.round(scrollY)+'/'+Math.max(0,de.scrollHeight-innerHeight)};
      if(a.ref&&a.dy==null){get(a.ref).scrollIntoView({block:'center'});return pos()}
      var dy=a.dy==null?Math.round(innerHeight*0.8):a.dy,t=target(a),el=t&&t.el;
      while(el&&el!==document.body&&el!==de){var cs=getComputedStyle(el);if(el.scrollHeight>el.clientHeight+1&&/auto|scroll/.test(cs.overflowY)){el.scrollBy(0,dy);return'scrolled '+desc(el)+' to '+Math.round(el.scrollTop)+'/'+(el.scrollHeight-el.clientHeight)}el=el.parentElement}
      scrollBy(0,dy);return pos()}
    function checked(el){return el.type==='checkbox'||el.type==='radio'?el.checked:el.getAttribute('aria-checked')==='true'}
    // Sets a checkbox or radio to the wanted state; safe to repeat.
    function tick(t,want){var el=t.el;if(!/^(checkbox|radio)$/.test(el.type||'')&&!/^(checkbox|radio|switch|menuitemcheckbox|menuitemradio)$/.test(el.getAttribute('role')||''))throw new Error(desc(el)+' is not a checkbox or radio');if(!want&&checked(el)&&(el.type==='radio'||el.getAttribute('role')==='radio'))throw new Error(desc(el)+' is a radio: it cannot be unchecked; check another option of its group');if(checked(el)!==want)press(t);return(checked(el)===want?'':'! not changed: ')+desc(el)+(checked(el)?' checked':' unchecked')}
    function form(f){return Object.keys(f).map(function(r){try{var v=f[r],el=get(r),y=(el.type||'').toLowerCase();
        if(typeof v==='boolean'||y==='checkbox'||y==='radio'||el.getAttribute('role')==='checkbox')return tick(target({ref:r}),v===true||v==='true'||v==='on');
        if(el.tagName==='SELECT')return pick({ref:r,text:v});
        return edit({action:'fill',ref:r,text:v})}catch(e){return'! '+r+': '+(e.message||e)}}).join('\n')}
    function mkfiles(a){var dt=new DataTransfer();(a.files||[]).forEach(function(f){var b=atob(f.b),u=new Uint8Array(b.length);for(var i=0;i<b.length;i++)u[i]=b.charCodeAt(i);dt.items.add(new File([u],f.n,{type:f.t}))});return dt}
    // Files (or text) dropped from outside the page onto a drop zone that has no file input.
    function dropOn(a){var t=need(a),dt=mkfiles(a);if(a.text!=null)dt.setData('text/plain',a.text);
      var de=function(ty){return t.to.dispatchEvent(new DragEvent(ty,{bubbles:true,cancelable:true,composed:true,clientX:t.x,clientY:t.y,dataTransfer:dt}))};
      de('dragenter');de('dragover');var took=!de('drop');var n=(a.files||[]).length;
      return'dropped '+(n?n+' file(s)':'text')+' on '+desc(t.el)+(took?'':' (no drop handler took it: wrong element?)')}
    function upload(a){var el=need(a).el;
      if(el.tagName!=='INPUT'||el.type!=='file')throw new Error(desc(el)+' is not a file input');
      var dt=mkfiles(a);
      el.files=dt.files;el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));
      return'set '+el.files.length+' file(s) on '+desc(el)}
    // For waits: is the text, ref or selector present (and visible)?
    function has(a){var el;
      if(a.ref){var w=R.get(a.ref);el=w&&w.deref();if(el&&!el.isConnected)el=null}
      else if(a.selector)el=document.querySelector(a.selector);
      else return(document.body.innerText||'').toLowerCase().indexOf(String(a.text||'').toLowerCase())>=0;
      return!!el&&(!el.checkVisibility||el.checkVisibility({visibilityProperty:true,checkVisibilityCSS:true}))}
    // Visible text lines before a click or key, to report what appeared after it (delta).
    function lines(){return(document.body&&document.body.innerText||'').split('\n').map(function(l){return l.trim()})}
    // Fields a fill/select/type changed besides its target (an address lookup, a reset).
    function fv(e){return e.type==='checkbox'||e.type==='radio'?String(e.checked):e.value}
    function fsnap(a){var el=null;try{el=a.ref?get(a.ref):a.selector?document.querySelector(a.selector):a.fields?get(Object.keys(a.fields)[0]):null}catch(e){}
      if(!el)el=document.activeElement;var root=el&&el.form||document;S.fa=a;S.fel=el;
      S.f0=[].slice.call(root.querySelectorAll('input:not([type=hidden]),select,textarea'),0,200).map(function(e){return[e,fv(e)]})}
    function fdelta(){var f0=S.f0,a=S.fa||{},own=new Set(),out=[];S.f0=null;if(!f0)return'';
      own.add(S.fel);[a.ref].concat(a.fields?Object.keys(a.fields):[]).forEach(function(r){try{if(r)own.add(get(r))}catch(e){}});
      f0.forEach(function(x){var e=x[0];if(out.length<4&&e.isConnected&&!own.has(e)&&fv(e)!==x[1])out.push(desc(e)+(e.type==='checkbox'||e.type==='radio'?(e.checked?' checked':' unchecked'):' ='+JSON.stringify(secret(e)?'\u2022\u2022\u2022':clip(e.tagName==='SELECT'&&e.selectedOptions[0]?e.selectedOptions[0].text:e.value,40))))});
      return out.join(', ')}
    function pend(){if(S.q0==null)return 0;try{return mcall('pend',[S.q0])}catch(e){return 0}}
    function delta(){var c=fdelta(),t0=S.t0,out=[],f='';S.t0=null;if(!t0)return{t:'',f:'',c:c};
      // A line that only shrank (an inline element removed) is not new text.
      var now=lines(),ns=new Set(now),gone=[];t0.forEach(function(l){if(l.length>1&&!ns.has(l))gone.push(l)});
      // After a slider key, lines without letters are its own labels run together (min, max, value).
      var sl=S.slider;S.slider=false;
      now.forEach(function(l){if(out.length<3&&l.length>1&&!(sl&&!/\p{L}/u.test(l))&&!t0.has(l)&&out.indexOf(l)<0&&!gone.some(function(g){return g.length>l.length&&g.indexOf(l)>=0}))out.push(l)});
      if(S.n0!=null)try{f=mcall('fails',[S.n0])}catch(e){}S.n0=null;
      return{t:out.map(function(l){return JSON.stringify(clip(l,100))}).join(' / '),f:f,c:c}}
    // CSS :hover cannot be triggered by dispatched events. Copy the page's :hover rules with a
    // class in place of :hover (a constructed sheet, which page CSP does not block) and put the
    // class on the element under the pointer and its ancestors, as a real pointer would.
    var HC={k:-1,n:0,bad:0,sheet:null};
    function hcss(){var ss=document.styleSheets;if(HC.k===ss.length)return HC;var out=[],n=0,bad=0;
      function walk(rs,acc){for(var i=0;i<rs.length;i++){var r=rs[i];
        if(r.selectorText!=null){if(/:hover\b/.test(r.selectorText)){acc.push(r.selectorText.replace(/:hover\b/g,'.__smcp_hover')+'{'+r.style.cssText+'}');n++}}
        else if(r.cssRules){var inner=[];walk(r.cssRules,inner);if(inner.length){var c=r.media?'@media '+r.media.mediaText:r.conditionText!=null&&r.constructor.name.indexOf('Supports')>=0?'@supports '+r.conditionText:'';acc.push(c?c+'{'+inner.join('')+'}':inner.join(''))}}}}
      for(var i=0;i<ss.length;i++){var rs;try{rs=ss[i].cssRules}catch(e){bad++;continue}if(rs)walk(rs,out)}
      var text=out.join('\n');
      try{if(!HC.sheet){HC.sheet=new CSSStyleSheet();document.adoptedStyleSheets=document.adoptedStyleSheets.concat([HC.sheet])}HC.sheet.replaceSync(text)}
      catch(e){var st=document.getElementById('__smcp_hover')||document.documentElement.appendChild(document.createElement('style'));st.id='__smcp_hover';st.textContent=text}
      HC.k=document.styleSheets.length;HC.n=n;HC.bad=bad;return HC}
    function hov(el){if(S.hv)S.hv.forEach(function(e){e.classList.remove('__smcp_hover')});var h=hcss(),l=[];
      for(var e=el;e&&e.nodeType===1;e=e.parentElement||(e.getRootNode&&e.getRootNode().host))l.push(e);
      if(h.n)l.forEach(function(e){e.classList.add('__smcp_hover')});S.hv=l;return h}
    function act(a){S.note='';if(a.text!=null&&(a.action==='dialog'||a.action==='click'))a.text=String(a.text).replace(/^answer\s*[:=]?\s*/i,'');var r=act1(a);return r+S.note}
    function act1(a){var t;S.fx=1;S.f0=null;S.slider=false;
      if(a.action==='click'||a.action==='dblclick'||a.action==='key'||a.action==='hover'||a.submit){watch();S.t0=new Set(lines());S.n0=null;try{S.n0=mcall('ncount')}catch(e){}}
      if(/^(click|dblclick|rclick|drag|key|hover|fill|check|select|type)$/.test(a.action)){fsnap(a);S.q0=null;try{S.q0=mcall('nn0')}catch(e){}}
      switch(a.action){
        case'click':t=need(a);if(a.text!=null)try{mcall('policy',[String(a.text)])}catch(e){}if(/^(INPUT|TEXTAREA|SELECT)$/.test(t.to.tagName)||t.to.isContentEditable)S.fx=1;if(S.hv)hov(t.to);press(t);return'clicked '+desc(t.el);
        case'dblclick':t=need(a);if(S.hv)hov(t.to);press(t);press(t,{detail:2});mev(t.to,'dblclick',t.x,t.y,{detail:2});return'double-clicked '+desc(t.el);
        case'drag':t=need(a);var dst=a.to_sel?document.querySelector(a.to_sel):get(a.to);if(!dst)throw new Error('no element matches '+a.to_sel);var dr=dst.getBoundingClientRect(),dx=dr.left+dr.width/2,dy=dr.top+dr.height/2,dh=deep(dx,dy),dto=dh&&inside(dst,dh)?dh:dst;
          // Pointer libraries (sortable lists, sliders) follow the mouse; HTML5 drag and drop needs drag events.
          mev(t.to,'pointerdown',t.x,t.y);mev(t.to,'mousedown',t.x,t.y);
          for(var st=1;st<=5;st++){var mx=t.x+(dx-t.x)*st/5,my=t.y+(dy-t.y)*st/5,mo=deep(mx,my)||dto;mev(mo,'pointermove',mx,my,{buttons:1});mev(mo,'mousemove',mx,my,{buttons:1})}
          var src=t.el.closest('[draggable=true]')||(t.to.closest&&t.to.closest('[draggable=true]'));
          if(src){var dt=new DataTransfer(),de=function(el,ty,x,y){var ev=new DragEvent(ty,{bubbles:true,cancelable:true,composed:true,clientX:x,clientY:y,dataTransfer:dt});return el.dispatchEvent(ev)};
            de(src,'dragstart',t.x,t.y);de(dto,'dragenter',dx,dy);de(dto,'dragover',dx,dy);de(dto,'drop',dx,dy);de(src,'dragend',dx,dy)}
          mev(dto,'pointerup',dx,dy);mev(dto,'mouseup',dx,dy);
          return'dragged '+desc(t.el)+' to '+desc(dst)+(src?'':' (pointer events only: no draggable element)');
        case'rclick':t=need(a);['pointerdown','mousedown','pointerup','mouseup','contextmenu'].forEach(function(e){mev(t.to,e,t.x,t.y,{button:2,buttons:/down/.test(e)?2:0})});return'right-clicked '+desc(t.el);
        case'hover':t=need(a);['pointerover','mouseover','pointerenter','mouseenter','pointermove','mousemove'].forEach(function(e){mev(t.to,e,t.x,t.y)});
          var h=hov(t.to);return'hovered '+desc(t.el)+(h.n?' ('+h.n+' :hover rules':' (no :hover styles found')+(h.bad?'; '+h.bad+' stylesheets from other sites unreadable, --os if nothing shows)':')');
        case'type':return sub(a,edit(a));
        case'fill':return sub(a,a.fields?form(a.fields):edit(a));
        case'check':return tick(need(a),a.text!=='false');
        case'key':return key(a);
        case'select':return pick(a);
        case'scroll':return scroll(a);
        case'upload':return upload(a);
        case'drop':return dropOn(a);
        case'dialog':var dp=a.text==null?'accept':String(a.text);try{mcall('policy',[dp])}catch(e){throw new Error('dialogs cannot be answered on this page until it is reloaded')}return'next dialog: '+(dp==='accept'||dp==='dismiss'?dp:'answer '+JSON.stringify(dp));
        default:throw new Error('unknown action '+a.action)}}
    // --submit: Enter in the field just edited (the last of a form; the focused one without a target).
    function sub(a,r){if(!a.submit)return r;var s=typeof a.submit==='string';
      return r+'; '+key({key:'Enter',ref:s?a.submit:a.ref,x:s?null:a.x,y:s?null:a.y})}
    function pickEl(a){var e=a.ref?get(a.ref):a.selector?document.querySelector(a.selector):deep(a.x,a.y);
      if(!e)throw new Error(a.selector?'no element matches '+a.selector:'no element at '+a.x+','+a.y);return e}
    // The selector is built in the page's world (main.js), which the recorder shares.
    function loc(a){var e=pickEl(a);if(e.getRootNode()!==document)throw new Error(desc(e)+' is inside a shadow root, which --sel cannot reach; use its ref');
      var k='l'+Date.now();e.setAttribute('data-smcp-el',k);var s;
      try{s=mcall('loc',[k])}catch(x){e.removeAttribute('data-smcp-el');if(x.message==='NOMAIN')throw new Error('this page was loaded before the Safari CLI Bridge extension; reload it');throw x}
      if(!s)throw new Error('no unique selector found for '+desc(e));return"--sel '"+s.replace(/'/g,"'\\''")+"'  "+desc(e)}
    function storage(a){var st,area=a.area==='session'?'session':'local';try{st=area==='session'?sessionStorage:localStorage}catch(e){throw new Error(area+'Storage is not available on this page')}
      var keys=[];for(var i=0;i<st.length;i++){var k=st.key(i);if(k.indexOf('__smcp_')!==0)keys.push(k)}keys.sort();
      if(a.clear){keys.forEach(function(k){st.removeItem(k)});return'cleared '+keys.length+' '+area+'Storage key'+(keys.length===1?'':'s')}
      if(a.del!=null){if(st.getItem(a.del)==null)throw new Error('no '+area+'Storage key '+JSON.stringify(a.del));st.removeItem(a.del);return'deleted '+JSON.stringify(a.del)}
      if(a.key!=null&&a.value!=null){st.setItem(a.key,a.value);return'set '+JSON.stringify(a.key)+' ('+a.value.length+' chars)'}
      if(a.key!=null){var v=st.getItem(a.key);if(v==null)throw new Error('no '+area+'Storage key '+JSON.stringify(a.key)+(keys.length?'; keys: '+keys.slice(0,20).join(', '):''));
        var m=a.max_chars==null?6000:a.max_chars;return m>0&&v.length>m?v.slice(0,m)+'\n\u001e… '+(v.length-m)+' more chars (--max 0 for all)':v}
      if(!keys.length)return'(no '+area+'Storage keys on '+location.host+')';
      return keys.map(function(k){return k+' = '+clip(st.getItem(k),120)}).join('\n')+'\n\u001e'+keys.length+' '+area+'Storage key'+(keys.length===1?'':'s')+' on '+location.host}
    // Without the extension: the page's own cookies (no HttpOnly, no domain or expiry). Same reply as the extension's op.
    function cookies(a){var all=document.cookie?document.cookie.split(/;\s*/).map(function(p){var i=p.indexOf('=');return{name:i<0?'':p.slice(0,i),value:i<0?p:p.slice(i+1)}}):[];
      var gone='=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/',hs=location.hostname.split('.');
      var kill=function(n){document.cookie=n+gone;for(var i=0;i<hs.length-1;i++)document.cookie=n+gone+'; domain=.'+hs.slice(i).join('.')};
      if(a.act==='load'){var n=0;(a.list||[]).forEach(function(c){if(c.httpOnly)return;document.cookie=c.name+'='+c.value+'; path='+(c.path||'/')+(c.exp?'; expires='+new Date(c.exp*1000).toUTCString():'')+(c.domain&&c.domain[0]==='.'?'; domain='+c.domain:'')+(c.secure?'; secure':'');n++});return JSON.stringify({ok:n})}
      if(a.act==='set'){document.cookie=a.name+'='+a.value+'; path=/';all=[{name:a.name,value:a.value}];return JSON.stringify({ok:document.cookie.split(/;\s*/).indexOf(a.name+'='+a.value)>=0?all:[]})}
      if(a.name)all=all.filter(function(c){return c.name===a.name});
      if(a.act==='del'||a.act==='clear')all.forEach(function(c){kill(c.name)});
      return JSON.stringify({ok:all})}
    function record(a){try{return mcall(a.stop?'recStop':'recStart',[])}catch(x){if(x.message==='NOMAIN')throw new Error('recording needs the page to be loaded with the Safari CLI Bridge extension on; reload it');throw x}}
    // A box drawn around the element in the user's view, gone after a few seconds.
    function light(a){var H=S.hls||(S.hls=[]);
      if(a.hide){var k=H.length;H.slice().forEach(function(x){x()});return k?'removed '+k+' highlight'+(k>1?'s':''):'no highlights'}
      var e=pickEl(a),host=document.createElement('div');host.setAttribute('data-smcp-hl','');
      host.style.cssText='all:initial;position:fixed;left:0;top:0;width:0;height:0;z-index:2147483647;pointer-events:none';
      var sh=host.attachShadow({mode:'closed'}),b=document.createElement('div');sh.appendChild(b);
      b.style.cssText='position:fixed;box-sizing:border-box;border:3px solid #ff2d55;border-radius:5px;box-shadow:0 0 0 4px rgba(255,45,85,.25);background:rgba(255,45,85,.07);pointer-events:none';
      (document.body||document.documentElement).appendChild(host);
      var r0=e.getBoundingClientRect();if(r0.top<0||r0.bottom>innerHeight)e.scrollIntoView({block:'center'});
      var pos=function(){var r=e.getBoundingClientRect();b.style.left=(r.left-4)+'px';b.style.top=(r.top-4)+'px';b.style.width=(r.width+8)+'px';b.style.height=(r.height+8)+'px'};
      var secs=a.secs==null?5:+a.secs,iv,to,x=function(){clearInterval(iv);clearTimeout(to);host.remove();var i=H.indexOf(x);if(i>=0)H.splice(i,1)};
      pos();iv=setInterval(function(){if(!e.isConnected)x();else pos()},100);if(secs>0)to=setTimeout(x,secs*1000);H.push(x);
      return'highlighted '+desc(e)+(secs>0?' for '+secs+' s':' until highlight --hide')}
    // For js with an element: tag it so code in either world can find it.
    function mark(a){var e=a.ref?get(a.ref):a.selector?document.querySelector(a.selector):deep(a.x,a.y);
      if(!e)throw new Error(a.selector?'no element matches '+a.selector:'no element at '+a.x+','+a.y);e.setAttribute('data-smcp-el',a.slot);return'ok'}
    function geom(a){var t=target(a),g={iw:innerWidth,ih:innerHeight};
      if(t){g.x=t.x;g.y=t.y;g.d=desc(t.el);var ae=document.activeElement;if(ae&&ae!==document.body&&inside(t.el,ae))g.fo=1;if(t.r)g.r=[t.r.left,t.r.top,t.r.width,t.r.height];
        // For real input: what a click at the centre would hit, when that is not the target.
        if(a.ref){var h=deep(t.x,t.y);if(h&&!inside(t.el,h)&&!inside(h,t.el))g.cover=desc(h)}}
      // Without a target: is there a field (or a frame, which may hold one) to type into?
      else{var f=document.activeElement;if(f&&(/^(INPUT|TEXTAREA|IFRAME)$/.test(f.tagName)||f.isContentEditable))g.ed=1}return g}

    function routes(a){try{return mcall('setRoutes',[a.list==null?null:a.list])}
      catch(e){if(e.message==='NOMAIN')throw new Error('this page was loaded before the Safari CLI Bridge extension; reload it, then route again');throw e}}
    // The main-world part (main.js): reached through synchronous DOM events from the extension's
    // isolated world, or directly when the agent runs in the page itself (frames reached by jsFrame).
    function mcall(op,args){var M=window.__smcpM;if(M){M.arm();return M[op].apply(null,args||[])}
      var r=null,h=function(e){r=e.detail};document.addEventListener('__smcp_r',h);
      document.dispatchEvent(new CustomEvent('__smcp_q',{detail:JSON.stringify({op:op,a:args||[]})}));document.removeEventListener('__smcp_r',h);
      if(r==null)throw new Error('NOMAIN');r=JSON.parse(r);if(r.e)throw new Error(r.e);return r.v}
    function logs(a){try{return mcall('logs',[a])}catch(e){if(e.message==='NOMAIN')return'(this page was loaded before the Safari CLI Bridge extension; reload it to capture logs)';throw e}}
    S.mrun=function(id,code){try{return mcall('run',[id,code])}catch(e){return'nomain'}};
    function ser(v){if(v===undefined)return'undefined';if(v instanceof Element)return desc(v);if(typeof v==='function')return String(v).slice(0,200);
      try{var j=JSON.stringify(v,function(k,x){return x instanceof Element?desc(x):typeof x==='bigint'?String(x):x});return j===undefined?String(v):j}catch(e){return String(v)}}
    addEventListener('beforeunload',function(){S.bye=Date.now()});addEventListener('pageshow',function(){S.bye=0});
    S.slot=function(id){var s=S.slots[id]={d:0};return{done:function(v){s.d=1;s.v=ser(v)},fail:function(e){s.d=1;s.e=String(e)}}};
    S.take=function(id){var s=S.slots[id];if(!s){try{return mcall('take',[id])}catch(e){return'{"x":1}'}}if(!s.d)return'{"p":1}';delete S.slots[id];return JSON.stringify(s.e?{e:s.e}:{v:s.v})};
    S.call=function(a){if(a.h!==S.h)return JSON.stringify({m:S.h||''});
      // u0: the address before the call, so a history.pushState route change counts as a change.
      var u0=location.href;
      try{var v=a.op==='read'?read(a):a.op==='table'?table(a):a.op==='act'?act(a):a.op==='geom'?geom(a):a.op==='mark'?mark(a):a.op==='route'?routes(a):a.op==='locator'?loc(a):a.op==='storage'?storage(a):a.op==='cookies'?cookies(a):a.op==='record'?record(a):a.op==='highlight'?light(a):a.op==='logs'?logs(a):a.op==='has'?has(a):a.op==='delta'?delta():a.op==='pend'?pend():null,o={v:v,u:location.href,u0:u0,r:document.readyState},d;try{d=mcall('dlgTake')}catch(e){}if(d&&d.length)o.d=d;return JSON.stringify(o)}
      catch(e){return JSON.stringify({e:String(e&&e.message||e)})}};
    })()
    """#
}
