import React,{useEffect,useState} from 'react';
import './subscription-payments.css';
import toast from 'react-hot-toast';

/** Mount only within the EXISTING authenticated platform-admin view. */
export default function SubscriptionPayments({apiBase='http://127.0.0.1:8000',token,refreshKey=0}){
  const [settings,setSettings]=useState(null);
  const [beneficiary,setBeneficiary]=useState('');
  const [upi,setUpi]=useState('');
  const [qr,setQr]=useState(null);
  const [invoices,setInvoices]=useState([]);
  const [payments,setPayments]=useState([]);
  const [error,setError]=useState('');
  const [notice,setNotice]=useState('');
  const [busy,setBusy]=useState(false);
  const [savedQrImage,setSavedQrImage]=useState('');
  const root=apiBase.replace(/\/$/,'')+'/api/owner-subscriptions';
  const auth=()=>({'Authorization':`Bearer ${token}`});
  async function request(path,opts={}){
    const res=await fetch(root+path,{...opts,headers:{...auth(),...(opts.headers||{})}});
    if(!res.ok){let detail;try{detail=await res.json()}catch{}throw new Error(detail?.detail||`Request failed (${res.status})`)}
    return res.json();
  }
  async function refresh(){
    setError('');
    try{
      const [s,i,p]=await Promise.all([request('/admin/settings'),request('/admin/invoices'),request('/admin/payments')]);
      setSettings(s);setInvoices(i);setPayments(p);
    }catch(e){setError(e.message);toast.error(e.message)}
  }
  useEffect(()=>{if(token)refresh()},[token,apiBase,refreshKey]);
  useEffect(()=>{
    if(settings?.qr){setBeneficiary(settings.qr.beneficiary||'');setUpi(settings.qr.upi_id||'')}
  },[settings?.qr?.updated_at]);
  useEffect(()=>{
    if(!token || !settings?.qr?.enabled){setSavedQrImage('');return}
    let disposed=false, url='';
    fetch(root+'/payment-qr',{headers:auth()}).then(r=>{if(!r.ok)throw Error('QR preview unavailable');return r.blob()}).then(blob=>{
      if(disposed)return;
      url=URL.createObjectURL(blob);setSavedQrImage(url);
    }).catch(()=>{if(!disposed)setSavedQrImage('')});
    return ()=>{disposed=true;if(url)URL.revokeObjectURL(url)};
  },[root,token,settings?.qr?.updated_at,settings?.qr?.enabled]);
  async function act(fn){setBusy(true);setError('');setNotice('');try{const result=await fn();const msg=result?.activation?.status==='pending'?'Payment approved. Activation pending; use Retry activation after resolving the error.':'Saved successfully';setNotice(msg);toast.success(msg);await refresh()}catch(e){setError(e.message);toast.error(e.message)}finally{setBusy(false)}}
  const currency=v=>'₹'+(Number(v||0)/100).toLocaleString('en-IN',{minimumFractionDigits:2,maximumFractionDigits:2});
  const pendingPayments=payments.filter(p=>p.status==='pending');
  const reviewedPayments=payments.filter(p=>p.status!=='pending');
  return <section className="ss-subscription-admin">
    <header className="ss-head"><div><h2>Owner subscription payments</h2><p>1. Publish platform payment details. 2. Review owner proof and bank credit. 3. Approve or reject. 4. Check activation status.</p></div></header>
    
    <div className="ss-grid">
      <div className="ss-panel ss-single-plan" aria-label="Single Stay Sync Manage subscription plan">
        <p className="ss-plan-eyebrow">ONE SIMPLE PLAN</p>
        <h3>Stay Sync Manage</h3>
        <p className="ss-plan-price">₹39 <span>/ billable resident or owner / month + GST</span></p>
        <p>Monthly subscription = (active billable residents + distinct active owner accounts) × ₹39, plus 18% GST. Beds are never charged.</p>
        <p>Example: 10 residents + 1 owner = <strong>₹429 subtotal + ₹77.22 GST = ₹506.22</strong>.</p>
        <p className="ss-plan-note">The single price applies to new invoices. Previously issued invoices retain their original amounts.</p>
      </div>
      <form className="ss-panel" onSubmit={e=>{e.preventDefault();if(!qr){toast.error('Choose a QR image');return}act(()=>{const data=new FormData();data.append('qr',qr);data.append('beneficiary',beneficiary);data.append('upi_id',upi);return request('/admin/qr',{method:'POST',body:data})})}}>
        <h3>Where owners send payments</h3><p>Only platform administrators can upload or replace the official UPI payment QR. Verify the beneficiary and UPI ID before publishing.</p>
        <label>Beneficiary name<input required maxLength={120} value={beneficiary} onChange={e=>setBeneficiary(e.target.value)}/></label>
        <label>UPI ID<input required maxLength={120} value={upi} onChange={e=>setUpi(e.target.value)}/></label>
        <label>PNG / JPEG (up to 2 MB)<input type="file" accept="image/png,image/jpeg" onChange={e=>setQr(e.target.files?.[0]||null)}/></label>
        <p className="ss-qr-status">{settings?.qr ? 'Saved platform QR — available across administrator sessions' : 'No platform QR saved yet. Upload once to publish it.'}</p>
        {savedQrImage&&<img src={savedQrImage} alt="Currently saved platform UPI QR code" className="ss-qr-preview"/>}
        {settings?.qr&&<p className="hint">Beneficiary: {settings.qr.beneficiary} · UPI: {settings.qr.upi_id}</p>}
        <button disabled={busy||!qr}>{busy?'Saving…':settings?.qr?'Replace saved QR':'Upload and save QR'}</button>
        {settings?.qr&&<button className="ss-alt" type="button" disabled={busy} onClick={()=>act(()=>request('/admin/qr/status',{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify({enabled:!settings.qr.enabled})}))}>{settings.qr.enabled?'Disable QR':'Enable QR'}</button>}
      </form>
    </div>
    <div className="ss-panel"><h3>Owner invoices</h3><p>Invoices issued by the owner-subscription payment system. Resident and owner counts determine new invoice totals; historical invoices remain unchanged.</p><div className="ss-scroll"><table><thead><tr><th>Owner ID</th><th>Billing month</th><th>Beds (capacity)</th><th>Residents</th><th>Owners</th><th>Subtotal</th><th>GST</th><th>Invoice amount</th><th>Payment status</th></tr></thead><tbody>{invoices.map(i=><tr key={i.id}><td>{i.owner_id}</td><td>{i.period}</td><td>{i.beds}</td><td>{i.residents}</td><td>{i.owners||0}</td><td>{currency(i.subtotal_cents||i.amount_cents)}</td><td>{currency(i.gst_cents||0)}</td><td>{currency(i.amount_cents)}</td><td>{i.status}</td></tr>)}</tbody></table></div>{!invoices.length&&<p>No invoices issued yet.</p>}</div>
    <div className="ss-panel"><h3>Payments waiting for review ({pendingPayments.length})</h3><p>Confirm receipt in the company bank/UPI account before approving an owner payment. A screenshot alone is not proof that money arrived.</p><div className="ss-scroll"><table><thead><tr><th>Owner</th><th>UTR</th><th>Submitted</th><th>Proof</th><th>Status</th><th>Actions</th></tr></thead><tbody>{pendingPayments.map(p=><tr key={p.id}><td>{p.owner_id}</td><td>{p.utr}</td><td>{p.submitted_at?.slice(0,10)}</td><td><button className="ss-alt" type="button" onClick={async()=>{try{const r=await fetch(root+'/admin/payments/'+p.id+'/proof',{headers:auth()});if(!r.ok)throw new Error('Cannot load proof');const blob=await r.blob();const url=URL.createObjectURL(blob);window.open(url,'_blank','noopener');setTimeout(()=>URL.revokeObjectURL(url),60000)}catch(e){toast.error(e.message)}}}>View proof</button></td><td>{p.status}{p.status==='approved'?' / '+p.activation_status:''}</td><td>{p.status==='approved'&&p.activation_status!=='activated'&&<button type="button" disabled={busy} onClick={()=>act(()=>request('/admin/payments/'+p.id+'/reconcile',{method:'POST'}))}>Retry activation</button>}{p.status==='pending'&&<div className="ss-actions"><button type="button" disabled={busy} onClick={()=>{const remarks=window.prompt('Verified receipt reference / remarks','')??null;if(remarks!==null&&window.confirm('I independently verified this exact bank/UPI credit in the beneficiary account. Activate the subscription?'))act(()=>request('/admin/payments/'+p.id+'/review',{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify({approve:true,bank_verified:true,remarks})}))}}>Approve</button><button className="ss-alt" type="button" disabled={busy} onClick={()=>{const remarks=window.prompt('Reason for rejection','')??null;if(remarks!==null)act(()=>request('/admin/payments/'+p.id+'/review',{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify({approve:false,remarks})}))}}>Reject</button></div>}</td></tr>)}</tbody></table></div>{!pendingPayments.length&&<p>No payments are awaiting review.</p>}</div>
    <div className="ss-panel"><h3>Reviewed payments ({reviewedPayments.length})</h3>
      <p>These payments were already processed. A reviewed transaction should not be approved again.</p>
      <div className="ss-scroll"><table><thead><tr><th>Owner</th><th>UTR</th><th>Status</th><th>Activation</th></tr></thead>
      <tbody>{reviewedPayments.map(p=><tr key={p.id}><td>{p.owner_id}</td><td>{p.utr}</td><td>{p.status}</td><td>{p.activation_status||'—'}{p.status==='approved'&&p.activation_status!=='activated'&&<button type="button" disabled={busy} onClick={()=>act(()=>request('/admin/payments/'+p.id+'/reconcile',{method:'POST'}))}>Retry activation</button>}</td></tr>)}</tbody></table></div>
      {!reviewedPayments.length&&<p>No payments reviewed yet.</p>}
    </div>
  </section>
}
