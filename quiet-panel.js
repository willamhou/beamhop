'use strict';
(() => {
  const en = document.documentElement.lang === 'en';
  const words = {
    client:['客户 A','Client A'], product:['项目 B','Project B'],
    plan:['部署方案','Deployment plan'], review:['风险评审','Risk review'], manual:['手动交接','Manual handoff'], pilot:['部署试点','Deployment pilot'],
    original:['业务数据不能离开公司内网。','Business data must stay on the company network.'],
    source:['邮件 · 客户 A','Mail · Client A'], clip:['邮件选区','Email selection'],
    text:['文本','Text'], file:['文件','File'], image:['图片','Image'],
    reference:['项目 B · 内网试点记录','Project B · Network pilot record'],
    referenceBody:['内网试点运行在客户自管服务器；客户负责升级和备份；目前只完成内部试点。','Pilot on the company network, running on customer-managed servers. The customer handles upgrades and backups. Only an internal pilot is complete.'],
    referenceMatch:['检索线索：选区与试点记录都提到“内网”。','Retrieval clue: the selection and pilot record both mention “company network”.'],
    conditions:['这些条件尚未在客户 A 中确认。这是一份候选参考，不是已验证的解决方案。','These conditions have not been confirmed for Client A. This is a candidate reference, not a verified solution.'],
    addReference:['连同出处和适用条件加入','Add with its source and conditions'], included:['已加入参考','Reference included'], available:['可加入参考 · 1','Reference available · 1'],
    close:['收起详情','Close details'], back:['回到原消息','Back to the message'], remove:['移除','Remove'],
    materials:['这次带上的材料','Material for this handoff'], add:['添加材料','Add material'],
    addText:['添加文本','Add text'], editText:['编辑文本','Edit text'], textName:['补充文本','Additional text'], manualSource:['手动添加的文本','Manually added text'],
    textTitle:['标题','Title'], textBody:['文本内容','Text content'], textPlaceholder:['输入或粘贴要带上的材料…','Type or paste material to include…'],
    textHelp:['更改自动保留，交接时使用修改后的内容。原文仅留在本页供对照，出处继续保留。','Changes are kept automatically; the edited content is used for handoff. The original stays in this page for comparison, and its source is retained.'],
    newTextHelp:['输入的文字作为一份独立材料保留；给 Agent 的任务仍写在指令框里。','This text is a separate piece of material; write the task for the agent in the instruction field.'],
    originalText:['原始文本','Original text'], editedText:['本次交接文本 · 已编辑','Handoff text · Edited'], originalVersion:['查看原始文本','View original text'],
    restoreOriginal:['恢复原文','Restore original'], done:['完成','Done'], emptyText:['文本内容为空：','Empty text: '], emptyTextHelp:['。请补充内容或移除这项。','. Add content or remove this item.'],
    addFile:['添加示例文件','Add a sample file'], addImage:['添加示例图片','Add a sample image'], addLocal:['从本机选择…','Choose from this device…'],
    addHint:['也可以拖入文件，或在输入区粘贴图片。文件不会上传。','You can also drop files or paste an image into the input. Files are not uploaded.'],
    fileName:['部署约束.md','deployment-notes.md'], imageName:['内网示意图.svg','network-diagram.svg'],
    fixture:['演示样例','Demo sample'], local:['本机选择 · 仅保留在本页','From this device · Kept only in this page'],
    fileNote:['带上文件本体；不会假装已经读取或解析正文。','The file itself is included. Its contents have not been read or parsed.'],
    fixtureFileNote:['示例文件：客户自管服务器、升级与备份责任，以及内部试点的范围。','Sample file: customer-managed servers, upgrade and backup responsibilities, and the limits of the internal pilot.'],
    empty:['尚未添加材料','No material added'], destination:['交给哪个应用、哪场会话','Choose an app and session'],
    connectionHint:['以下均为模拟的已连接去处；能力按连接区分，不代表这些应用当前支持情况。','These are simulated connected destinations. Capabilities belong to each example connection, not to the apps in general.'],
    background:['后台交接 · 文本、文件、图片','Background handoff · Text, files, images'], draft:['填入草稿 · 仅文本','Draft preparation · Text only'], copy:['手动复制 · 仅文本','Manual copy · Text only'],
    send:['发送','Send'], fill:['填入草稿 ↗','Fill draft ↗'], copyAction:['复制','Copy'],
    bgHint:['后台交接，留在当前应用','Handoff in the background; stay in this app'], draftHint:['将打开接收应用；只填入，不发送','Opens the receiving app; prepares a draft without sending'], copyHint:['复制后需自行核对会话并粘贴','Check the session and paste manually after copying'],
    unsupported:['该去处不能接收这些附件：','This destination cannot receive these attachments: '], unsupportedEnd:['。请换去处，或检查后移除；不会只发送文字。','. Choose another destination or review and remove them; text will not be sent on its own.'],
    noContent:['先添加材料，或写一句指令。','Add material or write an instruction first.'],
    prompt:['给 Agent 的指令','Instruction for the agent'], noPrompt:['仅补充材料；没有要求启动新任务。','Context only; no request to start a new task.'],
    held:['已先留着，继续阅读。','Held for later. Keep reading.'], sent:['接收端已确认；仍在原处。','Receipt confirmed; you stayed at the source.'],
    filled:['已填入草稿，尚未发送。','Draft prepared; not sent.'], copied:['已复制；尚未交接给接收方。','Copied; not yet handed to the receiver.'],
    failed:['连接前已不可用，尚未发出；材料与指令已保留。','Unavailable before the attempt; nothing was sent. Material and instruction are kept.'],
    copyFailed:['未能复制。材料与指令仍在，可以重试或手动选取下方内容。','Could not copy. Material and instruction are kept; retry or select the content below manually.'],
    retry:['重试原去处','Retry the original destination'], retryHelp:['重试使用本次记录的材料和接收位置，不使用你后来改选的去处。','Retry uses this record’s material and destination, not a later selection.'],
    receipt:['交接记录','Handoff record'], noExecution:['接收确认不表示 Agent 已执行或完成。','A receipt does not mean the agent has executed or completed the work.'],
    contextReceipt:['本次只补充上下文，没有发起新的执行请求。','This handoff adds context without requesting a new task.'],
    originalWork:['已打开原会话；没有带入当前材料或指令。','Original session opened; current material and instruction were not added.'],
    openUnavailable:['接收方暂不可用。当前输入和暂存均已保留。','The receiver is unavailable. Your current input and held batches are kept.'], returned:['已回到原消息。','Back at the original message.'],
    shelf:['先留着的材料','Held batches'], restore:['继续这份材料','Continue this batch'], restoreKeep:['先留住当前输入，再恢复','Keep current input, then restore'],
    restoreNotice:['当前输入已先留着，已恢复所选材料；尚未发送。','Current input held; selected batch restored. Nothing was sent.'], restored:['已恢复这份材料；尚未发送。','Batch restored; nothing was sent.'],
    resume:['接着哪场会话做','Resume a session'], busy:['正在复制…','Copying…'], countSuffix:[' 项',' items'], more:['更多材料','More material'], view:['查看材料','Inspect material'], closeShelf:['收起暂存','Close held batches'],
    history:['交接记录','Handoff history'], backHistory:['所有交接记录','All handoff records'], recover:['取回材料，不发送','Recover material without sending'], recoverKeep:['先留住当前输入，再取回','Keep current input, then recover'],
    statusSent:['已接收','Received'],statusFilled:['已填草稿','Draft prepared'],statusCopied:['已复制，待交接','Copied; handoff pending'],statusFailed:['未发出，可重试','Not sent; retry available'],statusCopyFailed:['复制失败','Copy failed']
  };
  const t = key => words[key][en ? 1 : 0];
  const $ = id => document.getElementById(id);
  const escape = s => String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  // Fictional capability assignments, not claims about these apps' actual APIs.
  const routes = [
    {id:'a-codex',work:'client',app:'Codex',session:'plan',mode:'background',accept:['text','file','image']},
    {id:'a-claude',work:'client',app:'Claude',session:'review',mode:'draft',accept:['text']},
    {id:'a-chatgpt',work:'client',app:'ChatGPT',session:'manual',mode:'copy',accept:['text']},
    {id:'b-codex',work:'product',app:'Codex',session:'pilot',mode:'background',accept:['text','file','image']}
  ];
  const route = id => routes.find(r=>r.id===id);
  const routeName = id => {const r=route(id);return r.app+' · '+t(r.session);};
  let sequence=0, generation=0, timer=null;
  const objectUrls=new Set();
  const sampleClip = () => ({id:'clip',kind:'text',name:t('clip'),source:t('source'),text:t('original'),originalText:t('original')});
  const newBatch = routeId => ({id:'batch-'+(++sequence),routeId,instruction:'',materials:[sampleClip()],dirty:false});
  const snapshot = batch => ({...batch,materials:batch.materials.map(m=>({...m}))});
  const materialVersion = items => JSON.stringify(items.map(m=>['id','kind','name','text','originalText','source','conditions','url','size'].map(key=>m[key])));
  const sameBatch = (a,b) => a?.id===b.id&&a.instruction===b.instruction&&a.routeId===b.routeId&&materialVersion(a.materials)===materialVersion(b.materials);
  const editedText = m => m.kind==='text' && m.originalText!==undefined && m.text!==m.originalText;
  const hasContent = batch => !!batch && (!!batch.materials.length || !!batch.instruction.trim());
  const state={batch:newBatch('a-codex'),lastRoute:'a-codex',open:true,detail:null,picker:null,ready:false,shelf:[],receipts:[],lastReceipt:null,busy:false};
  const button=(action,label,extra='')=>'<button type="button" data-action="'+action+'" '+extra+'>'+escape(label)+'</button>';
  const feedback=message=>{$('feedback').textContent=message;};
  const sizeText=bytes=>bytes<1024?bytes+' B':bytes<1048576?Math.round(bytes/1024)+' KB':(bytes/1048576).toFixed(1)+' MB';
  const materialIcon=m=>m.kind==='image'?'<img src="'+escape(m.url)+'" alt="">':'<span class="kind-icon" aria-hidden="true">'+(m.kind==='file'?escape((m.name.split('.').pop()||'FILE').slice(0,4).toUpperCase()):'“”')+'</span>';
  function cancelSuggestion(){generation++;clearTimeout(timer);timer=null;}
  function updateReference(){const included=state.batch?.materials.some(m=>m.id==='reference');$('show-reference').hidden=!(state.open&&state.ready);$('show-reference').textContent=t(included?'included':'available');}
  function suggest(){
    cancelSuggestion();state.ready=false;updateReference();
    if(!state.open||!state.batch||route(state.batch.routeId).work!=='client'||!state.batch.materials.some(m=>m.id==='clip'&&(en?/company network/i:/内网/).test(m.text))||$('suggestion-speed').value==='none')return;
    const revision=generation,batchId=state.batch.id;
    const arrive=()=>{if(revision!==generation||!state.open||state.batch?.id!==batchId)return;state.ready=true;updateReference();};
    if($('suggestion-speed').value==='cached')arrive();else timer=setTimeout(arrive,4000);
  }
  function resizeInput(){const field=$('quick-prompt');field.style.height='auto';field.style.height=Math.max(52,field.scrollHeight)+'px';}
  function hidePicker(focus=false){
    const trigger=state.picker==='add'?'add-material':'choose-destination';state.picker=null;$('inline-picker').hidden=true;$('inline-picker').innerHTML='';
    $('add-material').setAttribute('aria-expanded','false');$('choose-destination').setAttribute('aria-expanded','false');if(focus&&state.open)$(trigger).focus({preventScroll:true});
  }
  function showDetail(kind,html){state.detail=kind;$('detail-panel').innerHTML=html;$('detail-panel').hidden=false;$('show-material').setAttribute('aria-expanded',String(kind==='materials'));$('show-reference').setAttribute('aria-expanded',String(kind==='reference'));}
  function hideDetail(){state.detail=null;$('detail-panel').hidden=true;$('detail-panel').innerHTML='';$('show-material').setAttribute('aria-expanded','false');$('show-reference').setAttribute('aria-expanded','false');}
  function unsupported(batch){return batch.materials.filter(m=>!route(batch.routeId).accept.includes(m.kind));}
  function renderRoute(){
    if(!state.batch)return;
    const r=route(state.batch.routeId),missing=unsupported(state.batch),blankText=state.batch.materials.filter(m=>m.kind==='text'&&!m.text.trim()),empty=!state.batch.materials.length&&!state.batch.instruction.trim();
    $('receiver-name').textContent=routeName(r.id);$('work-name').textContent=t(r.work);$('choose-destination').title=t(r.work)+' / '+routeName(r.id);
    $('action-label').textContent=t(r.mode==='background'?'send':r.mode==='draft'?'fill':'copyAction');$('prepare').disabled=!!missing.length||!!blankText.length||empty||state.busy;$('hold').disabled=!!blankText.length||empty||state.busy;
    $('route-hint').textContent=blankText.length?t('emptyText')+blankText.map(m=>m.name).join(en?', ':'、')+t('emptyTextHelp'):missing.length?t('unsupported')+missing.map(m=>m.name).join(en?', ':'、')+t('unsupportedEnd'):t(r.mode==='background'?'bgHint':r.mode==='draft'?'draftHint':'copyHint');$('route-hint').classList.toggle('route-warning',!!missing.length||!!blankText.length);
  }
  function renderMaterials(){
    const items=state.batch?.materials||[];$('material-count').textContent=String(items.length);
    $('material-chips').innerHTML=items.slice(0,2).map(m=>'<span class="material-chip"><button type="button" data-inspect="'+escape(m.id)+'" title="'+escape(m.name)+'" aria-label="'+escape(t(m.kind==='text'?'editText':'view')+' · '+m.name)+'">'+materialIcon(m)+'<span>'+escape(m.name)+'</span></button><button type="button" class="remove-chip" data-remove="'+escape(m.id)+'" aria-label="'+escape(t('remove')+' '+m.name)+'">×</button></span>').join('')+(items.length>2?'<button type="button" class="more-materials" data-all="true" aria-label="'+escape(t('more'))+'">+'+(items.length-2)+'</button>':'')+(!items.length?'<span class="empty-materials">'+escape(t('empty'))+'</span>':'');renderRoute();updateReference();
  }
  function syncCapture(){document.querySelector('.panel-stage').style.minHeight='';$('quick-panel').hidden=false;$('quick-prompt').value=state.batch.instruction;resizeInput();renderMaterials();$('reopen').hidden=true;state.open=true;suggest();}
  function openCapture(){if(state.busy)return;if(!state.batch)state.batch=newBatch(state.lastRoute);hideDetail();hidePicker();feedback('');syncCapture();$('quick-prompt').focus({preventScroll:true});}
  function closeCapture(message=''){const stage=document.querySelector('.panel-stage');stage.style.minHeight=stage.getBoundingClientRect().height+'px';state.open=false;cancelSuggestion();hidePicker();hideDetail();$('quick-panel').hidden=true;$('reopen').hidden=!state.batch;feedback(message);$('capture-selection').focus({preventScroll:true});}
  function materialHTML(m,editable=false){
    return '<section class="material-detail"><div class="material-title">'+materialIcon(m)+'<strong>'+escape(m.name)+'</strong><span class="muted">'+escape(t(m.kind))+(m.size===undefined?'':' · '+sizeText(m.size))+'</span></div><p class="muted">'+escape(m.source)+'</p>'+(m.kind==='text'?(editedText(m)?'<p class="edited-label">'+escape(t('editedText'))+'</p>':'')+'<p class="literal">'+escape(m.text)+'</p>'+(editable?originalHTML(m):''):m.kind==='image'?'<img class="image-preview" src="'+escape(m.url)+'" alt="'+escape(m.name)+'">':'<p>'+escape(m.fixture?t('fixtureFileNote'):t('fileNote'))+'</p>')+(m.conditions?'<p class="muted">'+escape(m.conditions)+'</p>':'')+(editable?'<div class="material-actions">'+(m.kind==='text'?'<button type="button" data-edit="'+escape(m.id)+'">'+escape(t('editText'))+'</button>':'')+'<button type="button" data-remove="'+escape(m.id)+'">'+escape(t('remove'))+'</button></div>':'')+'</section>';
  }
  function originalHTML(m){return m.originalText===undefined?'':'<details class="original-text"><summary>'+escape(t('originalVersion'))+'</summary><p class="literal">'+escape(m.originalText)+'</p></details>';}
  function editText(id){
    if(state.busy||!state.batch)return;
    const m=state.batch.materials.find(item=>item.id===id&&item.kind==='text');if(!m)return;
    hidePicker();
    showDetail('text-editor','<section id="text-editor" data-material="'+escape(m.id)+'"><h3>'+escape(t(m.originalText===undefined&&!m.text?'addText':'editText'))+'</h3><p class="muted">'+escape(m.source)+'</p><label for="material-title-input">'+escape(t('textTitle'))+'</label><input id="material-title-input" type="text" maxlength="160"><label for="material-text-input">'+escape(t('textBody'))+'</label><textarea id="material-text-input" rows="5" placeholder="'+escape(t('textPlaceholder'))+'" aria-describedby="text-editor-help"></textarea><p id="text-editor-help" class="muted">'+escape(t(m.originalText===undefined?'newTextHelp':'textHelp'))+'</p><p id="text-edit-state" class="edited-label" hidden>'+escape(t('editedText'))+'</p>'+originalHTML(m)+(m.conditions?'<p class="muted">'+escape(m.conditions)+'</p>':'')+'<div class="detail-actions">'+(m.originalText===undefined?'':button('restore-original',t('restoreOriginal')))+'<button type="button" data-remove="'+escape(m.id)+'">'+escape(t('remove'))+'</button>'+button('finish-text',t('done'))+'</div></section>');
    $('material-title-input').value=m.name;$('material-text-input').value=m.text;
    updateEditorState(m);$('material-text-input').focus({preventScroll:true});
  }
  function updateEditorState(m){
    $('text-edit-state').hidden=!editedText(m);
    const restoreButton=$('text-editor').querySelector('[data-action="restore-original"]');if(restoreButton)restoreButton.disabled=!editedText(m);
  }
  function addText(){
    const item={id:'material-'+(++sequence),kind:'text',name:t('textName'),source:t('manualSource'),text:''};
    addMaterials([item]);editText(item.id);
  }
  function showMaterials(id){if(!state.batch)return;const items=id?state.batch.materials.filter(m=>m.id===id):state.batch.materials;showDetail('materials','<h3>'+escape(t('materials'))+' · '+state.batch.materials.length+'</h3>'+items.map(m=>materialHTML(m,true)).join('')+(!items.length?'<p>'+escape(t('empty'))+'</p>':'')+'<div class="detail-actions">'+button('close',t('close'))+'</div>');}
  function showReference(){if(!state.batch||!state.ready)return;const added=state.batch.materials.some(m=>m.id==='reference');showDetail('reference','<h3>'+escape(t('reference'))+'</h3><p class="muted">'+escape(t('referenceMatch'))+'</p><p>'+escape(t('referenceBody'))+'</p><p class="muted">'+escape(t('conditions'))+'</p><div class="detail-actions">'+button('reference',t(added?'remove':'addReference'))+button('close',t('close'))+'</div>');}
  function addMaterials(items){if(!state.batch)state.batch=newBatch(state.lastRoute);state.batch.materials.push(...items);state.batch.dirty=true;hidePicker();renderMaterials();suggest();if(state.detail==='materials')showMaterials();}
  function removeMaterial(id){if(!state.batch)return;state.batch.materials=state.batch.materials.filter(m=>m.id!==id);state.batch.dirty=true;renderMaterials();suggest();if(state.detail==='materials'||state.detail==='text-editor')showMaterials();else if(state.detail==='reference')showReference();$('show-material').focus({preventScroll:true});}
  function addFiles(files){
    const items=Array.from(files).map(file=>{const kind=/^image\/(png|jpeg|webp|gif|avif|bmp)$/.test(file.type)?'image':'file';let url=null;if(kind==='image'){url=URL.createObjectURL(file);objectUrls.add(url);}return {id:'material-'+(++sequence),kind,name:file.name||t(kind),source:t('local'),size:file.size,file,url};});if(items.length)addMaterials(items);
  }
  function showPicker(kind){
    if(state.picker===kind){hidePicker(true);return;}hideDetail();state.picker=kind;
    const content=kind==='add'?'<h3>'+escape(t('add'))+'</h3>'+button('add-text',t('addText'))+button('sample-file',t('addFile'))+button('sample-image',t('addImage'))+button('local-files',t('addLocal'))+'<p>'+escape(t('addHint'))+'</p>':'<h3>'+escape(t('destination'))+'</h3>'+routes.map(r=>'<button type="button" data-route="'+r.id+'" aria-pressed="'+String(state.batch.routeId===r.id)+'"><strong>'+escape(routeName(r.id))+'</strong><span>'+escape(t(r.work)+' · '+t(r.mode))+'</span></button>').join('')+'<p>'+escape(t('connectionHint'))+'</p>';
    $('inline-picker').innerHTML=content;$('inline-picker').hidden=false;$('inline-picker').setAttribute('role','dialog');$('inline-picker').setAttribute('aria-label',t(kind==='add'?'add':'destination'));
    $('add-material').setAttribute('aria-expanded',String(kind==='add'));$('choose-destination').setAttribute('aria-expanded',String(kind==='destination'));positionPicker();($('inline-picker').querySelector('[aria-pressed="true"]')||$('inline-picker').querySelector('button')).focus({preventScroll:true});
  }
  function positionPicker(){
    if(!state.picker)return;
    const picker=$('inline-picker'),panel=$('quick-panel').getBoundingClientRect(),anchor=$(state.picker==='add'?'add-material':'choose-destination').getBoundingClientRect();
    const below=innerHeight-anchor.bottom-12,above=anchor.top-12;
    picker.style.position='fixed';picker.style.width=Math.min(panel.width-24,innerWidth-16)+'px';picker.style.left=Math.max(8,Math.min(panel.left+12,innerWidth-(panel.width-24)-8))+'px';picker.style.right='auto';
    picker.style.maxHeight='none';
    const natural=picker.scrollHeight+2,down=below>=Math.min(natural,260)||below>=above,space=down?below:above;
    const available=space<100?innerHeight-16:space;
    picker.style.maxHeight=Math.max(80,available)+'px';
    const height=Math.min(natural,available);
    picker.style.top=(space<100?8:down?anchor.bottom+5:anchor.top-5-height)+'px';
  }
  function stash(batch){const saved=snapshot(batch);saved.dirty=true;const i=state.shelf.findIndex(b=>b.id===batch.id);if(i<0)state.shelf.push(saved);else state.shelf[i]=saved;renderShelf();}
  function renderShelf(){
    $('batch-shelf').hidden=!state.shelf.length;$('shelf-count').textContent=String(state.shelf.length);
    $('shelf-panel').innerHTML='<h3>'+escape(t('shelf'))+'</h3>'+state.shelf.map(b=>'<section class="saved-batch"><strong>'+escape(routeName(b.routeId))+'</strong><small>'+escape(t(route(b.routeId).work)+' · '+b.materials.length+t('countSuffix'))+'</small><p>'+escape(b.instruction||b.materials.map(m=>m.name).join(en?', ':'、'))+'</p><button type="button" data-restore="'+b.id+'">'+escape(t(hasContent(state.batch)&&state.batch.id!==b.id?'restoreKeep':'restore'))+'</button></section>').join('')+'<button type="button" data-action="close-shelf">'+escape(t('closeShelf'))+'</button>';
    if(!state.shelf.length){$('shelf-panel').hidden=true;$('shelf-toggle').setAttribute('aria-expanded','false');}
  }
  function hold(){if(!state.batch||$('hold').disabled)return;stash(state.batch);state.lastRoute=state.batch.routeId;state.batch=null;closeCapture(t('held'));}
  function restore(id){
    const selected=state.shelf.find(b=>b.id===id);if(!selected)return;const kept=hasContent(state.batch)&&state.batch.id!==id;if(kept)stash(state.batch);
    state.shelf=state.shelf.filter(b=>b.id!==id);state.batch=snapshot(selected);state.lastRoute=selected.routeId;$('shelf-panel').hidden=true;$('shelf-toggle').setAttribute('aria-expanded','false');renderShelf();openCapture();feedback(t(kept?'restoreNotice':'restored'));
  }
  function packetHTML(batch){return '<p class="muted">'+escape(t(route(batch.routeId).work)+' / '+routeName(batch.routeId))+'</p><h4>'+escape(t('prompt'))+'</h4><p class="literal">'+escape(batch.instruction||t('noPrompt'))+'</p><h4>'+escape(t('materials'))+' · '+batch.materials.length+'</h4>'+batch.materials.map(m=>materialHTML(m)).join('');}
  function packetText(batch){return [t(route(batch.routeId).work)+' / '+routeName(batch.routeId),t('prompt')+': '+(batch.instruction||t('noPrompt')),...batch.materials.map(m=>m.name+'\n'+m.source+'\n'+(editedText(m)?t('editedText')+'\n':'')+m.text+(m.conditions?'\n'+m.conditions:''))].join('\n\n');}
  function record(batch,status,previous=null){const receipt=previous||{id:'receipt-'+(++sequence),batch:snapshot(batch)};receipt.status=status;if(!previous)state.receipts.push(receipt);state.lastReceipt=receipt;$('view-receipt').hidden=false;$('open-receiver').hidden=status!=='sent';return receipt;}
  function showHistory(){
    if(state.receipts.length===1){showReceipt(state.receipts[0]);return;}
    const statusKey={sent:'statusSent',filled:'statusFilled',copied:'statusCopied',failed:'statusFailed',copyFailed:'statusCopyFailed'};
    showDetail('history','<h3>'+escape(t('history'))+'</h3>'+[...state.receipts].reverse().map(r=>'<button type="button" class="work-choice" data-record="'+r.id+'"><strong>'+escape(routeName(r.batch.routeId))+'</strong><small>'+escape(t(statusKey[r.status])+' · '+r.batch.materials.length+t('countSuffix'))+'</small><span class="record-snippet">'+escape(r.batch.instruction||t('noPrompt'))+'</span></button>').join('')+'<div class="detail-actions">'+button('close',t('close'))+'</div>');
  }
  function showReceipt(receipt=state.lastReceipt){
    if(!receipt)return;const failed=receipt.status==='failed'||receipt.status==='copyFailed';
    showDetail('receipt','<h3>'+escape(t('receipt'))+'</h3><p>'+escape(t(receipt.status))+'</p>'+(receipt.status==='sent'?'<p class="muted">'+escape(t('noExecution'))+'</p>'+(!receipt.batch.instruction.trim()?'<p class="muted">'+escape(t('contextReceipt'))+'</p>':''):'')+packetHTML(receipt.batch)+'<div class="detail-actions">'+(failed?button('retry',t('retry'),'data-receipt="'+receipt.id+'"'):'')+button('recover',t(hasContent(state.batch)?'recoverKeep':'recover'),'data-receipt="'+receipt.id+'"')+(state.receipts.length>1?button('history',t('backHistory')):'')+button('close',t('close'))+'</div>'+(failed?'<p class="muted">'+escape(t('retryHelp'))+'</p>':''));
  }
  function openWork(routeId,prepared=null){closeCapture('');showDetail('work','<h3>'+escape(routeName(routeId))+'</h3><p>'+escape(t($('receiver-unavailable').checked?'openUnavailable':prepared?'filled':'originalWork'))+'</p>'+(!$('receiver-unavailable').checked&&prepared?packetHTML(prepared):'<p class="muted">'+escape(t(route(routeId).work))+'</p>')+'<div class="detail-actions">'+button('back',t('back'))+'</div>');$('detail-panel').querySelector('button').focus({preventScroll:true});}
  async function deliver(batch,retryRecord=null){
    if(state.busy)return;const frozen=snapshot(batch),r=route(frozen.routeId);
    const blankText=frozen.materials.filter(m=>m.kind==='text'&&!m.text.trim());if(blankText.length){feedback(t('emptyText')+blankText.map(m=>m.name).join(', ')+t('emptyTextHelp'));return;}
    if(unsupported(frozen).length){feedback(t('unsupported')+unsupported(frozen).map(m=>m.name).join(', '));return;}
    if(!frozen.materials.length&&!frozen.instruction.trim()){feedback(t('noContent'));return;}
    if(r.mode!=='copy'&&$('receiver-unavailable').checked){const rec=record(frozen,'failed',retryRecord);closeCapture(t('failed'));showReceipt(rec);return;}
    if(r.mode==='copy'){
      state.busy=true;feedback(t('busy'));document.querySelectorAll('#quick-panel button,#quick-panel textarea,#text-editor button,#text-editor input,#text-editor textarea').forEach(el=>{el.disabled=true;});
      try{await navigator.clipboard.writeText(packetText(frozen));}
      catch{const rec=record(frozen,'copyFailed',retryRecord);state.busy=false;document.querySelectorAll('#quick-panel button,#quick-panel textarea,#text-editor button,#text-editor input,#text-editor textarea').forEach(el=>{el.disabled=false;});renderRoute();closeCapture(t('copyFailed'));showReceipt(rec);return;}
      state.busy=false;document.querySelectorAll('#quick-panel button,#quick-panel textarea,#text-editor button,#text-editor input,#text-editor textarea').forEach(el=>{el.disabled=false;});
    }
    const status=r.mode==='background'?'sent':r.mode==='draft'?'filled':'copied';record(frozen,status,retryRecord);
    // A retry must not consume a newer capture or a changed version of its input.
    if(sameBatch(state.batch,frozen)){state.lastRoute=frozen.routeId;state.batch=null;}
    state.shelf=state.shelf.filter(b=>!sameBatch(b,frozen));renderShelf();if(r.mode==='draft')openWork(frozen.routeId,frozen);else closeCapture(t(status));
  }
  function reset(){
    if(state.busy)return;cancelSuggestion();objectUrls.forEach(url=>URL.revokeObjectURL(url));objectUrls.clear();
    Object.assign(state,{batch:newBatch('a-codex'),lastRoute:'a-codex',open:true,detail:null,picker:null,ready:false,shelf:[],receipts:[],lastReceipt:null});$('receiver-unavailable').checked=false;$('suggestion-speed').value='cached';$('view-receipt').hidden=true;$('open-receiver').hidden=true;renderShelf();openCapture();
  }
  $('quick-prompt').addEventListener('input',event=>{state.batch.instruction=event.target.value;state.batch.dirty=true;resizeInput();renderRoute();});
  $('quick-prompt').addEventListener('paste',event=>{if(event.clipboardData?.files.length){event.preventDefault();addFiles(event.clipboardData.files);}});
  $('quick-panel').addEventListener('dragover',event=>{event.preventDefault();event.dataTransfer.dropEffect='copy';});$('quick-panel').addEventListener('drop',event=>{event.preventDefault();if(!state.busy)addFiles(event.dataTransfer.files);});
  $('capture-selection').addEventListener('click',openCapture);$('reopen').addEventListener('click',openCapture);
  $('show-material').addEventListener('click',()=>{hidePicker();if(state.detail==='materials')hideDetail();else showMaterials();});$('show-reference').addEventListener('click',()=>{hidePicker();if(state.detail==='reference')hideDetail();else showReference();});
  $('add-material').addEventListener('click',()=>showPicker('add'));$('choose-destination').addEventListener('click',()=>showPicker('destination'));
  $('hold').addEventListener('click',hold);$('prepare').addEventListener('click',()=>{if(state.batch)deliver(state.batch);});$('suggestion-speed').addEventListener('change',()=>{if(state.detail==='reference')hideDetail();suggest();});
  $('file-input').addEventListener('change',event=>{addFiles(event.target.files);event.target.value='';});
  $('inline-picker').addEventListener('click',event=>{
    const b=event.target.closest('button');if(!b)return;
    if(b.dataset.action==='add-text'){addText();return;}
    if(b.dataset.route){state.batch.routeId=b.dataset.route;state.lastRoute=b.dataset.route;state.batch.dirty=true;hidePicker(true);renderRoute();suggest();return;}
    if(b.dataset.action==='sample-file')addMaterials([{id:'material-'+(++sequence),kind:'file',name:t('fileName'),source:t('fixture'),fixture:true,url:'./deployment-notes.md'}]);
    if(b.dataset.action==='sample-image')addMaterials([{id:'material-'+(++sequence),kind:'image',name:t('imageName'),source:t('fixture'),fixture:true,url:'./material-sample.svg'}]);
    if(b.dataset.action==='local-files'){hidePicker();$('file-input').click();}$('add-material').focus({preventScroll:true});
  });
  $('material-chips').addEventListener('click',event=>{const b=event.target.closest('button');if(!b)return;if(b.dataset.remove)removeMaterial(b.dataset.remove);else if(state.batch.materials.some(m=>m.id===b.dataset.inspect&&m.kind==='text'))editText(b.dataset.inspect);else showMaterials(b.dataset.inspect);});
  $('detail-panel').addEventListener('input',event=>{
    if(!['material-title-input','material-text-input'].includes(event.target.id)||state.busy)return;
    const id=$('text-editor')?.dataset.material,m=state.batch?.materials.find(item=>item.id===id);if(!m)return;
    if(event.target.id==='material-title-input')m.name=event.target.value.trim()||t('textName');else m.text=event.target.value;
    state.batch.dirty=true;renderMaterials();updateEditorState(m);suggest();
  });
  $('detail-panel').addEventListener('click',event=>{
    const b=event.target.closest('button');if(!b)return;if(b.dataset.edit){editText(b.dataset.edit);return;}if(b.dataset.remove){removeMaterial(b.dataset.remove);return;}if(b.dataset.openWork){openWork(b.dataset.openWork);return;}if(b.dataset.record){showReceipt(state.receipts.find(r=>r.id===b.dataset.record));return;}const a=b.dataset.action;
    if(a==='finish-text'){hideDetail();$('show-material').focus({preventScroll:true});}
    if(a==='restore-original'){
      const m=state.batch?.materials.find(item=>item.id===$('text-editor')?.dataset.material);if(m?.originalText!==undefined){m.text=m.originalText;state.batch.dirty=true;$('material-text-input').value=m.text;renderMaterials();updateEditorState(m);suggest();$('material-text-input').focus({preventScroll:true});}
    }
    if(a==='close'){hideDetail();(state.open?$('show-material'):$('capture-selection')).focus({preventScroll:true});}
    if(a==='back'){hideDetail();feedback(t('returned'));$('capture-selection').focus({preventScroll:true});}
    if(a==='reference'){if(state.batch.materials.some(m=>m.id==='reference'))removeMaterial('reference');else addMaterials([{id:'reference',kind:'text',name:t('reference'),source:t('reference')+' · '+t('fixture'),text:t('referenceBody'),originalText:t('referenceBody'),conditions:t('conditions')}]);showReference();}
    if(a==='retry'){const rec=state.receipts.find(item=>item.id===b.dataset.receipt);if(rec&&(rec.status==='failed'||rec.status==='copyFailed'))deliver(rec.batch,rec);}
    if(a==='history')showHistory();
    if(a==='recover'){const rec=state.receipts.find(item=>item.id===b.dataset.receipt);if(rec){const kept=hasContent(state.batch);if(kept)stash(state.batch);state.batch={...snapshot(rec.batch),id:'batch-'+(++sequence),dirty:true};state.lastRoute=state.batch.routeId;openCapture();feedback(t(kept?'restoreNotice':'restored'));}}
  });
  $('view-receipt').addEventListener('click',showHistory);$('open-receiver').addEventListener('click',()=>{if(state.lastReceipt)openWork(state.lastReceipt.batch.routeId);});
  $('resume-work').addEventListener('click',()=>{closeCapture('');showDetail('works','<h3>'+escape(t('resume'))+'</h3>'+routes.map(r=>'<button type="button" class="work-choice" data-open-work="'+r.id+'">'+escape(routeName(r.id))+'<small>'+escape(t(r.work))+'</small></button>').join('')+'<p class="muted">'+escape(t('originalWork'))+'</p><div class="detail-actions">'+button('back',t('back'))+'</div>');$('detail-panel').querySelector('button').focus({preventScroll:true});});
  $('shelf-toggle').addEventListener('click',()=>{renderShelf();const open=$('shelf-panel').hidden;$('shelf-panel').hidden=!open;$('shelf-toggle').setAttribute('aria-expanded',String(open));if(open)$('shelf-panel').querySelector('button')?.focus({preventScroll:true});});
  $('shelf-panel').addEventListener('click',event=>{const b=event.target.closest('button');if(!b)return;if(b.dataset.restore)restore(b.dataset.restore);else{$('shelf-panel').hidden=true;$('shelf-toggle').setAttribute('aria-expanded','false');$('shelf-toggle').focus({preventScroll:true});}});
  document.addEventListener('click',event=>{if(state.picker&&!$('inline-picker').contains(event.target)&&!$('choose-destination').contains(event.target)&&!$('add-material').contains(event.target))hidePicker();});
  window.addEventListener('resize',positionPicker);
  window.addEventListener('scroll',()=>{
    if(!state.picker)return;
    const anchor=$(state.picker==='add'?'add-material':'choose-destination').getBoundingClientRect();
    if(anchor.bottom<0||anchor.top>innerHeight)hidePicker();else positionPicker();
  },{passive:true});
  document.addEventListener('keydown',event=>{
    if(event.isComposing||event.keyCode===229||state.busy)return;
    if(event.key==='Escape'){
      if(!$('shelf-panel').hidden){event.preventDefault();$('shelf-panel').hidden=true;$('shelf-toggle').setAttribute('aria-expanded','false');$('shelf-toggle').focus({preventScroll:true});}
      else if(state.picker){event.preventDefault();hidePicker(true);}
      else if($('quick-panel').contains(event.target)||$('detail-panel').contains(event.target)){event.preventDefault();if(state.detail){hideDetail();(state.open?$('quick-prompt'):$('capture-selection')).focus({preventScroll:true});}else closeCapture();}
    }
    if(!$('quick-panel').contains(event.target)||!state.open)return;
    if(event.metaKey&&event.key==='Enter'){event.preventDefault();if(!$('prepare').disabled)deliver(state.batch);}
    if(event.metaKey&&event.key==='5'){event.preventDefault();hold();}
  });
  $('reset-demo').addEventListener('click',reset);renderMaterials();resizeInput();suggest();
})();
