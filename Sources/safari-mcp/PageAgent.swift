enum PageAgent {
    /// Returned by the call wrapper when the agent is not in the page yet.
    static let absent = "__smcp_absent__"

    /// Injected once per page. Everything the tools need from the DOM lives here so a
    /// normal call is a single Apple Event carrying a few bytes.
    static let source = #"""
    (function(){
    if(window.__smcp)return;
    var S=window.__smcp={h:'',slots:{},con:null,net:null,last:{}};
    var R=new Map(),W=new WeakMap(),n=0;
    function ref(el){var id=W.get(el);if(!id){id='e'+(++n);W.set(el,id);R.set(id,new WeakRef(el))}return id}
    function get(id){var w=R.get(id),el=w&&w.deref();if(!el||!el.isConnected)throw new Error('ref '+id+' is stale (page changed or element removed); call read again');return el}
    function clip(s,k){s=String(s==null?'':s).replace(/\s+/g,' ').trim();return s.length>k?s.slice(0,k-1)+'\u2026':s}
    var IR=/^(button|link|checkbox|radio|tab|menuitem|menuitemcheckbox|menuitemradio|option|switch|combobox|textbox|searchbox|slider|spinbutton|treeitem)$/;
    var SKIP={SCRIPT:1,STYLE:1,NOSCRIPT:1,TEMPLATE:1,HEAD:1,LINK:1,META:1,svg:1,SVG:1};
    var PROSE={P:1,BLOCKQUOTE:1,PRE:1,FIGCAPTION:1,DD:1,LI:2,TD:2,TH:2,DT:2};
    var TR={BUTTON:'button',SELECT:'combobox',TEXTAREA:'textbox',SUMMARY:'button',A:'link'};
    function role(el){var r=el.getAttribute('role');if(r)return r;var t=el.tagName;
      if(t==='INPUT'){var y=(el.type||'text').toLowerCase();return y==='checkbox'||y==='radio'||y==='file'?y:/^(submit|button|reset|image)$/.test(y)?'button':y==='range'?'slider':y==='search'?'searchbox':'textbox'}
      return TR[t]||t.toLowerCase()}
    function native(el){var t=el.tagName;return t==='BUTTON'||t==='SELECT'||t==='TEXTAREA'||t==='SUMMARY'||(t==='A'&&el.hasAttribute('href'))||(t==='INPUT'&&el.type!=='hidden')}
    function secret(el){return (el.type||'').toLowerCase()==='password'||/cc-|one-time|password/.test(el.getAttribute('autocomplete')||'')}
    function name(el,k){var a=el.getAttribute('aria-label');if(a)return clip(a,k);
      var lb=el.getAttribute('aria-labelledby');if(lb){var s=lb.split(/\s+/).map(function(i){var e=document.getElementById(i);return e?e.textContent:''}).join(' ');if(s.trim())return clip(s,k)}
      var t=el.tagName;
      if(t==='INPUT'&&/^(submit|button|reset)$/.test(el.type))return clip(el.value,k);
      if(t==='INPUT'||t==='SELECT'||t==='TEXTAREA'){if(el.labels&&el.labels[0])return clip(el.labels[0].textContent,k);
        if(el.placeholder||el.title)return clip(el.placeholder||el.title,k);
        if(/^(checkbox|radio)$/.test(el.type)){var pe=el.parentElement,px=pe&&(pe.innerText||'').trim();if(px&&px.length<=80)return clip(px,k)}
        return clip(el.name||el.id||'',k)}
      if(t==='IMG')return clip(el.alt||el.title||'',k);
      var x=el.innerText||el.textContent||el.title;
      if(!x||!x.trim()){var im=el.querySelector('img[alt]');x=(im&&im.alt)||(el.getAttribute('href')||'').split(/[?#]/)[0].split('/').filter(Boolean).pop()||el.id||String(el.getAttribute('class')||'').split(/\s+/)[0]||''}
      return clip(x,k)}
    function state(el){var t=el.tagName,s='';
      if(t==='INPUT'||t==='TEXTAREA'||t==='SELECT'){var y=(el.type||'').toLowerCase();
        if(y==='checkbox'||y==='radio'){if(el.checked)s+=' checked'}
        else if(!/^(submit|button|reset|image)$/.test(y)){var v;if(secret(el))v=el.value?'\u2022\u2022\u2022':'';else if(t==='SELECT'){var o=el.selectedOptions[0];v=o?o.text:''}else v=el.value;if(v)s+=' ='+JSON.stringify(clip(v,60))}}
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
        var I=leaf||el.hasAttribute('onclick')||(ti!==null&&ti!=='-1')||(el.isContentEditable&&!(el.parentElement&&el.parentElement.isContentEditable));
        if(!I&&!inI&&ok&&el.children.length<6&&t!=='BODY'&&t!=='HTML'&&getComputedStyle(el).cursor==='pointer')I=true;
        if(I&&ok){out.push({el:el,inv:inv,s:ref(el)+' '+role(el)+' '+JSON.stringify(name(el,leaf?80:50))+state(el)});if(leaf)return;inI=true}
        else if(I&&leaf)return;
        else if(all&&ok&&/^H[1-6]$/.test(t)){out.push({el:el,inv:inv,s:ref(el)+' '+t.toLowerCase()+' '+JSON.stringify(name(el,120))});return}
        else if(all&&ok&&t==='IMG'){if(el.alt)out.push({s:'img '+JSON.stringify(clip(el.alt,80))});return}
        else if(all&&ok&&!inI&&(PROSE[t]===1||(PROSE[t]===2&&!el.querySelector('a[href],button,input,select,textarea')))){var p=clip(el.innerText,400);if(p.length>1)out.push({s:p,tel:el});if(!o.links)return;noText=true}
        var kids=el.shadowRoot?el.shadowRoot.childNodes:el.childNodes;
        for(var i=0;i<kids.length;i++){var k=kids[i];
          if(k.nodeType===1)rec(k,inI,noText);
          else if(all&&ok&&!I&&!noText&&k.nodeType===3){var x=k.nodeValue.trim();if(x.length>1||/[0-9A-Za-z]/.test(x))out.push({s:clip(x,160),tel:el})}}
      }
      rec(o.root||document.body,false);return out}

    // Lines are matched by ref when they have one, else by their text.
    function dk(l){var m=/^(e\d+) /.exec(l);return m?m[1]:l}
    function diff(o,b){var om=new Map(),out=[],same=0;
      o.split('\n').forEach(function(l){var k=dk(l),v=om.get(k);if(v)v.push(l);else om.set(k,[l])});
      b.split('\n').forEach(function(l){var k=dk(l),v=om.get(k),p=v&&v.shift();if(v&&!v.length)om.delete(k);
        if(p===undefined)out.push('+ '+l);else if(p===l)same++;else out.push('~ '+l)});
      om.forEach(function(v,k){v.forEach(function(l){out.push('- '+(k===l?clip(l,80):k+' '+clip(l.slice(k.length+1),50)))})});
      return(out.length?out.join('\n')+'\n':'no changes ')+'('+same+' unchanged)'}

    // Markdown of the readable content. Links become text[n] with the URLs listed once at the end.
    var BLK={P:1,DIV:1,SECTION:1,ARTICLE:1,MAIN:1,HEADER:1,FOOTER:1,NAV:1,ASIDE:1,FORM:1,FIELDSET:1,FIGURE:1,FIGCAPTION:1,BLOCKQUOTE:1,DL:1,DT:1,DD:1,ADDRESS:1,DETAILS:1,SUMMARY:1,HR:1,TR:1,CAPTION:1};
    var NOISE={NAV:1,HEADER:1,FOOTER:1,ASIDE:1,navigation:1,banner:1,contentinfo:1,complementary:1,search:1};
    function short(h){var u;try{u=new URL(h,location.href)}catch(e){return''}
      if(!/^(https?|file):$/.test(u.protocol))return'';return u.origin===location.origin?(u.pathname+u.search+u.hash):u.href}
    function md(root,fit){
      var lines=[],U=new Map(),buf='',pf='',ind='',c=0,il=0;
      function flush(){var t=buf.replace(/[ \t\n\r ]+/g,' ').trim();buf='';if(t){lines.push(pf+t);pf=ind}}
      function url(h){var s=short(h);if(!s)return 0;if(!U.has(s))U.set(s,U.size+1);return U.get(s)}
      function kids(el){var s=el.tagName==='SLOT'&&el.assignedNodes({flatten:true});return s&&s.length?s:el.shadowRoot?el.shadowRoot.childNodes:el.childNodes}
      function inner(el){var b=buf;buf='';il++;walk(el);il--;var t=buf.replace(/[ \t\n\r ]+/g,' ').trim();buf=b;return t}
      function walk(n){var ks=kids(n);for(var i=0;i<ks.length;i++)node(ks[i])}
      function node(n){
        if(n.nodeType===3){buf+=n.nodeValue;return}
        if(n.nodeType!==1||++c>20000)return;
        var t=n.tagName,ro=n.getAttribute('role');
        if(SKIP[t]||/^(INPUT|SELECT|TEXTAREA|BUTTON|OPTION|IFRAME|CANVAS|VIDEO|AUDIO|DIALOG)$/.test(t)||n.getAttribute('aria-hidden')==='true')return;
        if(n.checkVisibility&&!n.checkVisibility({visibilityProperty:true,checkVisibilityCSS:true})&&getComputedStyle(n).display!=='contents')return;
        if(fit&&(NOISE[t]||NOISE[ro]))return;
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
        if(t==='TABLE'&&!n.querySelector('table')){flush();var rows=[].slice.call(n.rows),cols=0;
          rows.slice(0,60).forEach(function(r,ri){var cs=[].map.call(r.cells,function(x){return clip(inner(x),120).replace(/\|/g,'\\|')});
            if(!cs.join(''))return;lines.push(ind+'| '+cs.join(' | ')+' |');if(!cols){cols=cs.length;lines.push(ind+'|'+' --- |'.repeat(cols))}});
          if(rows.length>60)lines.push(ind+'(… '+(rows.length-60)+' more rows)');return}
        var blk=BLK[t]||t==='LI'||(t.indexOf('-')>0&&/^(block|flex|grid|list-item|table)/.test(getComputedStyle(n).display));
        if(blk)flush();walk(n);if(blk)flush();else if(t==='TD'||t==='TH')buf+=' '}
      node(root);flush();return{lines:lines,urls:[...U.keys()]}}
    function text(root){
      if(root)return md(root,false);
      var m=document.querySelector('article,main,[role=main]'),r=m&&md(m,false);
      if(r&&r.lines.join('').length>=200)return r;
      r=md(document.body,true);return r.lines.join('').length>=200?r:md(document.body,false)}
    function foot(m,used){var f=[];m.urls.forEach(function(u,i){if(!used||used.has(i+1))f.push('['+(i+1)+']: '+u)});return f.length?'\n\n'+f.join('\n'):''}
    // BM25 over the markdown lines; the best ones are returned in page order, each under its nearest heading.
    function rank(m,q,max){
      var tok=function(s){return s.toLowerCase().match(/[\p{L}\p{N}]+/gu)||[]},L=m.lines,N=L.length,df={},docs=[],avg=0;
      L.forEach(function(l){var tf={},ts=tok(l);ts.forEach(function(w){tf[w]=(tf[w]||0)+1});for(var w in tf)df[w]=(df[w]||0)+1;docs.push({tf:tf,n:ts.length});avg+=ts.length});
      avg=avg/Math.max(N,1)||1;var qs=tok(q),sc=[];
      docs.forEach(function(d,i){var s=0;if(/^\s*#/.test(L[i]))return;qs.forEach(function(w){var f=d.tf[w];if(!f)return;var idf=Math.log(1+(N-df[w]+0.5)/(df[w]+0.5));s+=idf*f*2.2/(f+1.2*(0.25+0.75*d.n/avg))});if(s>0)sc.push({i:i,s:s})});
      if(!sc.length)return'no text matches '+JSON.stringify(q);
      sc.sort(function(x,y){return y.s-x.s});
      var pick=new Set(),size=0;
      for(var k=0;k<sc.length&&k<30;k++){var len=L[sc[k].i].length;if(size+len>max&&pick.size)break;pick.add(sc[k].i);size+=len}
      var out=[],used=new Set(),hd=-1,prev=-2;
      [...pick].sort(function(x,y){return x-y}).forEach(function(i){
        for(var h=i;h>=0;h--)if(/^\s*#/.test(L[h]))break;
        if(h>=0&&h!==hd&&h!==i){out.push(L[h]);hd=h}else if(prev>=0&&i!==prev+1)out.push('…');
        out.push(L[i]);prev=i;L[i].replace(/\[(\d+)\]/g,function(_,n){used.add(+n)})});
      return out.join('\n')+foot(m,used)}
    function links(root,q){
      var seen=new Set(),inn=[],ext=[],ws=q?q.toLowerCase().split(/\s+/).filter(Boolean):[];
      root.querySelectorAll('a[href]').forEach(function(el){var u=short(el.getAttribute('href'));if(!u||seen.has(u))return;
        if(el.checkVisibility&&!el.checkVisibility({visibilityProperty:true,checkVisibilityCSS:true}))return;
        var nm=name(el,60),hay=(nm+' '+u).toLowerCase();if(ws.some(function(w){return hay.indexOf(w)<0}))return;
        seen.add(u);(/^[a-z]+:/.test(u)?ext:inn).push(ref(el)+' '+JSON.stringify(nm)+' '+u)});
      return inn.concat(ext.length?['external:'].concat(ext):[]).join('\n')||(q?'no link matches '+JSON.stringify(q):'(no links)')}

    function read(a){
      var root=a.ref?get(a.ref):a.selector?document.querySelector(a.selector):null;
      if(a.selector&&!root)throw new Error('selector matched nothing');
      var body,qm=a.query&&a.mode!=='text'&&a.mode!=='links';
      if(qm){
        var q=a.query.toLowerCase().trim(),ws=q.split(/\s+/).filter(Boolean),hits=[];
        var wb=ws.map(function(w){return new RegExp('(^|[^a-z0-9])'+w.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+'($|[^a-z0-9])')});
        scan({mode:'all',full:true,links:true,root:root}).forEach(function(x){var el=x.el;if(!el&&!x.tel)return;
          var nm=x.s.toLowerCase(),at=!el?'':((el.id||'')+' '+(el.getAttribute('name')||'')+' '+(el.getAttribute('placeholder')||'')+' '+(el.getAttribute('href')||'').replace(/^[a-z]+:\/\/[^\/]+/i,'')+' '+(el.title||'')).toLowerCase();
          var sc=0,hit=0;ws.forEach(function(w,i){if(wb[i].test(nm)){sc+=3;hit++}else if(nm.indexOf(w)>=0){sc+=2;hit++}else if(at.indexOf(w)>=0){sc++;hit++}});
          if(!hit)return;if(nm.indexOf(q)>=0)sc+=2;if(nm.indexOf('"'+q+'"')>=0)sc+=4;x.all=hit===ws.length;
          if(!el){var r=x.tel.getBoundingClientRect();x.inv=r.bottom>0&&r.top<innerHeight;sc-=0.25}
          if(x.inv)sc+=0.5;hits.push({sc:sc,x:x})});
        if(hits.some(function(h){return h.x.all}))hits=hits.filter(function(h){return h.x.all});
        hits.sort(function(p,r){return r.sc-p.sc});
        body=hits.slice(0,10).map(function(h){var x=h.x;return(x.el?x.s:ref(x.tel)+' text '+JSON.stringify(clip(x.s,100)))+(x.inv?'':' (offscreen)')}).join('\n')||'no match for '+JSON.stringify(a.query);
      }else if(a.mode==='text'){
        var m=text(root);body=a.query?rank(m,a.query,a.max_chars||6000):m.lines.join('\n')+foot(m,null);
      }else if(a.mode==='links'){
        body=links(root||document.body,a.query);
      }else{
        body=scan({mode:a.mode,full:a.full,root:root}).map(function(x){return x.s}).join('\n')||(a.full?'(nothing found)':'(nothing in viewport; scroll or pass full:true)');
      }
      if(!qm){
        var k=(a.mode||'interactive')+'|'+(a.ref||a.selector||'')+'|'+(a.full?1:0)+'|'+(a.query||''),old=S.last[k];S.last[k]=body;
        if(a.diff)body=old==null?'(first read of this page in this mode; full result)\n'+body:diff(old,body)}
      var off=a.offset||0,max=a.max_chars||6000,tot=body.length,cut=body.slice(off,off+max);
      if(off+max<tot){var nl=cut.lastIndexOf('\n');if(nl>max*0.6)cut=cut.slice(0,nl);cut+='\n\u2026 '+(tot-off-cut.length)+' more chars; offset='+(off+cut.length)}
      var de=document.documentElement;
      return(document.title?clip(document.title,80)+' | ':'')+location.href.slice(0,200)+' | scroll '+Math.round(scrollY)+'/'+Math.max(0,de.scrollHeight-innerHeight)+(document.readyState==='complete'?'':' | still loading')+'\n'+cut}

    function deep(x,y){var e=document.elementFromPoint(x,y);while(e&&e.shadowRoot){var n=e.shadowRoot.elementFromPoint(x,y);if(!n||n===e)break;e=n}return e}
    function inside(el,c){for(;c;c=c.parentNode||c.host)if(c===el)return true;return false}
    function target(a){var el;
      if(a.ref){el=get(a.ref);var r=el.getBoundingClientRect();
        if(r.top<0||r.left<0||r.bottom>innerHeight||r.right>innerWidth){el.scrollIntoView({block:'center',inline:'center'});r=el.getBoundingClientRect()}
        // Events go to the innermost element under the pointer, as a real click would, so
        // a link or button nested in the referenced element still activates.
        var x=r.left+r.width/2,y=r.top+r.height/2,h=deep(x,y);
        return{el:el,to:h&&inside(el,h)?h:el,x:x,y:y,r:r}}
      if(a.x!=null&&a.y!=null){el=deep(a.x,a.y);if(!el)throw new Error('nothing at '+a.x+','+a.y);return{el:el,to:el,x:a.x,y:a.y}}
      return null}
    function need(a){var t=target(a);if(!t)throw new Error('pass ref or x,y');return t}
    function mev(el,type,x,y,more){var P=type.indexOf('pointer')===0,C=P&&window.PointerEvent?PointerEvent:MouseEvent;
      var i={bubbles:!/enter|leave/.test(type),cancelable:true,composed:true,view:window,clientX:x,clientY:y,screenX:x+screenX,screenY:y+screenY,button:0,buttons:/down/.test(type)?1:0,detail:1};
      if(P){i.pointerId=1;i.pointerType='mouse';i.isPrimary=true}
      if(more)for(var k in more)i[k]=more[k];
      return el.dispatchEvent(new C(type,i))}
    function watch(){S.fx=0;var mo=new MutationObserver(hit),ev=['input','change','scroll','hashchange','submit'];
      function hit(){S.fx=1;mo.disconnect();ev.forEach(function(e){removeEventListener(e,hit,true)})}
      mo.observe(document,{subtree:true,childList:true,attributes:true,characterData:true});ev.forEach(function(e){addEventListener(e,hit,true)});setTimeout(hit,1500)}
    function press(t,d){var el=t.to||t.el;
      mev(el,'pointerdown',t.x,t.y,d);mev(el,'mousedown',t.x,t.y,d);
      if(el.focus&&document.activeElement!==el)try{el.focus({preventScroll:true})}catch(e){}
      mev(el,'pointerup',t.x,t.y,d);mev(el,'mouseup',t.x,t.y,d);mev(el,'click',t.x,t.y,d)}
    function setv(el,v){var p=el.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;
      Object.getOwnPropertyDescriptor(p,'value').set.call(el,v);
      el.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:v}));el.dispatchEvent(new Event('change',{bubbles:true}))}
    function edit(a){var t=target(a),el=t?t.el:document.activeElement,fill=a.action==='fill',text=a.text==null?'':String(a.text);
      if(!el||el===document.body)throw new Error('nothing is focused; pass ref');
      var inp=el.tagName==='INPUT'||el.tagName==='TEXTAREA';
      if(!inp&&!el.isContentEditable)throw new Error(desc(el)+' is not editable');
      el.focus();
      if(fill){if(inp)el.select();else getSelection().selectAllChildren(el)}
      else if(inp)try{el.setSelectionRange(el.value.length,el.value.length)}catch(e){}
      var before=inp?el.value:null,ok=false;
      try{ok=text?document.execCommand('insertText',false,text):(fill?document.execCommand('delete'):true)}catch(e){}
      if(inp){var want=fill?text:before+text;if(!ok||el.value!==want&&el.value===before)setv(el,want)}
      else if(!ok)el.textContent=(fill?'':el.textContent)+text;
      return(fill?'filled ':'typed into ')+desc(el)}
    var KC={Enter:13,Tab:9,Escape:27,Backspace:8,Delete:46,' ':32,ArrowLeft:37,ArrowUp:38,ArrowRight:39,ArrowDown:40,Home:36,End:35,PageUp:33,PageDown:34};
    function key(a){var t=target(a),el=t?t.el:(document.activeElement||document.body);
      if(t&&el.focus)el.focus();
      var ps=String(a.key||'').split('+'),k=ps.pop()||'+',i={bubbles:true,cancelable:true,composed:true,view:window};
      if(k==='Space')k=' ';if(k==='Return')k='Enter';if(k==='Esc')k='Escape';
      ps.forEach(function(p){p=p.toLowerCase();i[p==='cmd'||p==='meta'?'metaKey':p==='ctrl'?'ctrlKey':p==='alt'||p==='option'?'altKey':'shiftKey']=true});
      i.key=k;i.code=k===' '?'Space':k.length===1?(/[0-9]/.test(k)?'Digit'+k:'Key'+k.toUpperCase()):k;
      i.keyCode=i.which=KC[k]||(k.length===1?k.toUpperCase().charCodeAt(0):0);
      var go=el.dispatchEvent(new KeyboardEvent('keydown',i));
      if(go&&(k.length===1||k==='Enter'))go=el.dispatchEvent(new KeyboardEvent('keypress',i))&&go;
      if(go&&k==='Enter'&&el.tagName==='INPUT'&&el.form){if(el.form.requestSubmit)el.form.requestSubmit();else el.form.submit()}
      el.dispatchEvent(new KeyboardEvent('keyup',i));
      return'key '+a.key+(go?'':' (handled by page)')}
    function pick(a){var el=need(a).el,want=String(a.text==null?'':a.text);
      if(el.tagName!=='SELECT')throw new Error(desc(el)+' is not a <select>; click it instead');
      var os=[].slice.call(el.options),o=os.find(function(o){return o.value===want||o.text.trim()===want})||os.find(function(o){return o.text.toLowerCase().indexOf(want.toLowerCase())>=0});
      if(!o)throw new Error('no option '+JSON.stringify(want)+'; options: '+os.slice(0,20).map(function(o){return o.text.trim()}).join(' | '));
      el.value=o.value;el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));
      return'selected '+JSON.stringify(o.text.trim())+' in '+desc(el)}
    function scroll(a){var de=document.documentElement,pos=function(){return'scroll '+Math.round(scrollY)+'/'+Math.max(0,de.scrollHeight-innerHeight)};
      if(a.ref&&a.dy==null){get(a.ref).scrollIntoView({block:'center'});return pos()}
      var dy=a.dy==null?Math.round(innerHeight*0.8):a.dy,t=target(a),el=t&&t.el;
      while(el&&el!==document.body&&el!==de){var cs=getComputedStyle(el);if(el.scrollHeight>el.clientHeight+1&&/auto|scroll/.test(cs.overflowY)){el.scrollBy(0,dy);return'scrolled '+desc(el)+' to '+Math.round(el.scrollTop)+'/'+(el.scrollHeight-el.clientHeight)}el=el.parentElement}
      scrollBy(0,dy);return pos()}
    function checked(el){return el.type==='checkbox'||el.type==='radio'?el.checked:el.getAttribute('aria-checked')==='true'}
    function form(f){return Object.keys(f).map(function(r){try{var v=f[r],el=get(r),y=(el.type||'').toLowerCase();
        if(typeof v==='boolean'||y==='checkbox'||y==='radio'||el.getAttribute('role')==='checkbox'){var want=v===true||v==='true'||v==='on';
          if(checked(el)!==want)press(target({ref:r}));return(checked(el)===want?'':'! not changed: ')+desc(el)+(checked(el)?' checked':' unchecked')}
        if(el.tagName==='SELECT')return pick({ref:r,text:v});
        return edit({action:'fill',ref:r,text:v})}catch(e){return'! '+r+': '+(e.message||e)}}).join('\n')}
    function upload(a){var el=need(a).el;
      if(el.tagName!=='INPUT'||el.type!=='file')throw new Error(desc(el)+' is not a file input');
      var dt=new DataTransfer();(a.files||[]).forEach(function(f){var b=atob(f.b),u=new Uint8Array(b.length);for(var i=0;i<b.length;i++)u[i]=b.charCodeAt(i);dt.items.add(new File([u],f.n,{type:f.t}))});
      el.files=dt.files;el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));
      return'set '+el.files.length+' file(s) on '+desc(el)}
    // For waits: is the text, ref or selector present (and visible)?
    function has(a){var el;
      if(a.ref){var w=R.get(a.ref);el=w&&w.deref();if(el&&!el.isConnected)el=null}
      else if(a.selector)el=document.querySelector(a.selector);
      else return(document.body.innerText||'').toLowerCase().indexOf(String(a.text||'').toLowerCase())>=0;
      return!!el&&(!el.checkVisibility||el.checkVisibility({visibilityProperty:true,checkVisibilityCSS:true}))}
    function act(a){var t;S.fx=1;
      if(a.action==='click'||a.action==='dblclick'||a.action==='key')watch();
      switch(a.action){
        case'click':t=need(a);if(/^(INPUT|TEXTAREA|SELECT)$/.test(t.to.tagName)||t.to.isContentEditable)S.fx=1;press(t);return'clicked '+desc(t.el);
        case'dblclick':t=need(a);press(t);press(t,{detail:2});mev(t.to,'dblclick',t.x,t.y,{detail:2});return'double-clicked '+desc(t.el);
        case'hover':t=need(a);['pointerover','mouseover','pointerenter','mouseenter','pointermove','mousemove'].forEach(function(e){mev(t.to,e,t.x,t.y)});return'hover events sent to '+desc(t.el)+' (CSS :hover styles need os:true)';
        case'type':return edit(a);
        case'fill':return a.fields?form(a.fields):edit(a);
        case'key':return key(a);
        case'select':return pick(a);
        case'scroll':return scroll(a);
        case'upload':return upload(a);
        case'dialog':S.dp=a.text==null?'accept':String(a.text);return'next dialog: '+(S.dp==='accept'||S.dp==='dismiss'?S.dp:'answer '+JSON.stringify(S.dp));
        default:throw new Error('unknown action '+a.action)}}
    function geom(a){var t=target(a),g={iw:innerWidth,ih:innerHeight};
      if(t){g.x=t.x;g.y=t.y;g.d=desc(t.el);if(t.r)g.r=[t.r.left,t.r.top,t.r.width,t.r.height]}return g}

    function fmt(v){if(typeof v==='string')return v;if(v instanceof Error)return v.name+': '+v.message;try{return JSON.stringify(v)}catch(e){return String(v)}}
    function push(arr,x){arr.push(x);arr.t=(arr.t||0)+1;if(arr.length>300)arr.shift()}
    // Bodies of text/JSON responses, kept for the last 50 requests.
    var BOD=new Map();
    function keep(id,ct,b){if(!/json|text|xml|javascript|html|csv/i.test(ct||''))return;BOD.set(id,{c:ct,b:String(b).slice(0,4000)});if(BOD.size>50)BOD.delete(BOD.keys().next().value)}
    function hook(){if(S.con)return false;S.con=[];S.net=[];S.nn=0;S.cur={};
      ['log','info','warn','error','debug'].forEach(function(l){var o=console[l];console[l]=function(){try{push(S.con,l+' '+[].map.call(arguments,fmt).join(' '))}catch(e){}return o.apply(console,arguments)}});
      addEventListener('error',function(e){push(S.con,'exception '+(e.message||(e.target&&(e.target.src||e.target.href))||'')+(e.filename?' @'+e.filename.split('/').pop()+':'+e.lineno:''))},true);
      addEventListener('unhandledrejection',function(e){push(S.con,'rejection '+fmt(e.reason))});
      var f=window.fetch;
      if(f)window.fetch=function(i,o){var u=typeof i==='string'?i:(i&&i.url)||String(i),m=(o&&o.method)||(i&&i.method)||'GET',t=performance.now(),id='n'+(++S.nn);
        return f.apply(this,arguments).then(function(r){push(S.net,id+' '+m+' '+r.status+' '+u+' '+Math.round(performance.now()-t)+'ms');
          try{var ct=r.headers.get('content-type');if(/json|text|xml|javascript|html|csv/i.test(ct||''))r.clone().text().then(function(b){keep(id,ct,b)},function(){})}catch(e){}return r},
          function(e){push(S.net,id+' '+m+' ERR '+u+' '+e);throw e})};
      var xo=XMLHttpRequest.prototype.open,xs=XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open=function(m,u){this.__q=[m,u];return xo.apply(this,arguments)};
      XMLHttpRequest.prototype.send=function(){var x=this,t=performance.now(),id='n'+(++S.nn);
        x.addEventListener('loadend',function(){if(!x.__q)return;push(S.net,id+' '+x.__q[0]+' '+(x.status||'ERR')+' '+x.__q[1]+' '+Math.round(performance.now()-t)+'ms');
          try{if(x.responseType===''||x.responseType==='text')keep(id,x.getResponseHeader('content-type'),x.responseText)}catch(e){}});return xs.apply(this,arguments)};
      return true}
    var STATIC=/^(img|css|link|script|font|video|audio|image|icon)$/;
    function logs(a){var fresh=hook(),net=a.kind==='network',kind=net?'net':'con',arr=net?S.net:S.con,note='';
      if(net&&a.id){var b=BOD.get(a.id),l=S.net.find(function(x){return x.indexOf(a.id+' ')===0});
        if(!l)return'no request '+a.id+' in the log';
        return clip(l,300)+(b?'\n'+b.c+'\n'+b.b.slice(0,(a.limit||40)*100):'\n(no body kept: only text/JSON bodies of the last 50 requests)')}
      var from=a.new&&S.cur[kind]!=null?arr.length-Math.min(arr.length,arr.t-S.cur[kind]):0;S.cur[kind]=arr.t||0;arr=arr.slice(from);
      if(net&&!S.nseen){S.nseen=1;var hid=0,res=performance.getEntriesByType('resource').filter(function(e){if(!a.pattern&&STATIC.test(e.initiatorType)){hid++;return false}return true});
        arr=res.map(function(e){return(e.initiatorType||'res')+' '+(e.responseStatus||'-')+' '+e.name+' '+Math.round(e.duration)+'ms'}).concat(arr);
        note='(fetch/XHR capture starts now; below: what this page loaded so far'+(hid?', without '+hid+' images/scripts/styles (pass pattern to include them)':'')+')\n'}
      else if(fresh)note='(capture starts now; earlier console output is not available)\n';
      if(!net&&a.level){var lv=a.level==='error'?/^(error|exception|rejection) /:/^(error|exception|rejection|warn) /;arr=arr.filter(function(l){return lv.test(l)})}
      if(a.pattern){var re;try{re=new RegExp(a.pattern,'i')}catch(e){}var p=a.pattern.toLowerCase();arr=arr.filter(function(l){return re?re.test(l):l.toLowerCase().indexOf(p)>=0})}
      var out=arr.slice(-(a.limit||30)).map(function(l){return clip(l,180)}).join('\n');
      if(a.clear){S.con.length=0;S.net.length=0;BOD.clear()}
      return note+(out||(a.new?'(nothing new)':'(no entries)'))}

    function ser(v){if(v===undefined)return'undefined';if(v instanceof Element)return desc(v);if(typeof v==='function')return String(v).slice(0,200);
      try{var j=JSON.stringify(v,function(k,x){return x instanceof Element?desc(x):typeof x==='bigint'?String(x):x});return j===undefined?String(v):j}catch(e){return String(v)}}
    // Page dialogs would block Apple Events until someone clicks them. Answer them here instead:
    // alert is acknowledged; confirm and prompt are dismissed unless act dialog chose otherwise.
    S.dlg=[];S.dp=null;
    ['alert','confirm','prompt'].forEach(function(t){window[t]=function(m,d){var p=S.dp,acc=t==='alert'||(p!=null&&p!=='dismiss'),v;S.dp=null;
      if(t==='confirm')v=acc;else if(t==='prompt')v=acc?(p&&p!=='accept'?p:d==null?'':String(d)):null;
      S.dlg.push(t+' '+JSON.stringify(clip(m,120))+' \u2192 '+(t==='prompt'&&acc?JSON.stringify(v):acc?'accepted':'dismissed'));return v}});
    addEventListener('beforeunload',function(){S.bye=Date.now()});addEventListener('pageshow',function(){S.bye=0});
    S.slot=function(id){var s=S.slots[id]={d:0};return{done:function(v){s.d=1;s.v=ser(v)},fail:function(e){s.d=1;s.e=String(e)}}};
    S.take=function(id){var s=S.slots[id];if(!s)return'{"x":1}';if(!s.d)return'{"p":1}';delete S.slots[id];return JSON.stringify(s.e?{e:s.e}:{v:s.v})};
    S.call=function(a){if(a.h!==S.h)return JSON.stringify({m:S.h||''});
      try{var v=a.op==='read'?read(a):a.op==='act'?act(a):a.op==='geom'?geom(a):a.op==='logs'?logs(a):a.op==='has'?has(a):null,o={v:v,u:location.href,r:document.readyState};if(S.dlg.length)o.d=S.dlg.splice(0);return JSON.stringify(o)}
      catch(e){return JSON.stringify({e:String(e&&e.message||e)})}};
    })()
    """#
}
