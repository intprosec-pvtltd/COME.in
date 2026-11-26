import React,{useEffect,useState} from 'react';import{createRoot}from'react-dom/client';import{BarChart3,Download,Eye,EyeOff,Trash2,Upload,LayoutDashboard,Users,Wallet,Megaphone,Wrench,Settings,LogOut,RefreshCw}from'lucide-react';import './style.css';
const API=(import.meta.env.VITE_API_URL||'http://127.0.0.1:8000').replace(/\/$/, '');
const currency=new Intl.NumberFormat('en-IN',{style:'currency',currency:'INR'});
const amount=value=>value==null?'—':currency.format(Number(value));
const month=()=>{const date=new Date();return `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}`};
const Attributions=({login=false})=> <div className="attribution"><span>by</span><img src={login?"/branding/intprosec_admin_signin.jpg":"/intprosec.webp"} alt="IntProSec"/></div>;
function App(){const[token,setToken]=useState(sessionStorage.getItem('pg_token')||'');const[me,setMe]=useState(null);const[error,setError]=useState('');const[tab,setTab]=useState('Overview');const[data,setData]=useState({});const [showPassword,setShowPassword]=useState(false);
const [signingIn,setSigningIn]=useState(false);
const [period,setPeriod]=useState(month);
const [analysis,setAnalysis]=useState(null);
const [analysisError,setAnalysisError]=useState('');
const [downloading,setDownloading]=useState(false);
const [qr,setQr]=useState(null);
const [qrPreview,setQrPreview]=useState('');
const [savedQr,setSavedQr]=useState('');
const [uploading,setUploading]=useState(false);
const [paymentNotice,setPaymentNotice]=useState('');
const [savingPayment,setSavingPayment]=useState(false);
const[email,setEmail]=useState(''),[password,setPassword]=useState('');const[form,setForm]=useState({title:'',body:'',category:'general',reference:'',invoice_id:'',amount:''});
async function api(path,opts={}){const res=await fetch(API+'/api'+path,{...opts,headers:{'Content-Type':'application/json',Authorization:'Bearer '+token,...opts.headers}});const json=await res.json();if(!res.ok)throw Error(typeof json.detail==='string'?json.detail:json.detail?.message||'Request failed');return json}
async function login(e){e.preventDefault();setError('');setSigningIn(true);try{const r=await fetch(API+'/api/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email,password})});const j=await r.json();if(!r.ok)throw Error(j.detail||'Login failed');if(!['owner','manager'].includes(j.user?.role))throw Error('Sign in with an owner or manager account.');
sessionStorage.setItem('pg_token',j.token);setToken(j.token);setPassword('');setShowPassword(false);
}catch(e){setError(e.message)}finally{setSigningIn(false)}}
async function refresh(){
  if(!token)return;
  try{
    const profile=await api('/me');
    if(!['owner','manager'].includes(profile.role))throw Error('Sign in with an owner or manager account.');
    setMe(profile);
    const endpoints={notices:'/notices',tickets:'/tickets',invoices:'/invoices',payments:'/payments',
      summary:'/summary',residents:'/residents',bank:'/v3/property-payment?property_id=0',policy:'/owner-features'};
    const results=await Promise.all(Object.entries(endpoints).map(async ([key,path])=>{
      try{return [key,await api(path)]}catch{return [key,null]}
    }));
    setData(Object.fromEntries(results));
  }catch(e){setError(e.message)}
}
useEffect(()=>{refresh()},[token]);
useEffect(()=>{
  if(!token||tab!=='Expense Analysis'||!period)return;
  const request=new AbortController();
  setAnalysis(null);setAnalysisError('');
  api('/expense-analysis?'+new URLSearchParams({period}),{signal:request.signal})
    .then(setAnalysis).catch(e=>{if(e.name!=='AbortError')setAnalysisError(e.message)});
  return ()=>request.abort();
},[token,tab,period]);

useEffect(()=>{
  if(!qr){setQrPreview('');return;}
  const url=URL.createObjectURL(qr);
  setQrPreview(url);
  return ()=>URL.revokeObjectURL(url);
},[qr]);

useEffect(()=>{
  setSavedQr('');
  if(!token||!data.bank?.qr_file_id||tab!=='Settings')return;
  const request=new AbortController();
  let url;
  fetch(API+'/api/v3/files/'+data.bank.qr_file_id,{
    headers:{Authorization:'Bearer '+token},signal:request.signal
  }).then(response=>{
    if(!response.ok)throw Error('Unable to load the saved QR image.');
    return response.blob();
  }).then(blob=>{
    if(!request.signal.aborted){url=URL.createObjectURL(blob);setSavedQr(url);}
  }).catch(error=>{
    if(!request.signal.aborted)setError(error.message);
  });
  return ()=>{request.abort();if(url)URL.revokeObjectURL(url);};
},[token,tab,data.bank?.qr_file_id]);

async function uploadQr(){
  if(!qr)return;
  setUploading(true);setError('');setPaymentNotice('');
  try{
    const body=new FormData();
    body.append('file',qr);
    const response=await fetch(API+'/api/v3/files/owner_qr',{method:'POST',headers:{Authorization:'Bearer '+token},body});
    const result=await response.json();
    if(!response.ok)throw Error(result.detail||'QR upload failed.');
    await api('/v3/payment-qr',{method:'PUT',body:JSON.stringify({property_id:0,file_id:result.id})});
    setQr(null);
    setData(current=>({...current,bank:{...current.bank,qr_file_id:result.id}}));
    setPaymentNotice('Payment QR saved.');
  }catch(e){setError(e.message)}finally{setUploading(false)}
}

function selectQr(event){
  const selected=event.target.files?.[0];
  event.target.value='';
  if(!selected)return;
  setError('');setPaymentNotice('');
  if(!['image/png','image/jpeg','image/webp'].includes(selected.type)||!selected.size||selected.size>5*1024*1024){
    setError('Select a PNG, JPG, or WebP image up to 5 MB.');return;
  }
  setQr(selected);
}

async function savePayment(event){
  event.preventDefault();
  if(!data.bank)return;
  setSavingPayment(true);setError('');setPaymentNotice('');
  const fields=['upi_id','bank_holder','bank_name','ifsc'];
  const payload=Object.fromEntries(fields.map(key=>[key,form[key]??data.bank[key]??'']));
  if(form.bank_account?.trim())payload.bank_account=form.bank_account.trim();
  try{
    const bank=await api('/v3/property-payment',{method:'PUT',body:JSON.stringify({property_id:0,...payload})});
    setData(current=>({...current,bank}));
    setForm(current=>{
      const next={...current};
      for(const key of [...fields,'bank_account'])delete next[key];
      return next;
    });
    setPaymentNotice('Payment instructions saved.');
  }catch(e){setError(e.message)}finally{setSavingPayment(false)}
}

async function downloadExpenses(){
  setDownloading(true);setAnalysisError('');
  try{
    const response=await fetch(API+'/api/expense-analysis/export?'+new URLSearchParams({period}),
      {headers:{Authorization:'Bearer '+token}});
    if(!response.ok){
      const body=await response.json().catch(()=>({}));
      throw Error(body.detail||'Unable to export expenses.');
    }
    const url=URL.createObjectURL(await response.blob());
    const link=document.createElement('a');
    link.href=url;link.download=`expenses-${period}.csv`;
    document.body.append(link);link.click();link.remove();
    setTimeout(()=>URL.revokeObjectURL(url),1000);
  }catch(e){setAnalysisError(e.message)}finally{setDownloading(false)}
}

async function deleteResident(resident){
  setError('');
  try{
    const path='/v3/residents/'+resident.id;
    const review=await api(path+'/deletion-review');
    if(!review.eligible)throw Error('This resident has linked records that prevent permanent deletion.');
    const email=window.prompt(`Permanently delete ${resident.name}? This cannot be undone. Type ${resident.email} to confirm.`);
    if(email===null)return;
    if(email.trim().toLowerCase()!==resident.email.toLowerCase())throw Error('Enter the exact resident email to confirm deletion.');
    await api(path,{method:'DELETE',body:JSON.stringify({confirm_email:email.trim()})});
    await refresh();
  }catch(e){setError(e.message)}
}

function logout(){
  sessionStorage.removeItem('pg_token');
  setToken('');setMe(null);setData({});setForm({title:'',body:'',category:'general'});setQr(null);setPaymentNotice('');setAnalysis(null);setAnalysisError('');setError('');setTab('Overview');
}
async function send(path,payload,method='POST'){setError('');try{await api(path,{method,body:JSON.stringify(payload)});await refresh();return true}catch(e){setError(e.message);return false}}
const input=(key,placeholder,type='text')=><input type={type} placeholder={placeholder} value={form[key]||''} onChange={e=>setForm({...form,[key]:e.target.value})}/>;
if(!token)return <div className="loginwrap"><form className="login" onSubmit={login}>
  <img className="login-logo" src="/branding/stay_sync_logo_original.png" alt="Stay Sync Manage"/>
  <h1>Owner and manager sign-in</h1>
  <label>Email<input type="email" required autoComplete="username" value={email} onChange={e=>setEmail(e.target.value)}/></label>
  <label>Password<span className="password-field"><input type={showPassword?'text':'password'} required autoComplete="current-password" value={password} onChange={e=>setPassword(e.target.value)}/><button type="button" className="password-toggle" aria-label={showPassword?'Hide password':'Show password'} onClick={()=>setShowPassword(!showPassword)}>{showPassword?<EyeOff size={18}/>:<Eye size={18}/>}</button></span></label>
  {error&&<div className="error" role="alert">{error}</div>}
  <button disabled={signingIn}>{signingIn?'Signing in…':'Sign in'}</button>
  <Attributions login/>
</form></div>;
const nav=[['Overview',LayoutDashboard],['Residents',Users],['Announcements',Megaphone],['Complaints',Wrench],['Rent & Dues',Wallet],['Expense Analysis',BarChart3],['Settings',Settings]];
const exportAllowed=data.policy?.features?.some(feature=>feature.key==='expense_csv'&&feature.allowed);
const gateway=data.policy?.features?.find(feature=>feature.key==='payment_gateway');
return <div className="layout"><aside className="owner-sidebar">
  <button className="brand" onClick={()=>setTab('Overview')} aria-label="Stay Sync Manage overview"><img src="/branding/stay_sync_manage_sidebar_purple.png" alt="Stay Sync Manage"/></button>
  <nav aria-label="Owner dashboard">{nav.map(([name,Icon])=><button className={tab===name?'active':''} aria-current={tab===name?'page':undefined} onClick={()=>setTab(name)} key={name}><Icon size={18}/>{name}</button>)}</nav>
  <div className="asideFoot"><div className="account"><span className="owner-avatar" aria-hidden="true">{(me?.name||'P')[0].toUpperCase()}</span><div><strong>{me?.name||'PG team'}</strong><small>{me?.tenant?.name}</small></div></div><button onClick={logout}><LogOut size={17}/>Sign out</button></div>
  <Attributions/>
</aside><main><header><div><small>{me?.tenant?.name||'Owner dashboard'}</small><h1>{tab}</h1></div><button className="refresh" onClick={refresh}><RefreshCw size={16}/>Refresh</button></header>
{error&&<div className="error" role="alert">{error}</div>}
{tab==='Overview'&&<><div className="stats">{[['Residents',data.summary?.residents],['Rent billed',amount(data.summary?.billed)],['Collected',amount(data.summary?.collected)],['Outstanding',amount(data.summary?.outstanding)],['Open tickets',data.summary?.open_tickets]].map(([a,b])=><div className="stat" key={a}><span>{a}</span><strong>{b??'—'}</strong></div>)}</div><section><h2>Action Center</h2><p>{data.payments?.filter(x=>x.status==='pending').length||0} payment submissions need verification. {data.tickets?.filter(x=>x.status!=='resolved').length||0} tickets are not resolved.</p><div className="actions"><button onClick={()=>setTab('Rent & Dues')}>Review payments</button><button className="secondary" onClick={()=>setTab('Complaints')}>View complaints</button></div></section></>}
{tab==='Residents'&&<section><h2>Resident Directory</h2><table><thead><tr><th>Name</th><th>Room</th><th>Email</th>{me?.role==='owner'&&<th>Action</th>}</tr></thead><tbody>{data.residents?.map(r=><tr key={r.id}><td>{r.name}</td><td>{r.room}</td><td>{r.email}</td>{me?.role==='owner'&&<td><button type="button" className="secondary resident-delete" onClick={()=>deleteResident(r)}><Trash2 size={15}/> Delete permanently</button></td>}</tr>)}</tbody></table></section>}
{tab==='Announcements'&&<div className="two"><section><h2>Publish Announcement</h2>{input('title','Announcement title')}<textarea placeholder="Notice details" value={form.body} onChange={e=>setForm({...form,body:e.target.value})}/><select value={form.category} onChange={e=>setForm({...form,category:e.target.value})}>{['general','water','electricity','wifi','maintenance','emergency'].map(c=><option key={c}>{c}</option>)}</select><button onClick={()=>send('/notices',{title:form.title,body:form.body,category:form.category})}>Publish to residents</button></section><section><h2>Published Notices</h2>{data.notices?.map(n=><article key={n.id}><b>{n.title}</b><small>{n.category} • {n.status}</small><p>{n.body}</p></article>)}</section></div>}
{tab==='Complaints'&&<section><h2>Maintenance Tickets</h2><table><thead><tr><th>Ticket</th><th>Issue</th><th>Status</th><th>Action</th></tr></thead><tbody>{data.tickets?.map(t=><tr key={t.id}><td>#{t.id}</td><td><b>{t.category}</b><br/>{t.description}</td><td>{t.status}</td><td><select value={t.status} onChange={e=>send('/tickets/'+t.id,{status:e.target.value},'PATCH')}>{['submitted','assigned','in_progress','resolved','reopened'].map(s=><option key={s}>{s}</option>)}</select></td></tr>)}</tbody></table></section>}
{tab==='Rent & Dues'&&<><div className="two"><section><h2>Create Monthly Invoice</h2><select onChange={e=>setForm({...form,resident_id:Number(e.target.value)})}><option>Select resident</option>{data.residents?.map(r=><option value={r.id} key={r.id}>{r.name} • Room {r.room}</option>)}</select><input type="month" onChange={e=>setForm({...form,period:e.target.value})}/><input type="number" placeholder="Rent amount" onChange={e=>setForm({...form,invoice_amount:e.target.value})}/><input type="date" onChange={e=>setForm({...form,due_date:e.target.value})}/><button onClick={()=>send('/invoices',{resident_id:form.resident_id,period:form.period,amount:form.invoice_amount,due_date:form.due_date})}>Create invoice</button></section><section><h2>Payment Verification</h2>{data.payments?.filter(p=>p.status==='pending').map(p=><article key={p.id}><b>₹{p.amount} • Resident #{p.resident_id}</b><small>Reference: {p.reference} • Invoice #{p.invoice_id}</small><div className="actions"><button onClick={()=>send('/payments/'+p.id+'/verify',{decision:'approved'})}>Approve after bank check</button><button className="secondary" onClick={()=>send('/payments/'+p.id+'/verify',{decision:'rejected'})}>Reject</button></div></article>)}<p className="note">Never approve based only on submitted reference or screenshot.</p></section></div><section><h2>Rent Ledger</h2><table><thead><tr><th>Invoice</th><th>Resident</th><th>Period</th><th>Billed</th><th>Paid</th><th>Outstanding</th></tr></thead><tbody>{data.invoices?.map(i=><tr key={i.id}><td>#{i.id}</td><td>#{i.resident_id}</td><td>{i.period}</td><td>₹{i.amount}</td><td>₹{i.paid}</td><td>₹{i.outstanding}</td></tr>)}</tbody></table></section></>}
{tab==='Expense Analysis'&&<section>
  <div className="section-heading"><div><h2>Monthly expenses</h2><p>Total recorded: <strong>{amount(analysis?.total)}</strong></p></div>
    <label>Month<input type="month" value={period} onChange={e=>setPeriod(e.target.value)}/></label>
  </div>
  {analysisError&&<div className="error" role="alert">{analysisError}</div>}
  {period&&!analysis&&!analysisError&&<p role="status">Loading expenses…</p>}
  {analysis?.categories.length>0&&<table><thead><tr><th>Category</th><th>Entries</th><th>Amount</th></tr></thead><tbody>{analysis.categories.map(row=><tr key={row.category}><td>{row.category}</td><td>{row.entries}</td><td>{amount(row.amount)}</td></tr>)}</tbody></table>}
  {analysis?.categories.length===0&&<p>No expenses recorded for this month.</p>}
  <div className="actions">{exportAllowed
    ?<button className="secondary" disabled={!analysis||downloading} onClick={downloadExpenses}><Download size={16}/> {downloading?'Downloading…':'Download CSV'}</button>
    :data.policy&&<small>CSV export requires an active paid subscription and administrator access.</small>}</div>
</section>}
{tab==='Settings'&&<><section className="payment-settings">
  <h2>Payment instructions</h2>
  {paymentNotice&&<p className="payment-notice" role="status">{paymentNotice}</p>}
  <div className="payment-settings-grid">
    <form className="payment-bank" onSubmit={savePayment}>
      <h3>UPI and bank details</h3>
      {Object.entries({upi_id:'UPI ID',bank_holder:'Account holder',bank_name:'Bank name',ifsc:'IFSC'}).map(([key,label])=>
        <label key={key}>{label}<input value={form[key]??data.bank?.[key]??''} onChange={e=>setForm({...form,[key]:e.target.value})}/></label>)}
      <label>Bank account number<input inputMode="numeric" autoComplete="off" value={form.bank_account??''}
        placeholder={data.bank?.bank_account_masked||'Enter new account number'}
        onChange={e=>setForm({...form,bank_account:e.target.value})}/></label>
      <small>Leave the account number blank to keep the saved number.</small>
      <button disabled={!data.bank||savingPayment||uploading}>{savingPayment?'Saving…':'Save payment instructions'}</button>
    </form>
    <div className="payment-qr">
      <h3>Rent payment QR</h3>
      <div className="qr-preview">
        {qrPreview||savedQr?<img src={qrPreview||savedQr} alt={qr?'Selected payment QR preview':'Saved payment QR'}/>:<><Upload size={25}/><span>No QR image uploaded</span></>}
      </div>
      <label htmlFor="payment-qr-file">Choose QR image</label>
      <input id="payment-qr-file" type="file" accept="image/png,image/jpeg,image/webp" onChange={selectQr} disabled={uploading}/>
      <small>{qr?qr.name:'PNG, JPG or WebP · up to 5 MB'}</small>
      <div className="actions">
        <button type="button" disabled={!qr||uploading||savingPayment} onClick={uploadQr}><Upload size={16}/>{uploading?'Uploading…':'Upload QR image'}</button>
        {qr&&<button className="secondary" type="button" disabled={uploading} onClick={()=>setQr(null)}>Cancel</button>}
      </div>
    </div>
  </div>
</section>
{gateway&&<section><h2>Payment gateway</h2><p>{!gateway.available?'Online payment processing is unavailable. Manual payment verification is available in Rent & Dues.':gateway.allowed?'Included in your subscription.':'Available with an eligible paid subscription.'}</p></section>}
</>}
</main></div>}
createRoot(document.getElementById('root')).render(<App/>);
