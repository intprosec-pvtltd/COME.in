import React,{useEffect,useMemo,useState} from 'react';
import{createRoot}from'react-dom/client';
import{LayoutDashboard,Building2,UsersRound,BedDouble,WalletCards,ReceiptText,ShieldCheck,LogOut,RefreshCw,Plus,CheckCircle2,AlertCircle,Search,ArrowUpRight,ChartNoAxesCombined,House,Layers,IndianRupee,Settings2,ClipboardList,Menu,X,LockKeyhole}from'lucide-react';
import './style.css';

const DEFAULT_API='http://127.0.0.1:8000';
const API=(import.meta.env.VITE_API_URL||DEFAULT_API).replace(/\/$/,'');
const fmt=new Intl.NumberFormat('en-IN',{style:'currency',currency:'INR',minimumFractionDigits:2});
const money=v=>fmt.format(Number(v||0));
const plural=(n,s)=>`${n} ${s}${n===1?'':'s'}`;
const nav=[['Overview',LayoutDashboard],['PG Owners',Building2],['Properties & Beds',BedDouble],['Subscriptions',WalletCards],['Invoices',ReceiptText],['Activity',ClipboardList]];
const currentPeriod=()=>{const d=new Date();return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}`};
const inputDate=/^\d{4}-(0[1-9]|1[0-2])$/;

function Logo({size='normal'}){return <img alt="COME.in — Spaces People Belong" className={`logo logo-${size}`} src="/comein-logo.png"/>}
function Attribution(){return <div className="attribution"><span>by</span><img src="/intprosec.webp" alt="IntProSec — Intelligence Protection Security"/></div>}
function Banner({children,tone='info',close}){return <div className={`banner ${tone}`}>{tone==='error'?<AlertCircle size={18}/>:<ShieldCheck size={18}/>}<span>{children}</span>{close&&<button className="bare" onClick={close}>Dismiss</button>}</div>}
function Stat({label,value,note,icon:Icon}){return <div className="stat"><div className="stat-top"><span>{label}</span><div className="iconwell">{Icon&&<Icon size={19}/>}</div></div><strong>{value}</strong>{note&&<small>{note}</small>}</div>}
function Tag({value}){return <span className={`tag ${value==='active'||value==='paid'?'good':value==='trial'||value==='draft'?'soft':value==='past_due'||value==='issued'?'warn':'neutral'}`}>{String(value).replaceAll('_',' ')}</span>}
function Empty({text}){return <div className="empty"><Layers size={23}/><p>{text}</p></div>}

function App(){
  const [token,setToken]=useState(()=>sessionStorage.getItem('comein_platform_admin_token')||'');
  const [admin,setAdmin]=useState(null);
  const [tab,setTab]=useState('Overview');
  const [overview,setOverview]=useState(null);
  const [owners,setOwners]=useState([]);
  const [invoices,setInvoices]=useState([]);
  const [audit,setAudit]=useState([]);
  const [ownerId,setOwnerId]=useState(null);
  const [detail,setDetail]=useState(null);
  const [error,setError]=useState('');
  const [success,setSuccess]=useState('');
  const [loading,setLoading]=useState(false);
  const [mobileNav,setMobileNav]=useState(false);
  const [search,setSearch]=useState('');
  const [credentials,setCredentials]=useState({email:'',password:''});
  const [create,setCreate]=useState({business_name:'',owner_name:'',owner_email:'',temporary_password:''});
  const [newPG,setNewPG]=useState({name:'',address:''});
  const [subDraft,setSubDraft]=useState(null);
  const [period,setPeriod]=useState(currentPeriod());
  const [paymentRefs,setPaymentRefs]=useState({});
  const [showCreate,setShowCreate]=useState(false);

  async function request(path,{method='GET',body,authToken=token}={}){
    const response=await fetch(`${API}/api/platform${path}`,{
      method,headers:{...(body!==undefined?{'Content-Type':'application/json'}:{}),...(authToken?{Authorization:`Bearer ${authToken}`}:{})},
      body:body===undefined?undefined:JSON.stringify(body)
    });
    const payload=await response.json().catch(()=>({}));
    if(!response.ok)throw new Error(typeof payload.detail==='string'?payload.detail:`Request failed (${response.status})`);
    return payload;
  }
  const fail=e=>{setError(e.message||'Unable to complete request');setSuccess('')};
  const notify=s=>{setSuccess(s);setError('')};
  function logout(){sessionStorage.removeItem('comein_platform_admin_token');setToken('');setAdmin(null);setOverview(null);setOwners([]);setDetail(null)}

  async function refresh(authToken=token){
    if(!authToken)return;
    setLoading(true);setError('');
    try{
      const [me,o,list,inv]=await Promise.all([
        request('/auth/me',{authToken}),request('/overview',{authToken}),request('/owners',{authToken}),request('/invoices',{authToken})
      ]);
      setAdmin(me);setOverview(o);setOwners(list);setInvoices(inv);
      if(tab==='Activity')setAudit(await request('/audit',{authToken}));
      if(ownerId)setDetail(await request(`/owners/${ownerId}`,{authToken}));
    }catch(e){if(/401|expired|administrator sign-in/i.test(e.message))logout();fail(e)}finally{setLoading(false)}
  }
  useEffect(()=>{if(token)refresh(token)},[token]);
  async function signIn(e){e.preventDefault();setLoading(true);setError('');try{
    const result=await request('/auth/login',{method:'POST',body:credentials,authToken:''});
    sessionStorage.setItem('comein_platform_admin_token',result.access_token);
    setToken(result.access_token);setCredentials({email:'',password:''});
  }catch(e){fail(e)}finally{setLoading(false)}}
  async function chooseOwner(id){setOwnerId(id);setSubDraft(null);setError('');try{
    const x=await request(`/owners/${id}`);setDetail(x);setSubDraft({...x.subscription});
  }catch(e){fail(e)}}
  async function mutate(path,method,body,message,{reloadDetail=true}={}){
    setLoading(true);try{await request(path,{method,body});notify(message);await refresh();if(reloadDetail&&ownerId){const d=await request(`/owners/${ownerId}`);setDetail(d);setSubDraft({...d.subscription})}return true}catch(e){fail(e);return false}finally{setLoading(false)}
  }
  async function addOwner(e){e.preventDefault();const result=await mutate('/owners','POST',create,'PG owner registered. Share the temporary password securely.');if(result){setCreate({business_name:'',owner_name:'',owner_email:'',temporary_password:''});setShowCreate(false)}}
  async function addPG(e){e.preventDefault();if(!ownerId)return;const ok=await mutate(`/owners/${ownerId}/properties`,'POST',newPG,'PG property created');if(ok)setNewPG({name:'',address:''})}
  const matchingOwners=useMemo(()=>owners.filter(o=>`${o.business_name} ${o.owners.map(x=>`${x.name} ${x.email}`).join(' ')}`.toLowerCase().includes(search.toLowerCase())),[owners,search]);
  async function setNav(value){setTab(value);setMobileNav(false);if(value==='Activity'&&token){try{setAudit(await request('/audit'))}catch(e){fail(e)}}}

  if(!token)return <div className="login-scene"><div className="login-frame"><div className="login-top"><Logo/><div className="login-emblem"><LockKeyhole size={20}/></div></div><div className="login-copy"><span className="eyebrow">INTPROSEC INTERNAL WORKSPACE</span><h1>COME.in Platform Control</h1><p>Manage PG owners, properties, bed capacity and subscriptions from one secure workspace.</p></div><form onSubmit={signIn} className="login-fields"><label>Administrator email<input type="email" required autoComplete="username" value={credentials.email} onChange={e=>setCredentials({...credentials,email:e.target.value})} placeholder="admin@yourcompany.com"/></label><label>Password<input type="password" required autoComplete="current-password" value={credentials.password} onChange={e=>setCredentials({...credentials,password:e.target.value})} placeholder="Administrator password"/></label>{error&&<Banner tone="error">{error}</Banner>}<button className="primary full" disabled={loading} type="submit">{loading?'Signing in…':'Sign in to platform'} <ArrowUpRight size={17}/></button></form><p className="login-security"><ShieldCheck size={15}/> Separate privileged sign-in. No demo admin credentials are provided.</p><Attribution/></div></div>;

  return <div className="app-shell">
    <aside className={`sidebar ${mobileNav?'show':''}`}><div className="sidebar-head"><div className="sidebar-brand"><img className="sidebar-app-icon" src="/comein-app-icon.png" alt="COME.in app icon"/><div className="sidebar-brand-copy"><strong>COME.in</strong><small>Platform Control</small></div></div><button className="mobile-close bare" onClick={()=>setMobileNav(false)}><X/></button><div className="side-caption"><span className="dot"/>PLATFORM ADMINISTRATION</div></div>
      <nav>{nav.map(([name,Icon])=><button key={name} className={`nav-item ${tab===name?'active':''}`} onClick={()=>setNav(name)}><Icon size={19}/><span>{name}</span></button>)}</nav>
      <div className="side-bottom"><div className="sidebar-account-row"><div className="admin-chip" title={admin?.email||'IntProSec administrator'}><div className="avatar">{(admin?.name||'A')[0].toUpperCase()}</div><div className="admin-meta"><strong>{admin?.name||'Administrator'}</strong><small>{admin?.email||'Privileged access'}</small></div></div><button type="button" className="sidebar-signout" onClick={logout} title="Sign out of platform administrator account" aria-label="Sign out"><LogOut size={16}/><span>Sign out</span></button></div><Attribution/></div>
    </aside>
    {mobileNav&&<div className="scrim" onClick={()=>setMobileNav(false)}/>}
    <main className="content"><header className="page-header"><div className="header-left"><button className="mobile-menu bare" onClick={()=>setMobileNav(true)}><Menu/></button><div><span className="eyebrow">COME.in / INTPROSEC OPERATIONS</span><h1>{tab}</h1></div></div><div className="header-actions"><span className="live-indicator"><span/> Connected to API</span><button className="outline" onClick={()=>refresh()} disabled={loading}><RefreshCw size={16} className={loading?'spin':''}/> Refresh</button></div></header>
    {error&&<Banner tone="error" close={()=>setError('')}>{error}</Banner>}
    {success&&<Banner tone="info" close={()=>setSuccess('')}>{success}</Banner>}
    {tab==='Overview'&&<>
      <div className="intro"><div><span className="eyebrow">PLATFORM HEALTH AT A GLANCE</span><h2>Your PG network, clearly managed.</h2><p>Real registered residents, allocated properties and monthly subscription estimates—not placeholder client data.</p></div><div className="intro-icon"><ChartNoAxesCombined size={35}/></div></div>
      <div className="stats"><Stat label="PG owners" value={overview?.owners??'—'} icon={UsersRound} note="Registered tenant organizations"/><Stat label="Properties" value={overview?.pgs??'—'} icon={Building2} note="Registered PG locations"/><Stat label="Beds" value={overview?.beds??'—'} icon={BedDouble} note="Capacity across recorded rooms"/><Stat label="Billable residents" value={overview?.billable_residents??'—'} icon={UsersRound} note="Registered minus excluded"/><Stat label="Monthly estimate" value={overview?money(overview.estimated_monthly_revenue):'—'} icon={IndianRupee} note="Before GST and fees"/></div>
      <div className="two-col"><section className="panel"><div className="panel-title"><h3>Owner portfolio</h3><button className="text-action" onClick={()=>setNav('PG Owners')}>View all <ArrowUpRight size={16}/></button></div><div className="table-scroll"><table><thead><tr><th>PG owner</th><th>Properties</th><th>Beds</th><th>Residents</th><th>Monthly</th></tr></thead><tbody>{(overview?.owner_rows||[]).slice(0,8).map(o=><tr key={o.id}><td><strong>{o.business_name}</strong><small>{o.owners[0]?.name||'No owner assigned'}</small></td><td>{o.pg_count}</td><td>{o.total_beds}</td><td>{o.total_residents}</td><td>{money(o.subscription.estimated_monthly)}</td></tr>)}</tbody></table>{!overview?.owner_rows?.length&&<Empty text="No PG owners yet. Add one in PG Owners."/>}</div></section>
      <section className="panel highlights"><h3>Subscription collection</h3><div className="figure"><small>Confirmed manually received</small><strong>{overview?money(overview.confirmed_collected):'—'}</strong></div><div className="detail-row"><span>Issued, awaiting payment</span><b>{overview?money(overview.outstanding):'—'}</b></div><div className="detail-row"><span>Total invoices (excl. void)</span><b>{overview?money(overview.invoiced_total):'—'}</b></div><p className="hint">Invoices are internal ledger records. No live payment gateway is enabled in this package.</p><button className="primary" onClick={()=>setNav('Invoices')}>Open billing ledger <ArrowUpRight size={16}/></button></section></div>
    </>}
    {tab==='PG Owners'&&<><div className="toolbar"><div><h2>PG owners & operators</h2><p>Each owner can manage multiple properties under their organization.</p></div><button className="primary" onClick={()=>setShowCreate(v=>!v)}><Plus size={17}/> Add PG owner</button></div>
      {showCreate&&<section className="panel"><h3>Register a PG owner</h3><p className="hint">Create a dedicated owner account and tenant organization. Share the temporary password privately; require password rotation before production use.</p><form className="form-grid" onSubmit={addOwner}><label>Business / PG brand<input required value={create.business_name} maxLength={120} onChange={e=>setCreate({...create,business_name:e.target.value})}/></label><label>Owner full name<input required value={create.owner_name} maxLength={120} onChange={e=>setCreate({...create,owner_name:e.target.value})}/></label><label>Owner email<input type="email" required value={create.owner_email} onChange={e=>setCreate({...create,owner_email:e.target.value})}/></label><label>Temporary password (12+)<input type="password" required minLength={12} autoComplete="new-password" value={create.temporary_password} onChange={e=>setCreate({...create,temporary_password:e.target.value})}/></label><div className="form-actions"><button className="primary" disabled={loading}>Create owner</button><button type="button" className="outline" onClick={()=>setShowCreate(false)}>Cancel</button></div></form></section>}
      <section className="panel"><div className="searchbar"><Search size={18}/><input placeholder="Search owner, PG, or email" value={search} onChange={e=>setSearch(e.target.value)}/></div><div className="table-scroll"><table><thead><tr><th>Organization</th><th>PGs</th><th>Beds</th><th>Residents</th><th>Billable</th><th>Subscription</th><th>Projected charge</th><th></th></tr></thead><tbody>{matchingOwners.map(o=><tr key={o.id}><td><strong>{o.business_name}</strong><small>{o.owners[0]?.name} · {o.owners[0]?.email}</small></td><td>{o.pg_count}</td><td>{o.total_beds}</td><td>{o.total_residents}</td><td>{o.billable_residents}</td><td><Tag value={o.subscription.status}/></td><td>{money(o.subscription.estimated_monthly)}</td><td><button className="outline small" onClick={()=>{chooseOwner(o.id);setTab('Properties & Beds')}}>Manage</button></td></tr>)}</tbody></table>{!matchingOwners.length&&<Empty text="No PG owners match your search."/>}</div></section></>}
    {(tab==='Properties & Beds'||tab==='Subscriptions')&&<><div className="toolbar"><div><h2>{tab==='Properties & Beds'?'Properties, capacity & residents':'Owner subscription settings'}</h2><p>Review property capacity, occupancy and billable residents across each owner’s portfolio.</p></div><label className="owner-picker">PG organization<select value={ownerId??''} onChange={e=>chooseOwner(Number(e.target.value))}><option value="" disabled>Select an owner</option>{owners.map(o=><option key={o.id} value={o.id}>{o.business_name}</option>)}</select></label></div>
    {!detail||!ownerId?<Empty text="Select a PG owner to view their properties and subscription."/>:<>
      <div className="stats"><Stat label="Properties" value={detail.pg_count} icon={Building2}/><Stat label="Beds" value={detail.total_beds} icon={BedDouble}/><Stat label="Registered residents" value={detail.total_residents} icon={UsersRound}/><Stat label="Billable" value={detail.billable_residents} icon={WalletCards}/><Stat label="Monthly subtotal" value={money(detail.subscription.estimated_monthly)} icon={IndianRupee}/></div>
      {tab==='Properties & Beds'?<>
      {(detail.unassigned_rooms>0||detail.unassigned_residents>0)&&<Banner tone="info">{detail.unassigned_rooms} rooms and {detail.unassigned_residents} residents are not assigned to a PG. Assign them below to obtain correct per-PG counts.</Banner>}
      <div className="two-col"><section className="panel"><h3>Registered PG properties</h3>{detail.properties.length?detail.properties.map(p=><div className="property" key={p.id}><div className="property-name"><House size={19}/><div><strong>{p.name}</strong><small>{p.address||'No address provided'}</small></div></div><div className="property-stats"><span>{plural(p.rooms,'room')}</span><span>{plural(p.beds,'bed')}</span><span>{plural(p.residents,'resident')}</span></div></div>):<Empty text="No PG properties registered yet."/>}</section><section className="panel"><h3>Add PG location</h3><p className="hint">A PG organization can have multiple locations. Capacity comes from existing room records; adding a property does not invent beds.</p><form className="stack" onSubmit={addPG}><label>Property name<input required value={newPG.name} onChange={e=>setNewPG({...newPG,name:e.target.value})} placeholder="e.g. Sunrise PG — North Wing"/></label><label>Address<input value={newPG.address} onChange={e=>setNewPG({...newPG,address:e.target.value})} placeholder="PG location"/></label><button className="primary" disabled={loading}>Add property</button></form></section></div>
      <div className="two-col"><section className="panel"><h3>Assign existing rooms to PGs</h3>{detail.rooms.length?detail.rooms.map(r=><div className="assign-row" key={r.id}><div><b>{r.name}</b><small>{r.beds} beds</small></div><select aria-label={`Property assignment for room ${r.name}`} value={r.property_id??''} onChange={e=>mutate(`/owners/${ownerId}/properties/${e.target.value}/rooms/${r.id}`,'PUT',undefined,'Room assigned')}><option value="">Unassigned</option>{detail.properties.map(p=><option key={p.id} value={p.id}>{p.name}</option>)}</select></div>):<Empty text="No rooms are recorded in this owner's existing backend."/>}</section><section className="panel"><h3>Assign residents and billing status</h3><p className="hint">In the uploaded backend, a registered resident has no separate active/inactive field. All registered residents are billable by default; exclusions need a reason.</p>{detail.residents.length?detail.residents.map(r=><div className="resident-row" key={r.id}><div><b>{r.name}</b><small>{r.room||'Room not set'} · {r.email}</small></div><div className="resident-controls"><select aria-label={`Property for ${r.name}`} value={r.property_id??''} onChange={e=>mutate(`/owners/${ownerId}/properties/${e.target.value}/residents/${r.id}`,'PUT',undefined,'Resident assigned')}><option value="">Unassigned</option>{detail.properties.map(p=><option key={p.id} value={p.id}>{p.name}</option>)}</select><label className="checkbox"><input type="checkbox" checked={r.billable} onChange={e=>{const billable=e.target.checked;const reason=billable?'':window.prompt('Reason for excluding this resident from billing:');if(!billable&&!reason)return;mutate(`/owners/${ownerId}/residents/${r.id}/billing`,'PUT',{excluded:!billable,reason:reason||''},'Billing eligibility updated')}}/> Billable</label></div></div>):<Empty text="No registered residents yet."/>}</section></div>
      </>:<div className="two-col"><section className="panel"><div className="panel-title"><h3>Plan configuration</h3><Tag value={detail.subscription.status}/></div><p className="hint">Billing is based on registered residents minus documented exclusions, not bed capacity.</p><form className="stack" onSubmit={e=>{e.preventDefault();mutate(`/owners/${ownerId}/subscription`,'PUT',{price_per_resident:subDraft.price_per_resident,status:subDraft.status,trial_until:subDraft.trial_until||'',billing_notes:subDraft.billing_notes||''},'Subscription settings saved')}}><label>Price per billable resident / month (INR)<input type="number" min="0" max="100000" step="0.01" required value={subDraft?.price_per_resident??'39'} onChange={e=>setSubDraft({...subDraft,price_per_resident:e.target.value})}/></label><label>Status<select value={subDraft?.status||'trial'} onChange={e=>setSubDraft({...subDraft,status:e.target.value})}>{['trial','active','past_due','paused','cancelled'].map(x=><option value={x} key={x}>{x}</option>)}</select></label><label>Trial end date<input type="date" value={subDraft?.trial_until||''} onChange={e=>setSubDraft({...subDraft,trial_until:e.target.value})}/></label><label>Notes<textarea value={subDraft?.billing_notes||''} rows={3} maxLength={500} onChange={e=>setSubDraft({...subDraft,billing_notes:e.target.value})}/></label><button className="primary" disabled={loading}>Save subscription</button></form></section><section className="panel"><h3>Subscription estimate</h3><div className="calculation"><div><span>Registered residents</span><b>{detail.total_residents}</b></div><div><span>Billable residents</span><b>{detail.billable_residents}</b></div><div><span>Rate / resident</span><b>{money(subDraft?.price_per_resident||0)}</b></div><div className="total"><span>Estimated monthly subtotal</span><strong>{money(Number(subDraft?.price_per_resident||0)*detail.billable_residents)}</strong></div></div><p className="hint">GST, coupons, refunds, payment processing fees and proration are not yet calculated. Monthly invoices snapshot the resident count and rate when generated.</p><label>Invoice month<input type="month" value={period} onChange={e=>setPeriod(e.target.value)}/></label><button className="primary" disabled={loading||!inputDate.test(period)} onClick={()=>mutate(`/owners/${ownerId}/invoices`,'POST',{period},'Draft subscription invoice created')}>Generate monthly draft invoice</button><p className="hint">Owner subscription gateway checkout is not active. For now, only verified external/manual receipts may be recorded against issued invoices.</p></section></div>}
    </>}</>}
    {tab==='Invoices'&&<><div className="toolbar"><div><h2>IntProSec subscription invoices</h2><p>Monthly invoices billed to PG owners for use of COME.in.</p></div></div><Banner tone="info">Invoices are exclusive of GST and have no payment gateway integration in this build. Only confirm a manual payment after independently verifying the bank credit. Do not share this admin screen with PG owners.</Banner><section className="panel"><div className="table-scroll"><table><thead><tr><th>Invoice</th><th>Owner</th><th>Month</th><th>Billable</th><th>Rate</th><th>Subtotal</th><th>Status</th><th>Payment action</th></tr></thead><tbody>{invoices.map(i=><tr key={i.id}><td><strong>CI-{String(i.id).padStart(5,'0')}</strong></td><td>{owners.find(o=>o.id===i.tenant_id)?.business_name||`Owner #${i.tenant_id}`}</td><td>{i.period}</td><td>{i.billable_residents}</td><td>{money(i.unit_rate)}</td><td><b>{money(i.subtotal)}</b></td><td><Tag value={i.status}/></td><td>{i.status==='draft'?<button className="outline small" disabled={loading} onClick={()=>mutate(`/invoices/${i.id}/issue`,'POST',undefined,'Invoice issued')}>Issue</button>:i.status==='issued'?<div className="ref-action"><input aria-label={`Payment reference for invoice ${i.id}`} placeholder="Verified bank UTR" value={paymentRefs[i.id]||''} onChange={e=>setPaymentRefs({...paymentRefs,[i.id]:e.target.value})}/><button className="outline small" disabled={loading||(paymentRefs[i.id]||'').trim().length<4} onClick={()=>{if(window.confirm('Confirm the money was received in IntProSec bank account?'))mutate(`/invoices/${i.id}/confirm-manual-payment`,'POST',{payment_reference:paymentRefs[i.id]},'Payment recorded after manual verification')}}>Record received</button></div>:i.payment_reference?<small>Ref: {i.payment_reference}</small>:'—'}</td></tr>)}</tbody></table>{!invoices.length&&<Empty text="No subscription invoices yet. Generate an invoice from the Subscriptions tab."/>}</div></section></>}
    {tab==='Activity'&&<section className="panel"><h2>Administrator activity</h2><p className="hint">Latest recorded administrative mutations; use a central audit system before production.</p><div className="table-scroll"><table><thead><tr><th>Time</th><th>Action</th><th>Object</th></tr></thead><tbody>{audit.map(a=><tr key={a.id}><td>{new Date(a.created_at).toLocaleString('en-IN')}</td><td>{a.action.replaceAll('_',' ')}</td><td>{a.target}</td></tr>)}</tbody></table>{!audit.length&&<Empty text="No administrative activity recorded yet."/>}</div></section>}
    <footer className="footer"><span>COME.in · Platform administration · © 2026</span><span>Access is restricted to authorized IntProSec administrators.</span></footer>
    </main>
  </div>
}

createRoot(document.getElementById('root')).render(<App/>);
