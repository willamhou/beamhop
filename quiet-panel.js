
(()=>{
  const root=document.getElementById('beamhop-inline');
  const q=s=>root.querySelector(s), qa=s=>Array.from(root.querySelectorAll(s));
  const original='业务数据不能离开公司内网。';
  let projects=[{id:'project-a',name:'客户 A'},{id:'project-b',name:'项目 B'}];
  let routes=[{id:'codex-a',app:'Codex',session:'部署方案',projectId:'project-a',title:'Codex · 部署方案',project:'客户 A',delivery:'draft',accept:['text','file','image']},{id:'claude-a',app:'Claude',session:'风险讨论',projectId:'project-a',title:'Claude · 风险讨论',project:'客户 A',delivery:'draft',accept:['text','file','image']},{id:'local-b',app:'本地 Agent',session:'内网试点',projectId:'project-b',title:'本地 Agent · 内网试点',project:'项目 B',delivery:'background',accept:['text']}];
  const design={width:520,spacing:12};
  let sequence=0,items=[{id:'selection',kind:'text',source:'邮件 · 客户 A',text:original,original}],routeId='codex-a',mode='compose',packet=null,dirty=false,pocket=[],pocketOpen=false,createKind=null,activeBatchId=null,records=[],lastRecordId=null;
  const demo={unavailable:false};
  const urls=new Set();
  const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const icon=name=>'<i data-lucide="'+name+'" aria-hidden="true"></i>';
  const btn=(action,label,extra='')=>'<button type="button" class="cursor-interaction" data-action="'+action+'" '+extra+'>'+label+'</button>';
  const route=()=>routes.find(r=>r.id===routeId)||routes[0];
  const deliveryLabel=r=>r.delivery==='background'?'后台发送 · 仅文本':'在原应用中继续编辑';
  const commandLike=()=>/^\s*\/[\p{L}\p{N}_-]*(?=\s|$)/mu.test(q('#bh-instruction').value);
  const packetHTML=batch=>'<small>给 Agent 的指令</small><p>'+esc(batch.instruction||'未填写，仅补充材料')+'</p>'+batch.materials.map(m=>m.kind==='text'?'<small>'+esc(m.source)+(m.original!==undefined&&m.text!==m.original?' · 已编辑':'')+'</small><p>'+esc(m.text)+'</p>':'<small>'+esc(m.kind==='image'?'图片':'文件')+'</small><p>'+esc(m.name)+'</p>').join('');
  function icons(){
    const paths={x:'M6 6l12 12M6 18L18 6',check:'M4 12l5 5L20 6',paperclip:'M21 11l-9 9a6 6 0 01-8-8L14 2a4 4 0 016 6L9 19a2 2 0 01-3-3L16 6',inbox:'M4 4h16l2 12v5H2v-5L4 4zM2 15h6l2 3h4l2-3h6','chevrons-up-down':'M8 9l4-4 4 4M8 15l4 4 4-4','message-square-plus':'M3 3h18v14H7l-4 4V3zM8 10h8M12 6v8','folder-plus':'M3 5h7l2 3h9v12H3V5zM8 14h8M12 10v8','file-text':'M6 2h8l4 4v16H6V2zM9 11h6M9 15h6'};
    root.querySelectorAll('[data-lucide]').forEach(el=>{const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');svg.setAttribute('viewBox','0 0 24 24');svg.setAttribute('fill','none');svg.setAttribute('stroke','currentColor');svg.setAttribute('stroke-width','1.5');svg.setAttribute('aria-hidden','true');svg.innerHTML='<path d="'+(paths[el.dataset.lucide]||paths['file-text'])+'"/>';el.replaceWith(svg);});
  }
  function resize(el){el.style.height='auto';el.style.height=el.scrollHeight+'px';}
  function notice(text){q('#bh-feedback').textContent=text;}
  function cleanItems(){return items.filter(m=>m.kind!=='text'||m.text.trim());}
  function update(){
    q('#bh-count').textContent=cleanItems().length;
    const missing=items.some(m=>m.missing),empty=!cleanItems().length&&!q('#bh-instruction').value.trim(),unsupported=cleanItems().filter(m=>!route().accept.includes(m.kind)),slash=commandLike();
    q('[data-action="hop"]').disabled=missing||empty||!!createKind||!!unsupported.length||(route().delivery==='background'&&slash);
    q('[data-action="hold"]').disabled=empty||!!createKind;
    q('[data-action="native-edit"]').disabled=missing||empty||!!createKind||!!unsupported.length;
    q('#bh-warning').hidden=!missing&&!unsupported.length;q('#bh-warning').textContent=missing?'附件已失效，请移除后重新添加。':unsupported.length?'当前连接只接收文本。请更换接收方，或移除 '+unsupported.map(m=>m.name).join('、')+'。':'';
    q('#bh-primary-label').textContent=route().delivery==='background'?'发送':'在 '+route().app+' 中继续编辑';
    q('[data-action="hop"]').setAttribute('aria-label',q('#bh-primary-label').textContent+'，模拟操作，Command 或 Control 加回车');
    q('[data-action="native-edit"]').textContent='在 '+route().app+' 中继续编辑';
    q('#bh-command-help').hidden=!slash;
    q('#bh-command-note').textContent='/ 命令需在原应用中选择；BH 保留输入原文。';
    q('#bh-action-note').textContent=route().delivery==='background'?'后台投递；收到接收确认后收起浮层。':'带入材料与指令，在原应用中确认发送。';
  }
  function snapshot(){return {instruction:q('#bh-instruction').value,routeId,materials:cleanItems().map(m=>({...m}))};}
  const statusLabel=record=>record.status==='prepared'?'已带入草稿 · 发送状态未确认':record.status==='confirmed'?'接收端已确认 · 任务状态未知':'交接未开始 · 内容已保留';
  function addRecord(batch,intent,status){const record={id:'record-'+(++sequence),batch:{...batch,materials:batch.materials.map(m=>({...m}))},receiver:{...routes.find(r=>r.id===batch.routeId)},intent,status};records.push(record);lastRecordId=record.id;return record;}
  const lastRecord=()=>records.find(r=>r.id===lastRecordId);
  function persist(){
    dirty=true;

    const serialize=list=>list.map(({url,file,...m})=>m.kind==='text'?m:{...m,missing:true});
    const privateContent={version:3,routeId,instruction:q('#bh-instruction').value,items:serialize(items),mode,packet:packet?{...packet,materials:serialize(packet.materials)}:null,design,projects,routes,pocket:pocket.map(batch=>({...batch,materials:serialize(batch.materials)})),records:records.map(record=>({...record,batch:{...record.batch,materials:serialize(record.batch.materials)}})),lastRecordId,activeBatchId,pocketOpen,sequence};
    try { sessionStorage.setItem('beamhop-flow-v3-'+document.documentElement.lang, JSON.stringify({privateContent})); }
    catch { notice('当前页可继续编辑，但浏览器未能保存草稿；关闭页面前请复制重要内容。'); }

  }
  function renderCaptured(){
    q('#bh-items').innerHTML=items.filter(m=>!m.addition).map(m=>{
      if(m.kind==='text')return '<div class="bh-text-row" data-id="'+esc(m.id)+'"><div class="bh-source-line"><span class="bh-source-name">'+esc(m.source)+'</span><span class="bh-edited" '+(m.text===m.original?'hidden':'')+'>已编辑</span><button type="button" class="bh-mini cursor-interaction" data-action="original" aria-expanded="false">查看原文</button><button type="button" class="bh-remove cursor-interaction" data-action="remove" aria-label="移除选中文字">'+icon('x')+'</button></div><textarea rows="1" aria-label="选中文字，可直接编辑" maxlength="5000"></textarea><div class="bh-original" hidden><p>'+esc(m.original)+'</p>'+btn('restore','恢复为原文')+'</div></div>';
      return '<div data-id="'+esc(m.id)+'"><div class="bh-file-row">'+(m.kind==='image'&&m.url?'<button type="button" class="bh-image-button cursor-interaction" data-action="preview" aria-label="预览 '+esc(m.name)+'" aria-expanded="false"><img src="'+esc(m.url)+'" alt="'+esc(m.name)+'"></button>':'<span class="bh-file-icon">'+icon('file-text')+'</span>')+'<span class="bh-file-copy"><strong>'+esc(m.name)+'</strong><small>'+(m.missing?'需要重新选择':m.kind==='image'?'图片':'文件')+' · '+esc(m.sizeLabel)+'</small></span><button type="button" class="bh-remove cursor-interaction" data-action="remove" aria-label="移除 '+esc(m.name)+'">'+icon('x')+'</button></div>'+(m.url?'<img class="bh-image-preview" src="'+esc(m.url)+'" alt="'+esc(m.name)+'" hidden>':'')+'</div>';
    }).join('');
    qa('.bh-text-row').forEach(row=>{const m=items.find(m=>m.id===row.dataset.id),el=row.querySelector('textarea');el.value=m.text;resize(el);});icons();update();
  }
  function appendInput(item){
    const row=document.createElement('div');row.className='bh-add-row';row.dataset.id=item.id;
    row.innerHTML='<span class="bh-plus" aria-hidden="true">＋</span><textarea rows="1" maxlength="5000" aria-label="补充材料" placeholder="输入或粘贴补充材料…"></textarea><button type="button" class="bh-remove cursor-interaction" data-action="remove" aria-label="移除这段补充文本" '+(!item.text?'hidden':'')+'>'+icon('x')+'</button>';
    const el=row.querySelector('textarea');el.value=item.text;q('#bh-additions').append(row);resize(el);
  }
  function ensureBlank(){if(!items.some(m=>m.addition&&!m.text.trim())){const item={id:'add-'+(++sequence),kind:'text',source:'补充文本',text:'',addition:true};items.push(item);appendInput(item);icons();}}
  function renderAdditions(){q('#bh-additions').innerHTML='';items.filter(m=>m.addition).forEach(appendInput);ensureBlank();}
  function renderRoute(){q('#bh-route-title').textContent=route().title;q('#bh-route-project').textContent=route().project;q('[data-action="destination"]').setAttribute('aria-label','更改接收方，当前为 '+route().project+'，'+route().title);}
  function hideMenu(focus=false){q('#bh-routes').hidden=true;q('#bh-routes').classList.remove('bh-creating','bh-menu-inline');createKind=null;update();q('[data-action="destination"]').setAttribute('aria-expanded','false');if(focus)q('[data-action="destination"]').focus({preventScroll:true});}
  function showRoutes(force=false){
    if(!force&&!q('#bh-routes').hidden){hideMenu(true);return;}setPocket(false);createKind=null;q('#bh-routes').classList.remove('bh-creating');
    q('#bh-routes').innerHTML='<div class="bh-menu-label">接收会话 · 接收方式为演示设定</div>'+routes.map(r=>'<button type="button" class="cursor-interaction" data-route="'+esc(r.id)+'" aria-pressed="'+(routeId===r.id)+'"><span><strong>'+esc(r.title)+'</strong><small>'+esc(r.project)+' · '+deliveryLabel(r)+'</small></span>'+(r.id===routeId?icon('check'):'')+'</button>').join('')+'<div class="bh-menu-separator"></div><button type="button" class="bh-create-action cursor-interaction" data-action="new-session">'+icon('message-square-plus')+'新建会话…</button><button type="button" class="bh-create-action cursor-interaction" data-action="new-project">'+icon('folder-plus')+'新建项目…</button>';
    q('#bh-routes').hidden=false;q('[data-action="destination"]').setAttribute('aria-expanded','true');icons();if(q('#bh-routes').getBoundingClientRect().top<root.getBoundingClientRect().top)q('#bh-routes').classList.add('bh-menu-inline');q('#bh-routes [aria-pressed="true"]').focus({preventScroll:true});
  }
  function showCreate(kind){
    createKind=kind;q('#bh-routes').classList.add('bh-creating');
    const projectField=kind==='project'?'<label class="bh-create-field" for="bh-project-name">项目名称<input id="bh-project-name" required maxlength="60" placeholder="例如：客户 C"></label>':'<label class="bh-create-field" for="bh-project-select">所属项目<select id="bh-project-select">'+projects.map(p=>'<option value="'+esc(p.id)+'" '+(p.id===route().projectId?'selected':'')+'>'+esc(p.name)+'</option>').join('')+'</select></label>';
    q('#bh-routes').innerHTML='<div id="bh-create-form" role="group" aria-label="新建接收会话"><div class="bh-create-heading"><strong>'+(kind==='project'?'新建项目与首个会话':'新建会话')+'</strong>'+btn('cancel-create','取消创建')+'</div><div class="bh-create-grid">'+projectField+'<label class="bh-create-field" for="bh-agent-select">接收应用<select id="bh-agent-select">'+['Codex','Claude','本地 Agent'].map(app=>'<option '+(app===route().app?'selected':'')+'>'+app+'</option>').join('')+'</select></label><label class="bh-create-field bh-full" for="bh-session-name">'+(kind==='project'?'首个会话名称':'会话名称')+' · 可选<input id="bh-session-name" maxlength="80" placeholder="新会话"></label></div><p class="bh-create-help">创建后选为接收方，当前材料和指令继续保留。</p><div class="bh-create-buttons"><button type="button" class="bh-create-primary cursor-interaction" data-action="confirm-create">创建并选用会话</button></div></div>';
    q('#bh-routes').hidden=false;update();(q('#bh-project-name')||q('#bh-session-name')).focus({preventScroll:true});
  }
  function createDestination(){
    if(!createKind)return;
    if(demo.unavailable){notice('接收应用暂不可用；创建信息和当前材料已保留。');return;}
    let project=projects.find(p=>p.id===q('#bh-project-select')?.value);
    if(createKind==='project'){
      const name=q('#bh-project-name').value.trim();if(!name){q('#bh-project-name').setCustomValidity('请填写项目名称');q('#bh-project-name').reportValidity();return;}
      if(projects.some(p=>p.name===name)){q('#bh-project-name').setCustomValidity('已有同名项目，请换个名称或取消后新建会话。');q('#bh-project-name').reportValidity();return;}
      project={id:'project-'+(++sequence),name};projects.push(project);
    }
    if(!project)return;
    const app=q('#bh-agent-select').value,session=q('#bh-session-name').value.trim()||'新会话';
    const id='route-'+(++sequence);routes.push({id,app,session,projectId:project.id,title:app+' · '+session,project:project.name,delivery:app==='本地 Agent'?'background':'draft',accept:app==='本地 Agent'?['text']:['text','file','image']});routeId=id;renderRoute();hideMenu(true);persist();notice('接收方已设为 '+project.name+' / '+app+' · '+session+'，尚未发送。');
  }
  function hasCurrent(){return mode==='compose'&&(cleanItems().length>0||q('#bh-instruction').value.trim());}
  function stashCurrent(){const batch={...snapshot(),id:activeBatchId||'batch-'+(++sequence)};const at=pocket.findIndex(b=>b.id===batch.id);if(at>=0)pocket[at]=batch;else pocket.push(batch);activeBatchId=null;return batch;}
  function setPocket(open){pocketOpen=open;q('#bh-pocket-panel').hidden=!open;q('[data-action="pocket"]').setAttribute('aria-expanded',String(open));if(open){hideMenu();renderPocket();}}
  function renderPocket(){
    q('#bh-pocket-count').textContent=pocket.length;
    q('.bh-pocket-trigger').classList.toggle('bh-has-records',!!records.length);
    q('#bh-pocket-panel').innerHTML='<div class="bh-pocket-head"><strong>Pocket 暂存 · '+pocket.length+' 批</strong>'+btn('close-pocket','收起列表')+'</div>'+(!pocket.length?'<p class="bh-pocket-empty">尚无暂存内容。点击「存入 Pocket」保存当前材料、指令和接收方。</p>':pocket.map(batch=>{const r=routes.find(r=>r.id===batch.routeId),snippet=batch.instruction||batch.materials.map(m=>m.text||m.name).join(' · ');return '<section class="bh-pocket-item" data-batch="'+esc(batch.id)+'"><strong>'+esc(r?.project||'未指定项目')+'</strong><small>'+esc(r?.title||'未指定接收方')+' · '+batch.materials.length+' 项材料</small><p class="bh-pocket-snippet">'+esc(snippet)+'</p><div class="bh-pocket-actions">'+btn('restore-batch',hasCurrent()?'暂存当前并恢复':'恢复到浮层')+(mode==='compose'&&batch.materials.length?btn('add-batch-materials','仅添加材料','data-tooltip="复制到当前浮层，沿用当前指令和接收方"'):'')+'</div></section>';}).join(''))+(records.length?'<div class="bh-pocket-section-label">最近交接 · 保留备份</div>'+records.slice().reverse().map(record=>'<section class="bh-pocket-item" data-record="'+record.id+'"><strong>'+esc(record.receiver.title)+'</strong><div class="bh-record-status">'+statusLabel(record)+'</div><small>'+esc(record.receiver.project)+' · '+record.batch.materials.length+' 项材料</small><div class="bh-pocket-actions">'+btn('view-record','查看记录')+(record.status!=='confirmed'?btn('recover-record',hasCurrent()?'暂存当前并恢复备份':'恢复备份'):'')+'</div></section>').join(''):'');icons();fitOverlays();
  }
  function fitOverlays(){if(!pocketOpen){q('.bh-stage').style.minHeight='';return;}q('.bh-stage').style.minHeight=Math.max(438,q('#bh-pocket-panel').offsetHeight+115)+'px';}
  function loadBatch(batch){items=batch.materials.map(m=>({...m}));routeId=batch.routeId;activeBatchId=batch.id;packet=null;q('#bh-instruction').value=batch.instruction;mode='compose';renderCaptured();renderAdditions();renderRoute();renderMode();}
  function restoreBatch(id){const batch=pocket.find(b=>b.id===id);if(!batch)return;const kept=hasCurrent();pocket=pocket.filter(b=>b.id!==id);if(kept)stashCurrent();loadBatch(batch);setPocket(false);renderPocket();fitOverlays();persist();notice(kept?'当前内容已存入 Pocket；所选批次已恢复到浮层，尚未发送。':'材料、指令和接收方已恢复到浮层，尚未发送。');q('#bh-instruction').focus({preventScroll:true});}
  function addBatchMaterials(id){const batch=pocket.find(b=>b.id===id);if(!batch||mode!=='compose')return;batch.materials.forEach(m=>items.push({...m,id:'material-'+(++sequence)}));renderCaptured();renderAdditions();setPocket(false);fitOverlays();persist();notice('材料已加入；当前指令和接收方不变，原批次仍在 Pocket。');}
  function recoverRecord(id){const record=records.find(r=>r.id===id);if(!record)return;const kept=hasCurrent();if(kept)stashCurrent();loadBatch({...record.batch,id:'batch-'+(++sequence)});setPocket(false);renderPocket();fitOverlays();persist();notice((kept?'当前内容已暂存。':'')+'已恢复 BH 交接时的备份；原应用里的后续修改不会同步回来。');q('#bh-instruction').focus({preventScroll:true});}
  function viewRecord(id){const record=records.find(r=>r.id===id);if(!record)return;if(hasCurrent())stashCurrent();lastRecordId=id;packet=record.batch;items=[];q('#bh-instruction').value='';mode=record.status==='prepared'?'prepared':record.status==='failed'?'failed':'receipt';setPocket(false);renderMode();renderPocket();fitOverlays();persist();notice('');}
  function renderMode(){
    q('.bh-window').hidden=mode==='idle';q('.bh-idle').hidden=mode!=='idle';q('.bh-composer').hidden=mode!=='compose';q('.bh-result').hidden=!['prepared','failed','receipt'].includes(mode);
    q('[data-action="last-record"]').hidden=!lastRecordId;
    if(mode==='idle')return;
    if(mode==='compose'){qa('textarea').forEach(resize);return;}
    const record=lastRecord(),r=record?.receiver||route();
    q('#bh-result-title').textContent=mode==='prepared'?'已在 '+r.app+' 准备草稿（模拟）':mode==='failed'?'未能打开 '+r.app:'接收端已确认（模拟）';
    q('#bh-result-description').textContent=mode==='prepared'?'接收会话：「'+r.session+'」。请在原应用中选择 / 命令、检查附件并确认发送。':mode==='failed'?'连接前发现应用不可用，未投递。材料、指令和接收方已保留，可恢复或复制文字。':'「'+r.session+'」已接收 '+packet.materials.length+' 项材料；这不代表任务已完成。';
    q('.bh-result-actions').innerHTML=(mode==='receipt'?'':btn('return-edit','恢复交接备份','data-tooltip="恢复交接时的内容，原应用里的后续修改不会同步回来"'))+btn('inspect-packet','查看交接内容')+(mode==='failed'?btn('copy-text','复制文字'):'')+btn('new','添加新材料');
    q('#bh-packet').hidden=true;
    icons();
  }
  function complete(kind){
    if(mode!=='compose'||q('[data-action="'+kind+'"]').disabled)return;
    if(kind==='hold'){
      stashCurrent();items=[];q('#bh-instruction').value='';mode='idle';packet=null;hideMenu();setPocket(false);q('.bh-idle>span').textContent='已存入 Pocket，尚未发送。';renderMode();renderPocket();persist();q('[data-action="pocket"]').focus({preventScroll:true});const pill=q('.bh-pocket-trigger');pill.classList.remove('bh-arrived');requestAnimationFrame(()=>pill.classList.add('bh-arrived'));notice('已暂存材料、指令和接收方；点击右下角 Pocket 可恢复。');return;
    }
    packet=snapshot();const intent=kind==='native-edit'?'draft':route().delivery,status=demo.unavailable?'failed':intent==='background'?'confirmed':'prepared';addRecord(packet,intent,status);
    activeBatchId=null;items=[];q('#bh-instruction').value='';mode=status==='confirmed'?'idle':status==='failed'?'failed':'prepared';hideMenu();setPocket(false);
    if(status==='confirmed')q('.bh-idle>span').textContent='接收端已确认，可继续手上的事。（模拟）';
    renderMode();renderPocket();fitOverlays();persist();
    if(mode!=='idle')q('.bh-result-actions button').focus({preventScroll:true});
    notice(status==='confirmed'?'已收到接收确认，任务是否完成由接收应用反馈。':status==='prepared'?'仅带入草稿，尚未确认发送。交接备份可从 Pocket 恢复。':'交接未开始，内容已保留。');
  }
  async function copyText(){
    const record=lastRecord();if(!record)return;
    const batch=record.batch,attachments=batch.materials.filter(m=>m.kind!=='text');
    const content=[record.receiver.project+' / '+record.receiver.title,'任务指令：'+(batch.instruction||'仅补充材料'),...batch.materials.filter(m=>m.kind==='text').map(m=>m.source+'\n'+m.text),...(attachments.length?['待手动添加的附件：'+attachments.map(m=>m.name).join('、')]:[])].join('\n\n');
    const button=q('[data-action="copy-text"]');button.disabled=true;
    try{await navigator.clipboard.writeText(content);notice('文字已复制，请在接收应用中粘贴。'+(attachments.length?'附件尚未带入，请手动添加。':''));}
    catch{notice('未能写入剪贴板。可展开「查看交接内容」手动复制，原材料仍保留。');}
    finally{if(button.isConnected)button.disabled=false;}
  }
  function addFiles(files){
    for(const file of files){const image=/^image\/(png|jpeg|webp|gif|avif|bmp)$/.test(file.type);const url=image?URL.createObjectURL(file):null;if(url)urls.add(url);items.push({id:'file-'+(++sequence),kind:image?'image':'file',name:file.name||'图片',sizeLabel:file.size<1024?file.size+' B':file.size<1048576?Math.ceil(file.size/1024)+' KB':(file.size/1048576).toFixed(1)+' MB',url,file});}
    renderCaptured();persist();notice('附件已带上，只保存在本次预览中。');
  }
  root.addEventListener('input',event=>{
    if(event.target.id==='bh-project-name')event.target.setCustomValidity('');
    if(event.target.tagName!=='TEXTAREA')return;
    resize(event.target);
    if(event.target.id!=='bh-instruction'){
      const row=event.target.closest('[data-id]'),m=items.find(m=>m.id===row?.dataset.id);if(!m)return;m.text=event.target.value;
      if(m.addition){row.querySelector('.bh-remove').hidden=!m.text;ensureBlank();}
      else row.querySelector('.bh-edited').hidden=m.text===m.original;
    }
    notice('');update();persist();
  });
  root.addEventListener('focusout',event=>{
    const row=event.target.closest('.bh-add-row');if(!row)return;
    const m=items.find(m=>m.id===row.dataset.id);
    if(m&&!m.text.trim()&&items.filter(m=>m.addition&&!m.text.trim()).length>1){items=items.filter(m=>m.id!==row.dataset.id);row.remove();}
  });
  root.addEventListener('click',event=>{
    const b=event.target.closest('button');if(!b)return;
    if(b.dataset.route){routeId=b.dataset.route;renderRoute();hideMenu(true);persist();return;}
    const row=b.closest('[data-id]'),m=items.find(m=>m.id===row?.dataset.id),a=b.dataset.action;
    if(a==='attach')q('#bh-files').click();
    if(a==='destination')showRoutes();
    if(a==='new-session')showCreate('session');
    if(a==='new-project')showCreate('project');
    if(a==='confirm-create')createDestination();
    if(a==='cancel-create'){hideMenu(true);notice('');}
    if(a==='pocket'){setPocket(!pocketOpen);fitOverlays();persist();}
    if(a==='close-pocket'){setPocket(false);fitOverlays();persist();q('[data-action="pocket"]').focus({preventScroll:true});}
    if(a==='restore-batch')restoreBatch(b.closest('[data-batch]').dataset.batch);
    if(a==='add-batch-materials')addBatchMaterials(b.closest('[data-batch]').dataset.batch);
    if(a==='original'){const box=row.querySelector('.bh-original');box.hidden=!box.hidden;b.setAttribute('aria-expanded',String(!box.hidden));b.textContent=box.hidden?'查看原文':'收起原文';}
    if(a==='restore'){m.text=m.original;const el=row.querySelector('textarea');el.value=m.text;resize(el);row.querySelector('.bh-edited').hidden=true;update();persist();el.focus({preventScroll:true});}
    if(a==='remove'){items=items.filter(item=>item.id!==m.id);row.remove();ensureBlank();update();persist();q('#bh-additions textarea').focus({preventScroll:true});}
    if(a==='preview'){const preview=row.querySelector('.bh-image-preview');preview.hidden=!preview.hidden;b.setAttribute('aria-expanded',String(!preview.hidden));}
    if(a==='hold'||a==='hop'||a==='native-edit')complete(a);
    if(a==='view-record'){
      const row=b.closest('[data-record]'),record=records.find(r=>r.id===row.dataset.record);let detail=row.querySelector('.bh-record-detail');
      if(!detail){detail=document.createElement('div');detail.className='bh-record-detail';detail.innerHTML=packetHTML(record.batch);row.append(detail);}else detail.hidden=!detail.hidden;
      b.textContent=detail.hidden?'查看记录':'收起详情';b.setAttribute('aria-expanded',String(!detail.hidden));fitOverlays();
    }
    if(a==='recover-record')recoverRecord(b.closest('[data-record]').dataset.record);
    if(a==='return-edit')recoverRecord(lastRecordId);
    if(a==='last-record')viewRecord(lastRecordId);
    if(a==='copy-text')copyText();
    if(a==='resume'){mode='compose';renderMode();persist();q('#bh-instruction').focus({preventScroll:true});notice('');}
    if(a==='new'||a==='capture'){items=[];packet=null;activeBatchId=null;mode='compose';setPocket(false);q('#bh-instruction').value='';renderCaptured();renderAdditions();renderMode();renderPocket();fitOverlays();persist();notice('');q('#bh-additions textarea').focus({preventScroll:true});}
    if(a==='inspect-packet'){
      const pane=q('#bh-packet');pane.hidden=!pane.hidden;
      b.textContent=pane.hidden?'查看交接内容':'收起交接内容';pane.innerHTML=packetHTML(packet);
    }
  });
  q('#bh-files').addEventListener('change',event=>{addFiles(Array.from(event.target.files));event.target.value='';});
  root.addEventListener('paste',event=>{if(mode!=='compose')return;const files=Array.from(event.clipboardData?.files||[]);if(files.length){event.preventDefault();addFiles(files);}});
  let dragDepth=0;
  root.addEventListener('dragenter',event=>{if(mode==='compose'&&event.dataTransfer?.types.includes('Files')){event.preventDefault();dragDepth++;q('.bh-window').classList.add('bh-drag');}});
  root.addEventListener('dragover',event=>{if(mode==='compose'&&event.dataTransfer?.types.includes('Files'))event.preventDefault();});
  root.addEventListener('dragleave',()=>{if(--dragDepth<=0){dragDepth=0;q('.bh-window').classList.remove('bh-drag');}});
  root.addEventListener('drop',event=>{if(mode!=='compose'||!event.dataTransfer?.files.length)return;event.preventDefault();dragDepth=0;q('.bh-window').classList.remove('bh-drag');addFiles(Array.from(event.dataTransfer.files));});
  root.addEventListener('keydown',event=>{if(event.isComposing)return;if(createKind&&event.key==='Enter'&&event.target.tagName==='INPUT'){event.preventDefault();createDestination();return;}if((event.metaKey||event.ctrlKey)&&event.key==='Enter'&&mode==='compose'&&!createKind){event.preventDefault();complete('hop');}if(event.key==='Escape'){if(!q('#bh-routes').hidden){event.preventDefault();hideMenu(true);}else if(pocketOpen){setPocket(false);fitOverlays();q('[data-action="pocket"]').focus({preventScroll:true});}}});
  document.addEventListener('click',event=>{const path=event.composedPath();if(!q('#bh-routes').hidden&&!path.includes(q('#bh-routes'))&&!path.includes(q('[data-action="destination"]')))hideMenu();if(pocketOpen&&!path.includes(q('.bh-dock'))){setPocket(false);fitOverlays();}});
  function applyDesign(){root.style.setProperty('--bh-width',design.width+'px');root.style.setProperty('--bh-gap',design.spacing+'px');qa('textarea').forEach(resize);}
  function restore(saved){
    const s=saved?.privateContent;if(s?.version!==3)return;
    if(s.version===3){
      if(Array.isArray(s.projects)&&s.projects.length)projects=s.projects;
      if(Array.isArray(s.routes)&&s.routes.length)routes=s.routes;
      if(Array.isArray(s.pocket))pocket=s.pocket.map(batch=>({...batch,materials:batch.materials.map(m=>m.kind==='text'?m:{...m,missing:true,url:null})}));
      if(Array.isArray(s.records))records=s.records.map(record=>({...record,batch:{...record.batch,materials:record.batch.materials.map(m=>m.kind==='text'?m:{...m,missing:true,url:null})}}));
      lastRecordId=s.lastRecordId||null;activeBatchId=s.activeBatchId||null;pocketOpen=!!s.pocketOpen;if(['compose','idle','prepared','failed','receipt'].includes(s.mode))mode=s.mode;sequence=Number(s.sequence)||0;
    }
    if(routes.some(r=>r.id===s.routeId))routeId=s.routeId;
    if(Array.isArray(s.items))items=s.items.filter(m=>m&&['text','file','image'].includes(m.kind)&&typeof m.id==='string').map(m=>m.kind==='text'?{...m,text:String(m.text||'')}:{...m,missing:true,url:null});
    sequence=Math.max(sequence,...items.map(m=>Number(m.id.split('-').pop())||0));
    q('#bh-instruction').value=typeof s.instruction==='string'?s.instruction:'';
    if(s.packet&&Array.isArray(s.packet.materials))packet=s.packet;
    if(['prepared','failed','receipt'].includes(mode)&&!lastRecord()){mode='compose';packet=null;}
    if(mode==='idle'&&lastRecord()?.status==='confirmed')q('.bh-idle>span').textContent='接收端已确认，可继续手上的事。（模拟）';
    if(s.design){design.width=Math.max(400,Math.min(600,Number(s.design.width)||520));design.spacing=Math.max(8,Math.min(20,Number(s.design.spacing)||12));}
  }
  let saved;try{saved=JSON.parse(sessionStorage.getItem('beamhop-flow-v3-'+document.documentElement.lang)||'null');}catch{}
  restore(saved);renderCaptured();renderAdditions();renderRoute();renderMode();renderPocket();setPocket(pocketOpen);applyDesign();
  const observer=new ResizeObserver(()=>{if(mode==='compose')qa('textarea').forEach(resize);});observer.observe(q('.bh-window'));
  document.querySelector('#receiver-unavailable').addEventListener('change',event=>{demo.unavailable=event.target.checked;});
  document.querySelector('#reset-demo').addEventListener('click',()=>{sessionStorage.removeItem('beamhop-flow-v3-'+document.documentElement.lang);location.reload();});
  window.addEventListener('pagehide' ,()=>{urls.forEach(url=>URL.revokeObjectURL(url));observer.disconnect();});
})();