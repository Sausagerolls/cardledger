import Foundation

/// The single-page browser UI served by `LANServer`. Pure HTML/CSS/JS, no build step.
/// Fetches `/api/cards` (settings + cards + games), renders an inventory grid with a card
/// detail panel, a live sale-price calculator, and full add/edit/delete that POST back to
/// the phone.
enum WebUI {
    static let page = #"""
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>CardLedger</title>
<style>
  :root { --accent:#4F46E5; --accent2:#6366F1; --profit:#16A34A; --loss:#DC2626; --gold:#B8860B;
          --bg:#F2F2F7; --surface:#fff; --raised:#fafafa; --text:#1c1c1e; --muted:#6b7280; --line:rgba(128,128,128,.2); }
  @media (prefers-color-scheme: dark) {
    :root { --bg:#000; --surface:#1c1c1e; --raised:#2c2c2e; --text:#f2f2f7; --muted:#9ca3af; } }
  * { box-sizing:border-box; }
  body { margin:0; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif; background:var(--bg); color:var(--text); }
  header { position:sticky; top:0; backdrop-filter:saturate(180%) blur(20px);
           background:color-mix(in srgb, var(--bg) 80%, transparent);
           padding:16px 20px; display:flex; align-items:center; gap:14px; flex-wrap:wrap;
           border-bottom:1px solid var(--line); z-index:10; }
  header h1 { font-size:22px; margin:0; font-weight:800; }
  .grow { flex:1; }
  .btn { background:var(--accent); color:#fff; border:none; border-radius:12px; padding:10px 16px;
         font-size:15px; font-weight:600; cursor:pointer; text-decoration:none; display:inline-block; }
  .btn.secondary { background:var(--raised); color:var(--text); border:1px solid var(--line); }
  .btn.danger { background:var(--loss); }
  #search { flex:1; min-width:180px; max-width:420px; padding:12px 16px; border-radius:14px;
            border:1px solid var(--line); background:var(--surface); color:var(--text); font-size:16px; }
  main { padding:20px; }
  .grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(180px,1fr)); gap:14px; }
  .tile { background:var(--surface); border-radius:16px; overflow:hidden; cursor:pointer; border:1px solid var(--line); transition:transform .12s; }
  .tile:hover { transform:translateY(-3px); }
  .tile .img { height:170px; background:#8881; display:flex; align-items:center; justify-content:center; }
  .tile .img img { width:100%; height:100%; object-fit:cover; }
  .tile .img .ph { font-size:40px; opacity:.3; }
  .tile .meta { padding:12px; }
  .tile .name { font-weight:700; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .tile .code { font-family:ui-monospace,monospace; color:var(--muted); font-size:13px; margin:2px 0; }
  .tile .price { color:var(--gold); font-weight:800; }
  .pill { display:inline-block; background:color-mix(in srgb,var(--profit) 18%,transparent); color:var(--profit);
          border-radius:999px; padding:2px 10px; font-size:12px; font-weight:700; }
  .empty { text-align:center; color:var(--muted); padding:60px 20px; }
  .overlay { position:fixed; inset:0; background:rgba(0,0,0,.5); display:none; align-items:center; justify-content:center; padding:20px; z-index:20; }
  .overlay.open { display:flex; }
  .sheet { background:var(--bg); border-radius:22px; max-width:560px; width:100%; max-height:90vh; overflow:auto; padding:22px; }
  .sheet h2 { margin:0 0 4px; }
  .photos { display:flex; gap:10px; overflow-x:auto; margin:14px 0; }
  .photos img { height:240px; border-radius:14px; }
  .card { background:var(--surface); border-radius:16px; padding:16px; margin:12px 0; border:1px solid var(--line); }
  .row { display:flex; justify-content:space-between; padding:5px 0; font-size:15px; gap:10px; }
  .row .l { color:var(--muted); }
  .big { font-size:34px; font-weight:800; color:var(--accent); }
  input[type=range] { width:100%; accent-color:var(--accent); }
  label.f { display:block; font-size:13px; color:var(--muted); margin:10px 0 4px; }
  input.f, select.f, textarea.f { width:100%; padding:10px 12px; border-radius:10px; border:1px solid var(--line);
            background:var(--surface); color:var(--text); font-size:16px; }
  .frow { display:flex; gap:10px; } .frow > div { flex:1; }
  .actions { display:flex; gap:10px; flex-wrap:wrap; margin-top:16px; }
  .close { float:right; font-size:22px; cursor:pointer; color:var(--muted); border:none; background:none; }
  .toast { position:fixed; bottom:24px; left:50%; transform:translateX(-50%); background:var(--text); color:var(--bg);
           padding:12px 20px; border-radius:12px; font-weight:600; opacity:0; transition:opacity .25s; z-index:50; }
  .toast.show { opacity:1; }
</style>
</head>
<body>
<header>
  <h1>CardLedger</h1>
  <input id="search" placeholder="Search name or short code">
  <span class="grow"></span>
  <button class="btn" onclick="openAdd()">+ Add card</button>
  <a class="btn secondary" href="/export.csv">Export CSV</a>
</header>
<main>
  <div id="grid" class="grid"></div>
  <div id="empty" class="empty" style="display:none">No cards yet — add one.</div>
</main>

<div class="overlay" id="overlay" onclick="if(event.target===this)closeSheet()">
  <div class="sheet" id="sheet"></div>
</div>
<div class="toast" id="toast"></div>

<script>
let DATA = { settings:{}, cards:[], games:[] };
const CONDS = [['M','Mint'],['NM','Near Mint'],['LP','Lightly Played'],['MP','Moderately Played'],
               ['HP','Heavily Played'],['DMG','Damaged'],['GRADED','Graded / Slabbed']];
const money = v => new Intl.NumberFormat(undefined,{style:'currency',currency:(DATA.settings.currency||'GBP')}).format(v||0);
const esc = s => (s||'').replace(/[&<>"]/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[m]));

function salePrice(cost, profitPct){
  const s=DATA.settings, profit=profitPct/100, vat=(s.vatPercent||0)/100, net=cost*(1+profit);
  if(s.method==='marginScheme'){ const m=Math.max(net-cost,0), va=m*vat; return {sale:net+va,vat:va,profit:net-cost}; }
  const sale=net*(1+vat); return {sale,vat:sale-net,profit:net-cost};
}

function render(){
  const q=document.getElementById('search').value.toLowerCase().trim();
  const grid=document.getElementById('grid'); grid.innerHTML='';
  const cards=DATA.cards.filter(c=>!q||c.name.toLowerCase().includes(q)||c.shortCode.toLowerCase().includes(q)||(c.number||'').toLowerCase().includes(q)||(c.setName||'').toLowerCase().includes(q));
  document.getElementById('empty').style.display=cards.length?'none':'block';
  for(const c of cards){
    const img=c.photoCount>0?`<img src="/photo/${encodeURIComponent(c.shortCode)}/0">`:`<div class="ph">🂠</div>`;
    const el=document.createElement('div'); el.className='tile';
    el.innerHTML=`<div class="img">${img}</div><div class="meta"><div class="name">${esc(c.name)||'Untitled'}</div>
      <div class="code">${esc(c.shortCode)}</div><div class="price">${money(c.purchasePrice)} ${c.isSold?'<span class=pill>Sold</span>':''}</div></div>`;
    el.onclick=()=>openCard(c.shortCode);
    grid.appendChild(el);
  }
}

function openCard(code){
  const c=DATA.cards.find(x=>x.shortCode===code); if(!c) return;
  const def=DATA.settings.defaultProfitPercent||10;
  const photos=Array.from({length:c.photoCount},(_,i)=>`<img src="/photo/${encodeURIComponent(c.shortCode)}/${i}">`).join('');
  const sub=[c.setName,c.number,c.rarity].filter(Boolean).join(' · ');
  document.getElementById('sheet').innerHTML=`
    <button class="close" onclick="closeSheet()">✕</button>
    <h2>${esc(c.name)||'Untitled card'}</h2>
    <div class="code" style="color:var(--muted);font-family:ui-monospace,monospace">${esc(c.shortCode)}</div>
    ${photos?`<div class="photos">${photos}</div>`:''}
    <div class="card">
      <div class="row"><span class="l">${esc(c.game||'')}</span><span>${esc(c.condition||'')}</span></div>
      ${sub?`<div class="row"><span class="l">Details</span><span>${esc(sub)}</span></div>`:''}
      <div class="row"><span class="l">Paid</span><span style="color:var(--gold);font-weight:700">${money(c.purchasePrice)}</span></div>
      <div class="row"><span class="l">Quantity</span><span>${c.quantity}</span></div>
      <div class="row"><span class="l">Purchased</span><span>${esc(c.purchaseDate||'')}</span></div>
      ${c.notes?`<div class="row"><span class="l">Notes</span><span>${esc(c.notes)}</span></div>`:''}
    </div>
    <div class="card">
      <div class="row"><strong>Sale calculator</strong></div>
      <div class="row"><span class="l">Target profit</span><span id="pp">${def}%</span></div>
      <input type="range" min="0" max="100" value="${def}" id="slider" oninput="recalc(${c.purchasePrice})">
      <div class="row" style="align-items:baseline"><span class="l">List at</span><span class="big" id="sale"></span></div>
      <div class="row"><span class="l">Includes VAT</span><span id="vat"></span></div>
      <div class="row"><span class="l">Profit</span><span id="profit" style="color:var(--profit);font-weight:700"></span></div>
    </div>
    <div class="actions">
      <button class="btn" onclick="openEdit('${c.shortCode}')">Edit</button>
      <button class="btn secondary" onclick="markSold('${c.shortCode}',${!c.isSold})">${c.isSold?'Mark unsold':'Mark sold'}</button>
      <span class="grow"></span>
      <button class="btn danger" onclick="del('${c.shortCode}')">Delete</button>
    </div>`;
  openSheet(); recalc(c.purchasePrice);
}
function recalc(cost){
  const pp=+document.getElementById('slider').value; document.getElementById('pp').textContent=pp+'%';
  const r=salePrice(cost,pp);
  document.getElementById('sale').textContent=money(r.sale);
  document.getElementById('vat').textContent=money(r.vat);
  document.getElementById('profit').textContent=money(r.profit);
}

function condOptions(sel){ return CONDS.map(c=>`<option value="${c[0]}" ${c[0]===sel?'selected':''}>${c[1]}</option>`).join(''); }
function gameOptions(sel){ return DATA.games.map(g=>`<option value="${g.code}" ${g.code===sel?'selected':''}>${esc(g.name)}</option>`).join(''); }

function formFields(c){
  return `
    <label class="f">Name</label><input class="f" id="f_name" value="${esc(c.name||'')}">
    <div class="frow"><div><label class="f">Set</label><input class="f" id="f_set" value="${esc(c.setName||'')}"></div>
      <div><label class="f">Card number</label><input class="f" id="f_num" value="${esc(c.number||'')}"></div></div>
    <div class="frow"><div><label class="f">Rarity</label><input class="f" id="f_rar" value="${esc(c.rarity||'')}"></div>
      <div><label class="f">Condition</label><select class="f" id="f_cond">${condOptions(c.conditionRaw||'NM')}</select></div></div>
    <div class="frow"><div><label class="f">Price paid (${esc(DATA.settings.currency||'GBP')})</label><input class="f" id="f_price" type="number" step="0.01" value="${c.purchasePrice||0}"></div>
      <div><label class="f">Quantity</label><input class="f" id="f_qty" type="number" min="1" value="${c.quantity||1}"></div></div>
    <label class="f">Purchase date</label><input class="f" id="f_date" type="date" value="${c.purchaseISO||''}">
    <label class="f">Notes</label><textarea class="f" id="f_notes" rows="2">${esc(c.notes||'')}</textarea>`;
}
function readForm(){
  return { name:val('f_name'), setName:val('f_set'), number:val('f_num'), rarity:val('f_rar'),
    condition:val('f_cond'), rarity:val('f_rar'), quantity:+val('f_qty')||1,
    purchasePrice:+val('f_price')||0, purchaseDate:val('f_date'), notes:val('f_notes') };
}
const val=id=>{const e=document.getElementById(id); return e?e.value:'';};

function openEdit(code){
  const c=DATA.cards.find(x=>x.shortCode===code); if(!c) return;
  document.getElementById('sheet').innerHTML=`<button class="close" onclick="openCard('${code}')">✕</button>
    <h2>Edit card</h2><div class="code" style="color:var(--muted);font-family:ui-monospace,monospace">${esc(code)}</div>
    <div class="card">${formFields(c)}</div>
    <div class="actions"><button class="btn" onclick="saveEdit('${code}')">Save</button>
      <button class="btn secondary" onclick="openCard('${code}')">Cancel</button></div>`;
  openSheet();
}
async function saveEdit(code){ const b=readForm(); b.shortCode=code; await post('update',b); }

function openAdd(){
  const c={conditionRaw:'NM',quantity:1};
  document.getElementById('sheet').innerHTML=`<button class="close" onclick="closeSheet()">✕</button>
    <h2>Add card</h2>
    <div class="card"><label class="f">Game system</label><select class="f" id="f_game">${gameOptions(DATA.games[0]&&DATA.games[0].code)}</select>
    ${formFields(c)}</div>
    <div class="actions"><button class="btn" onclick="saveAdd()">Add card</button>
      <button class="btn secondary" onclick="closeSheet()">Cancel</button></div>`;
  openSheet();
}
async function saveAdd(){ const b=readForm(); b.gameCode=val('f_game'); if(!b.name){ toast('Enter a name'); return; } await post('create',b); }

async function markSold(code,sold){ await post('update',{shortCode:code,isSold:sold}); }
async function del(code){ if(!confirm('Delete this card?')) return; await post('delete',{shortCode:code}); }

async function post(action,body){
  try{
    const r=await fetch('/api/card/'+action,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
    const j=await r.json();
    toast(j.message||(j.ok?'Done':'Failed'));
    closeSheet();
    setTimeout(load,300);  // give the phone a beat to refresh its snapshot
  }catch(e){ toast('Network error'); }
}

function openSheet(){ document.getElementById('overlay').classList.add('open'); }
function closeSheet(){ document.getElementById('overlay').classList.remove('open'); }
function toast(msg){ const t=document.getElementById('toast'); t.textContent=msg; t.classList.add('show'); setTimeout(()=>t.classList.remove('show'),1800); }

document.getElementById('search').addEventListener('input', render);
async function load(){ try{ DATA=await (await fetch('/api/cards')).json(); render(); }catch(e){ document.getElementById('empty').style.display='block'; } }
load();
setInterval(()=>{ if(!document.getElementById('overlay').classList.contains('open')) load(); }, 5000);
</script>
</body>
</html>
"""#
}
