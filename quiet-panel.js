'use strict';
(() => {
  const en = document.documentElement.lang === 'en';
  const words = {
    client: ['客户 A · 部署方案', 'Client A · Deployment plan'],
    product: ['项目 B · 部署试点', 'Project B · Deployment pilot'],
    original: ['业务数据不能离开公司内网。', 'Business data must stay on the company network.'],
    source: ['客户 A · 原邮件', 'Client A · Original email'],
    prompt: ['你的提示词', 'Your prompt'],
    noPrompt: ['未附加提示词，仅补充材料。', 'No added instruction; context only.'],
    close: ['收起', 'Close'],
    back: ['回到原消息', 'Back to the message'],
    link: ['只关联到这件工作，继续阅读', 'Link to this work and keep reading'],
    linked: ['已关联', 'Linked to'],
    linkedMessage: ['已保留原文、出处和提示词。', 'Original, source and prompt kept.'],
    held: ['已留在手边，继续阅读。', 'Held for later. Keep reading.'],
    undo: ['已撤销这次关联。', 'This link was undone.'],
    material: ['这次带上的内容', 'What goes with this handoff'],
    reason: ['本地线索', 'Local clue'],
    clientReason: ['这封邮件来自客户 A；工作记录中有同一客户的部署方案。原方案按云端部署设计。', 'This email is from Client A, whose deployment plan is in the work records. The existing plan assumes cloud deployment.'],
    productReason: ['你选择了项目 B。原记录是本地部署试点；这条客户要求是否适用，仍需判断。', 'You chose Project B. Its record is a local deployment pilot; applicability of this customer requirement still needs judgment.'],
    reference: ['项目 B · 试点记录', 'Project B · Pilot record'],
    referenceBody: ['内网试点运行在客户自管服务器；客户负责升级和备份；目前只完成内部试点。', 'Pilot on the company network, running on customer-managed servers. The customer handles upgrades and backups. Only an internal pilot is complete.'],
    referenceMatch: ['检索线索：选区与试点记录都提到“内网”。', 'Retrieval clue: the selection and pilot record both mention “company network”.'],
    conditions: ['这些条件尚未在客户 A 中确认。它是一份候选参考，不是已验证的解决方案。', 'These conditions have not been confirmed for Client A. This is a candidate reference, not a verified solution.'],
    referenceCheck: ['连同出处和适用条件带上', 'Include it with its source and conditions'],
    noReference: ['当前工作没有可用的跨项目参考。', 'No cross-project reference is available for this work.'],
    availableReference: ['相关经验 · 1', 'Reference · 1'],
    includedReference: ['已选参考 · 1', 'Included · 1'],
    preview: ['已准备草稿', 'Draft prepared'],
    unsent: ['尚未发送，也未执行。', 'Not sent or executed.'],
    failed: ['接收端暂不可用', 'Receiver unavailable'],
    retained: ['材料、提示词和参考已保留。稍后可以重试。', 'Material, prompt and reference are kept. You can retry later.'],
    retry: ['重试填入', 'Retry preparation'],
    destination: ['接收工作', 'Destination'],
    resume: ['接着哪件事做', 'Resume a work'],
    originalOnly: ['打开原工作；没有带入当前选区或提示词。', 'Original work opened; the current selection and prompt were not added.'],
    savedItem: ['有已关联的材料与交代', 'Linked material and instruction available'],
    clientPause: ['待确认客户侧服务器与运维安排。', 'Confirm customer servers and operational responsibilities.'],
    productPause: ['待核实正式交付的条件。', 'Check conditions for production delivery.'],
    resumeFailed: ['原工作保留着，没有夹带当前输入。', 'Original work is kept; the current input was not included.'],
    preparedMessage: ['草稿已留好，仍未发送。', 'Draft kept; still not sent.'],
    returnedMessage: ['已回到原消息。', 'Back at the original message.'],
    emptyReference: ['未加入其他项目的参考。', 'No reference from another project included.'],
    referenceUnavailable: ['没有相关记录；基础操作仍可使用。', 'No related records; basic actions remain available.']
  };
  const t = key => words[key][en ? 1 : 0];
  const $ = id => document.getElementById(id);
  const escape = s => String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const state = {target:'client', instruction:'', open:true, ready:false, include:false, detail:null, links:{}, prepared:{}, pending:null};
  let generation = 0, timer = null, lastUndo = null;
  const detail = $('detail-panel');
  const action = (id, label, primary=false) => '<button type="button" data-action="' + id + '"' + (primary ? ' class="default-action"' : '') + '>' + escape(label) + '</button>';
  const feedback = text => { $('feedback').textContent = text; };
  function resizeInput() { const field=$('quick-prompt');field.style.height='auto';field.style.height=Math.max(45,field.scrollHeight)+'px'; }
  function updateReference() {
    $('show-reference').hidden = !(state.open && state.ready && state.target === 'client');
    $('show-reference').textContent = t(state.include ? 'includedReference' : 'availableReference');
  }
  function cancelSuggestion() { generation++;clearTimeout(timer);timer=null; }
  function suggest() {
    cancelSuggestion();state.ready=false;updateReference();
    if (!state.open || state.target !== 'client' || $('suggestion-speed').value === 'none') return;
    const revision=generation;
    const arrive=()=>{if (revision !== generation || !state.open || state.target !== 'client') return;state.ready=true;updateReference();};
    if ($('suggestion-speed').value === 'cached') arrive();
    else timer=setTimeout(arrive,4000); // Deliberate scenario delay, not a benchmark.
  }
  function showDetail(kind, html) {
    state.detail=kind;detail.innerHTML=html;detail.hidden=false;
    $('show-material').setAttribute('aria-expanded',String(kind==='material'));
    $('show-reference').setAttribute('aria-expanded',String(kind==='reference'));
  }
  function hideDetail() {
    state.detail=null;detail.hidden=true;detail.innerHTML='';
    $('show-material').setAttribute('aria-expanded','false');$('show-reference').setAttribute('aria-expanded','false');
  }
  function openCapture() {
    state.open=true;$('quick-panel').hidden=false;$('reopen').hidden=true;hideDetail();feedback('');
    $('quick-target').value=state.target;$('quick-prompt').value=state.instruction;resizeInput();suggest();$('quick-prompt').focus({preventScroll:true});
  }
  function closeCapture(message) {
    state.open=false;cancelSuggestion();$('quick-panel').hidden=true;hideDetail();$('reopen').hidden=false;feedback(message);$('capture-selection').focus({preventScroll:true});
  }
  function packet(data) {
    return '<h3>'+escape(t('material'))+'</h3><p class="muted">'+escape(t('source'))+'</p><p>'+escape(t('original'))+'</p><p class="muted">'+escape(t('prompt'))+'</p><p class="literal">'+escape(data.instruction || t('noPrompt'))+'</p>' +
      (data.include ? '<hr><p class="muted">'+escape(t('reference'))+'</p><p>'+escape(t('referenceBody'))+'</p><p class="muted">'+escape(t('conditions'))+'</p>' : '<p class="muted">'+escape(t('emptyReference'))+'</p>');
  }
  function material() {
    const linked=Object.keys(state.links).map(t).join(en ? '; ' : '；');
    showDetail('material',packet({instruction:state.instruction,include:state.include && state.target==='client'}) + '<hr><p class="muted">'+escape(t('reason'))+'</p><p>'+escape(t(state.target==='client' ? 'clientReason':'productReason'))+'</p>' +
      (linked ? '<p class="muted">'+escape(t('linked')+': '+linked)+'</p>' : '') + '<div class="detail-actions">'+action('link',t('link'))+action('close',t('close'))+'</div>');
  }
  function reference() {
    showDetail('reference','<h3>'+escape(t('reference'))+'</h3><p class="muted">'+escape(t('referenceMatch'))+'</p><p>'+escape(t('referenceBody'))+'</p><p class="muted">'+escape(t('conditions'))+'</p><label class="check"><input type="checkbox" id="include-reference"'+(state.include?' checked':'')+'>'+escape(t('referenceCheck'))+'</label><div class="detail-actions">'+action('close',t('close'))+'</div>');
  }
  function snapshot() { return {instruction:state.instruction,include:state.target==='client' && state.include}; }
  function linkCurrent() {
    lastUndo={target:state.target,previous:state.links[state.target] ? structuredClone(state.links[state.target]) : null};
    state.links[state.target]=snapshot();closeCapture(t('linked')+' '+t(state.target)+' · '+t('linkedMessage'));$('undo-link').hidden=false;
  }
  function showWork(target,data,isResume) {
    const failed=$('receiver-unavailable').checked;
    state.pending={target,data:data ? structuredClone(data) : null,isResume};
    state.open=false;cancelSuggestion();$('quick-panel').hidden=true;$('reopen').hidden=false;
    feedback('');
    if (failed) {
      showDetail('failed','<h3>'+escape(t('failed'))+'</h3><p>'+escape(t(target))+'</p><p>'+escape(t(data?'retained':'resumeFailed'))+'</p><div class="detail-actions">'+action('back',t('back'))+action('retry',t('retry'),true)+'</div>');
    } else {
      if (data) state.prepared[target]=structuredClone(data);
      showDetail('receiver','<h3>'+escape(t(target))+'</h3><p class="muted">'+escape(t(data?'preview':'originalOnly'))+'</p>' + (data ? '<p>'+escape(t('unsent'))+'</p>'+packet(data) : '<p>'+escape(t(target==='client'?'clientPause':'productPause'))+'</p>')+'<div class="detail-actions">'+action('back',t('back'))+'</div>');
    }
    detail.querySelector('button')?.focus({preventScroll:true});
  }
  function prepare() {
    state.links[state.target]=snapshot();lastUndo=null;$('undo-link').hidden=true;
    showWork(state.target,state.links[state.target],false);
  }
  $('quick-prompt').addEventListener('input',event=>{state.instruction=event.target.value;resizeInput();if(state.detail==='material')material();});
  $('quick-target').addEventListener('change',()=>{state.target=$('quick-target').value;hideDetail();suggest();});
  $('capture-selection').addEventListener('click',openCapture);$('reopen').addEventListener('click',openCapture);
  $('show-material').addEventListener('click',()=>{if(state.detail==='material')hideDetail();else material();});
  $('show-reference').addEventListener('click',()=>{if(state.detail==='reference')hideDetail();else reference();});
  $('hold').addEventListener('click',()=>closeCapture(t('held')));$('prepare').addEventListener('click',prepare);
  $('suggestion-speed').addEventListener('change',()=>{if(state.detail==='reference')hideDetail();suggest();});
  $('resume-work').addEventListener('click',()=>{
    cancelSuggestion();state.open=false;$('quick-panel').hidden=true;$('reopen').hidden=false;
    showDetail('works','<h3>'+escape(t('resume'))+'</h3>'+['client','product'].map(key=>'<button type="button" class="work-choice" data-resume="'+key+'">'+escape(t(key))+'<small>'+escape(t(state.links[key]?'savedItem':key==='client'?'clientPause':'productPause'))+'</small></button>').join('')+'<div class="detail-actions">'+action('back',t('back'))+'</div>');
    detail.querySelector('button').focus({preventScroll:true});
  });
  detail.addEventListener('change',event=>{if(event.target.id==='include-reference'){state.include=event.target.checked;updateReference();}});
  detail.addEventListener('click',event=>{
    const button=event.target.closest('button');if(!button)return;
    if(button.dataset.resume){showWork(button.dataset.resume,state.links[button.dataset.resume],true);return;}
    const a=button.dataset.action;
    if(a==='close'){const trigger=state.detail==='reference'?'show-reference':'show-material';hideDetail();$(trigger).focus({preventScroll:true});}
    if(a==='link')linkCurrent();
    if(a==='retry' && state.pending)showWork(state.pending.target,state.pending.data,state.pending.isResume);
    if(a==='back')closeCapture(state.detail==='receiver' && state.pending?.data?t('preparedMessage'):t('returnedMessage'));
  });
  $('undo-link').addEventListener('click',()=>{if(!lastUndo)return;if(lastUndo.previous)state.links[lastUndo.target]=lastUndo.previous;else delete state.links[lastUndo.target];lastUndo=null;$('undo-link').hidden=true;feedback(t('undo'));});
  document.addEventListener('keydown',event=>{
    if(event.isComposing || event.keyCode===229)return;
    if(!($('quick-panel').contains(event.target)||detail.contains(event.target)))return;
    if(event.key==='Escape'){event.preventDefault();if(state.detail){hideDetail();if(state.open)$('quick-prompt').focus({preventScroll:true});else closeCapture('');}else closeCapture('');}
    if(event.metaKey && event.key==='Enter' && state.open){event.preventDefault();prepare();}
    if(event.metaKey && event.key==='5' && state.open){event.preventDefault();closeCapture(t('held'));}
  });
  $('reset-demo').addEventListener('click',()=>{
    cancelSuggestion();Object.assign(state,{target:'client',instruction:'',open:true,ready:false,include:false,detail:null,links:{},prepared:{},pending:null});lastUndo=null;$('undo-link').hidden=true;$('receiver-unavailable').checked=false;$('suggestion-speed').value='cached';openCapture();
  });
  resizeInput();suggest();
})();
