import React,{useEffect,useState} from 'react';
import './subscription-payments.css';

/** Mount only within the EXISTING authenticated platform-admin view. */
export default function SubscriptionPayments({apiBase='http://127.0.0.1:8000',token}){
  const [settings,setSettings]=useState(null);
  const [beds,setBeds]=useState('0');
  const [residents,setResidents]=useState('0');
  const [beneficiary,setBeneficiary]=useState('');
  const [upi,setUpi]=useState('');
  const [qr,setQr]=useState(null);
  const [invoices,setInvoices]=useState([]);
  const [payments,setPayments]=useState([]);
  const [error,setError]=useState('');
  const [notice,setNotice]=useState('');
  const [busy,setBusy]=useState(false);
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
      setBeds(s.pricing?.bed_rate||'0');setResidents(s.pricing?.resident_rate||'0');
    }catch(e){setError(e.message)}
  }
  useEffect(()=>{if(token)refresh()},[token,apiBase]);
  async function act(fn){setBusy(true);setError('');setNotice('');try{const result=await fn();setNotice(result?.activation?.status==='pending'?'Payment approved, but activation is pending. Use Retry activation after resolving the error.':'Saved successfully');await refresh()}catch(e){setError(e.message)}finally{setBusy(false)}}
  const currency=v=>'₹'+(Number(v||0)/100).toLocaleString('en-IN',{minimumFractionDigits:2,maximumFractionDigits:2});
  return <section className="ss-subscription-admin">
    <header className="ss-head"><div><h2>Owner subscription payments (new manual QR billing)</h2><p>Admin-set bed and billable-resident rates; separate from existing legacy invoice ledger. Verified payments activate paid access automatically; failed activations remain pending for reconciliation.</p></div><button onClick={refresh} disabled={busy}>Refresh</button></header>
    {error&&<p className="ss-alert" role="alert">{error}</p>}{notice&&<p className="ss-notice" role="status">{notice}</p>}
    <div className="ss-grid">
      <form className="ss-panel" onSubmit={e=>{e.preventDefault();act(()=>request('/admin/pricing',{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify({bed_rate:beds,resident_rate:residents})}))}}>
        <h3>Pricing rules</h3><p>Monthly charge = beds × rate + active residents × rate. Existing invoices retain their original amounts.</p>
        <label>Rate per bed (₹)<input required type="number" step="0.01" min="0" value={beds} onChange={e=>setBeds(e.target.value)}/></label>
        <label>Rate per active resident (₹)<input required type="number" step="0.01" min="0" value={residents} onChange={e=>setResidents(e.target.value)}/></label>
        <button disabled={busy}>Save pricing</button>
      </form>
      <form className="ss-panel" onSubmit={e=>{e.preventDefault();if(!qr){setError('Choose a QR image');return}act(()=>{const data=new FormData();data.append('qr',qr);data.append('beneficiary',beneficiary);data.append('upi_id',upi);return request('/admin/qr',{method:'POST',body:data})})}}>
        <h3>Official payment QR</h3><p>Only the platform administrator can upload or replace the UPI QR.</p>
        <label>Beneficiary name<input required maxLength={120} value={beneficiary} onChange={e=>setBeneficiary(e.target.value)}/></label>
        <label>UPI ID<input required maxLength={120} value={upi} onChange={e=>setUpi(e.target.value)}/></label>
        <label>PNG / JPEG (up to 2 MB)<input type="file" accept="image/png,image/jpeg" onChange={e=>setQr(e.target.files?.[0]||null)}/></label>
        <p>QR: {settings?.qr?(settings.qr.enabled?'Enabled':'Disabled'):'Not uploaded'}</p>
        <button disabled={busy}>Upload payment QR</button>
        {settings?.qr&&<button className="ss-alt" type="button" disabled={busy} onClick={()=>act(()=>request('/admin/qr/status',{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify({enabled:!settings.qr.enabled})}))}>{settings.qr.enabled?'Disable QR':'Enable QR'}</button>}
      </form>
    </div>
    <div className="ss-panel"><h3>Owner invoices</h3><div className="ss-scroll"><table><thead><tr><th>Owner</th><th>Period</th><th>Beds</th><th>Residents</th><th>Amount</th><th>Status</th></tr></thead><tbody>{invoices.map(i=><tr key={i.id}><td>{i.owner_id}</td><td>{i.period}</td><td>{i.beds}</td><td>{i.residents}</td><td>{currency(i.amount_cents)}</td><td>{i.status}</td></tr>)}</tbody></table></div>{!invoices.length&&<p>No invoices issued yet.</p>}</div>
    <div className="ss-panel"><h3>Payment verification queue</h3><p>Check the actual bank/UPI receipt before approving. A screenshot is not proof of settlement.</p><div className="ss-scroll"><table><thead><tr><th>Owner</th><th>UTR</th><th>Submitted</th><th>Proof</th><th>Status</th><th>Actions</th></tr></thead><tbody>{payments.map(p=><tr key={p.id}><td>{p.owner_id}</td><td>{p.utr}</td><td>{p.submitted_at?.slice(0,10)}</td><td><button className="ss-alt" type="button" onClick={async()=>{try{const r=await fetch(root+'/admin/payments/'+p.id+'/proof',{headers:auth()});if(!r.ok)throw new Error('Cannot load proof');const blob=await r.blob();const url=URL.createObjectURL(blob);window.open(url,'_blank','noopener');setTimeout(()=>URL.revokeObjectURL(url),60000)}catch(e){setError(e.message)}}}>View proof</button></td><td>{p.status}{p.status==='approved'?' / '+p.activation_status:''}</td><td>{p.status==='approved'&&p.activation_status!=='activated'&&<button type="button" disabled={busy} onClick={()=>act(()=>request('/admin/payments/'+p.id+'/reconcile',{method:'POST'}))}>Retry activation</button>}{p.status==='pending'&&<div className="ss-actions"><button type="button" disabled={busy} onClick={()=>{const remarks=window.prompt('Verified receipt reference / remarks','')??null;if(remarks!==null&&window.confirm('I independently verified this exact bank/UPI credit in the beneficiary account. Activate the subscription?'))act(()=>request('/admin/payments/'+p.id+'/review',{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify({approve:true,bank_verified:true,remarks})}))}}>Approve</button><button className="ss-alt" type="button" disabled={busy} onClick={()=>{const remarks=window.prompt('Reason for rejection','')??null;if(remarks!==null)act(()=>request('/admin/payments/'+p.id+'/review',{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify({approve:false,remarks})}))}}>Reject</button></div>}</td></tr>)}</tbody></table></div>{!payments.length&&<p>No payment submissions yet.</p>}</div>
  </section>
}
