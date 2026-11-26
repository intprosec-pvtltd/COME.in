import React,{useEffect,useMemo,useState} from 'react';
import{createRoot}from'react-dom/client';
import{LayoutDashboard,Building2,UsersRound,BedDouble,WalletCards,ReceiptText,ShieldCheck,LogOut,RefreshCw,Plus,CheckCircle2,AlertCircle,Search,ArrowUpRight,House,Layers,IndianRupee,Settings2,ClipboardList,Menu,X,LockKeyhole,UserRoundCog,UserCog,KeyRound,Save,SlidersHorizontal,BarChart3,Download,Power,Trash2}from'lucide-react';
import './style.css';
import SubscriptionPayments from './SubscriptionPayments.jsx';
import toast,{Toaster} from 'react-hot-toast';

const DEFAULT_API='http://127.0.0.1:8000';
const API=(import.meta.env.VITE_API_URL||DEFAULT_API).replace(/\/$/,'');
const fmt=new Intl.NumberFormat('en-IN',{style:'currency',currency:'INR',minimumFractionDigits:2});
const money=v=>fmt.format(Number(v||0));
const plural=(n,s)=>`${n} ${s}${n===1?'':'s'}`;
const nav=[['Overview',LayoutDashboard],['PG Owners',Building2],['Properties & Beds',BedDouble],['Subscriptions',WalletCards],['Invoices',ReceiptText],['User Management',UserCog],['Resident Verification',ShieldCheck],['Trial Management',ShieldCheck],['Feature Controls',SlidersHorizontal],['App Feedback',BarChart3]];
const currentPeriod=()=>{const d=new Date();return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}`};
const inputDate=/^\d{4}-(0[1-9]|1[0-2])$/;

function Logo({size='normal'}){return <img alt="Stay Sync - Spaces People Belong" className={`logo logo-${size}`} src="/branding/stay_sync_logo_original.png"/>}
function Attribution({login=false}){return <div className="attribution"><span>by</span><img src={login?"/branding/intprosec_admin_signin.jpg":"/intprosec.webp"} alt="IntProSec — Intelligence Protection Security"/></div>}
function Banner({children,tone='info',close}){return <div className={`banner ${tone}`}>{tone==='error'?<AlertCircle size={18}/>:<ShieldCheck size={18}/>}<span>{children}</span>{close&&<button className="bare" onClick={close}>Dismiss</button>}</div>}
function PasswordInput({label,...props}){
  const [visible,setVisible]=useState(false);
  return <div className="ss-password-wrap ss-admin-password"><input {...props} type={visible?'text':'password'}/><button type="button" className="ss-password-toggle" onClick={()=>setVisible(v=>!v)} aria-label={`${visible?'Hide':'Show'} ${label}`} aria-pressed={visible}>{visible?'Hide':'Show'}</button></div>;
}
function PrivatePhoto({tenantId,kind,id,token,size=42}){
  const [url,setUrl]=useState('');
  useEffect(()=>{
    if(!token||tenantId==null||id==null)return;
    let active=true,objectUrl='';
    fetch(`${API}/api/platform/display-photos/${tenantId}/${kind}/${id}`,{
      headers:{Authorization:`Bearer ${token}`}}).then(r=>r.ok?r.blob():null)
      .then(blob=>{if(blob&&active){objectUrl=URL.createObjectURL(blob);setUrl(objectUrl)}else if(active)setUrl('')})
      .catch(()=>{if(active)setUrl('')});
    return()=>{active=false;if(objectUrl)URL.revokeObjectURL(objectUrl)};
  },[tenantId,kind,id,token]);
  return url?<img src={url} alt={kind==='property'?'PG property photo':'Account photo'} className="ss-private-photo" style={{width:size,height:size,borderRadius:kind==='user'?'50%':10}}/>:
    <span className="ss-private-photo-placeholder" style={{width:size,height:size,borderRadius:kind==='user'?'50%':10}} aria-label="No photo uploaded">{kind==='user'?'👤':'🏠'}</span>;
}
function Stat({label,value,note,icon:Icon}){return <div className="stat"><div className="stat-top"><span>{label}</span><div className="iconwell">{Icon&&<Icon size={19}/>}</div></div><strong>{value}</strong>{note&&<small>{note}</small>}</div>}
const statusDescriptions={pending:'Awaiting trial approval',trial_active:'15-day trial is running',trial_expired:'Trial ended',suspended:'Access or subscription is paused',paid:'Paid subscription active',trial:'Trial plan',active:'Active',past_due:'Payment overdue',paused:'Paused',cancelled:'Cancelled',draft:'Invoice not sent yet',issued:'Invoice issued; awaiting verified payment',disabled:'Account disabled',owner:'PG owner',resident:'PG resident',manager:'PG manager',staff:'Staff member'};
function Tag({value}){const valueText=String(value??'unknown');return <span title={statusDescriptions[valueText]||valueText.replaceAll('_',' ')} className={`tag ${value==='active'||value==='paid'?'good':value==='trial'||value==='draft'?'soft':value==='past_due'||value==='issued'?'warn':'neutral'}`}>{({trial_active:'Trial running',trial_expired:'Trial ended',past_due:'Payment overdue',pending:'Pending approval',paid:'Paid',issued:'Awaiting payment',draft:'Draft',billable:'Billable'})[valueText]||valueText.replaceAll('_',' ')}</span>}
function Empty({text}){return <div className="empty"><Layers size={23}/><p>{text}</p></div>}

function App(){
  const [trials,setTrials]=useState([]);
  const [residentVerifications,setResidentVerifications]=useState([]);
  const [verificationSearch,setVerificationSearch]=useState('');
  const [trialFilter,setTrialFilter]=useState('all');
  const [trialSearch,setTrialSearch]=useState('');
  const [trialBusy,setTrialBusy]=useState(false);
  const [platformUsers,setPlatformUsers]=useState([]);
  const [userSearch,setUserSearch]=useState('');
  const [userRoleFilter,setUserRoleFilter]=useState('all');
  const [userOwnerFilter,setUserOwnerFilter]=useState('all');
  const [userStatusFilter,setUserStatusFilter]=useState('all');
  const [auditSearch,setAuditSearch]=useState('');
  const [editingUser,setEditingUser]=useState(null);
  const [profileDraft,setProfileDraft]=useState(null);
  const [profilePassword,setProfilePassword]=useState({current_password:'',new_password:''});
  const [profileVerification,setProfileVerification]=useState('');
  const [token,setToken]=useState(()=>sessionStorage.getItem('comein_platform_admin_token')||'');
  const [admin,setAdmin]=useState(null);
  const [tab,setTab]=useState(()=>{const saved=sessionStorage.getItem('staysync_admin_active_tab');return [...nav.map(([name])=>name),'Admin Profile','Activity'].includes(saved)?saved:'Overview'});
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
  const [showPassword,setShowPassword]=useState(false);
  const [refreshKey,setRefreshKey]=useState(0);
  const [create,setCreate]=useState({business_name:'',owner_name:'',owner_email:'',temporary_password:''});
  const [newPG,setNewPG]=useState({name:'',address:''});
  const [subDraft,setSubDraft]=useState(null);
  const [period,setPeriod]=useState(currentPeriod());
  const [paymentRefs,setPaymentRefs]=useState({});
  const [showCreate,setShowCreate]=useState(false);
  const [featureControls,setFeatureControls]=useState(null);
  const [featureBusy,setFeatureBusy]=useState(false);
  const [appFeedback,setAppFeedback]=useState(null);

  async function updateFeature(feature,enabled){
    setFeatureBusy(true);
    try{
      setFeatureControls(await request('/feature-controls/'+encodeURIComponent(feature.key),{method:'PUT',body:{enabled}}));
      notify('Feature policy saved');
    }catch(e){fail(e)}finally{setFeatureBusy(false)}
  }

  async function request(path,{method='GET',body,authToken=token}={}){
    const response=await fetch(`${API}/api/platform${path}`,{
      method,headers:{...(body!==undefined?{'Content-Type':'application/json'}:{}),...(authToken?{Authorization:`Bearer ${authToken}`}:{})},
      body:body===undefined?undefined:JSON.stringify(body)
    });
    const payload=await response.json().catch(()=>({}));
    if(!response.ok)throw new Error(typeof payload.detail==='string'?payload.detail:`Request failed (${response.status})`);
    return payload;
  }
  const fail=e=>{const msg=e?.message||'Unable to complete request';setError(msg);setSuccess('');toast.error(msg)};
  const notify=s=>{setSuccess(s);setError('');toast.success(s)};
  function logout(){sessionStorage.removeItem('staysync_admin_active_tab');sessionStorage.removeItem('comein_platform_admin_token');setToken('');setAdmin(null);setOverview(null);setOwners([]);setDetail(null);setPlatformUsers([]);setProfileDraft(null);setFeatureControls(null)}

  async function refresh(authToken=token){
    if(!authToken)return;
    setLoading(true);setError('');
    try{
      const [me,o,list,inv]=await Promise.all([
        request('/auth/me',{authToken}),request('/overview',{authToken}),request('/owners',{authToken}),request('/invoices',{authToken})
      ]);
      setAdmin(me);setOverview(o);setOwners(list);setInvoices(inv);setProfileDraft(p=>p||{name:me.name,email:me.email});
      if(tab==='Trial Management')setTrials(await request('/trials',{authToken}));
      if(tab==='Resident Verification')setResidentVerifications(await request('/resident-verifications',{authToken}));
      if(tab==='Activity')setAudit(await request('/audit',{authToken}));
      if(tab==='App Feedback')setAppFeedback(await request('/app-feedback',{authToken}));
      if(tab==='Feature Controls')setFeatureControls(await request('/feature-controls',{authToken}));
      if(tab==='User Management')setPlatformUsers(await request('/users',{authToken}));
      if(ownerId)setDetail(await request(`/owners/${ownerId}`,{authToken}));
    }catch(e){if(/401|expired|administrator sign-in/i.test(e.message))logout();fail(e)}finally{setLoading(false)}
  }
  useEffect(()=>{if(token)refresh(token)},[token]);
  async function signIn(e){e.preventDefault();setLoading(true);setError('');try{
    const result=await request('/auth/login',{method:'POST',body:credentials,authToken:''});
    sessionStorage.setItem('comein_platform_admin_token',result.access_token);
    setToken(result.access_token);setCredentials({email:'',password:''});
  }catch(e){fail(e)}finally{setLoading(false)}}
  async function chooseOwner(id){
    if(!id){setOwnerId(null);setDetail(null);setSubDraft(null);setError('');return;}
    setOwnerId(id);setDetail(null);setSubDraft(null);setError('');try{
    const x=await request(`/owners/${id}`);setDetail(x);setSubDraft({...x.subscription});
  }catch(e){fail(e)}}
  async function mutate(path,method,body,message,{reloadDetail=true}={}){
    setLoading(true);try{await request(path,{method,body});notify(message);await refresh();if(reloadDetail&&ownerId){const d=await request(`/owners/${ownerId}`);setDetail(d);setSubDraft({...d.subscription})}return true}catch(e){fail(e);return false}finally{setLoading(false)}
  }
  async function addOwner(e){e.preventDefault();const result=await mutate('/owners','POST',create,'PG owner registered. Share the temporary password securely.');if(result){setCreate({business_name:'',owner_name:'',owner_email:'',temporary_password:''});setShowCreate(false)}}
  async function addPG(e){e.preventDefault();if(!ownerId)return;const ok=await mutate(`/owners/${ownerId}/properties`,'POST',newPG,'PG property created');if(ok)setNewPG({name:'',address:''})}
  const matchingOwners=useMemo(()=>owners.filter(o=>`${o.business_name} ${o.owners.map(x=>`${x.name} ${x.email}`).join(' ')}`.toLowerCase().includes(search.toLowerCase())),[owners,search]);
  async function setNav(value){
    sessionStorage.setItem('staysync_admin_active_tab',value);
    setTab(value);setMobileNav(false);setError('');
    if(token&&value==='Trial Management'){try{setTrials(await request('/trials'))}catch(e){fail(e)}}
    if(token&&value==='Resident Verification'){try{setResidentVerifications(await request('/resident-verifications'))}catch(e){fail(e)}}
    if(token&&value==='Feature Controls'){
      setFeatureControls(null);
      try{setFeatureControls(await request('/feature-controls'))}catch(e){fail(e)}
    }
    if(token&&value==='App Feedback'){try{setAppFeedback(await request('/app-feedback'))}catch(e){fail(e)}}
    if(token&&value==='Activity'){try{setAudit(await request('/audit'))}catch(e){fail(e)}}
    if(token&&value==='User Management'){try{setPlatformUsers(await request('/users'))}catch(e){fail(e)}}
    if(value==='Admin Profile'&&admin){setProfileDraft({name:admin.name,email:admin.email});setProfileVerification('')}
  }
  async function trialAction(tenantId,action){
    if(trialBusy)return;
    let reason=window.prompt(`Reason for ${action.replaceAll('_',' ')} (minimum 8 characters):`);
    if(!reason||reason.trim().length<8)return;
    const body={reason:reason.trim()};
    if(action==='extend'){
      const days=Number(window.prompt('Extension days (1 to 30):','7'));
      if(!Number.isInteger(days)||days<1||days>30){fail(new Error('Choose 1 to 30 days'));return;}
      body.days=days;
    }
    if(action==='convert'){
      if(!window.confirm('Have you independently verified payment? This activates a paid subscription.'))return;
      body.payment_verified=true;
    }
    if(!window.confirm(`Confirm ${action} for PG #${tenantId}? This will be audited.`))return;
    setTrialBusy(true);
    try{
      await request(`/trials/${tenantId}/${action}`,{method:'POST',body});
      setTrials(await request('/trials'));
      notify(`Trial action completed: ${action}`);
      await refresh();
    }catch(e){fail(e)}finally{setTrialBusy(false)}
  }
  const filteredTrials=trials.filter(t=>(trialFilter==='all'||t.status===trialFilter)&&`${t.business_name} ${t.tenant_id}`.toLowerCase().includes(trialSearch.toLowerCase()));
  async function saveProfile(e){
    e.preventDefault();setLoading(true);
    try{const updated=await request('/profile',{method:'PUT',body:{...profileDraft,current_password:profileVerification}});
      setAdmin(updated);setProfileDraft({name:updated.name,email:updated.email});setProfileVerification('');notify('Administrator profile updated');}
    catch(e){fail(e)}finally{setLoading(false)}
  }
  async function savePassword(e){
    e.preventDefault();setLoading(true);
    try{await request('/profile/password',{method:'POST',body:profilePassword});logout();notify('Password changed. Sign in with your new password.');}
    catch(e){fail(e)}finally{setLoading(false)}
  }
  async function saveUser(e){
    e.preventDefault();setLoading(true);
    try{const result=await request(`/users/${editingUser.id}`,{method:'PUT',body:{name:editingUser.name,email:editingUser.email,role:editingUser.role,room:editingUser.room||'',is_active:editingUser.is_active}});
      if(editingUser.role==='resident'&&Number(editingUser.monthly_rent||0)>=0){await request(`/users/${editingUser.id}/monthly-rent`,{method:'PUT',body:{monthly_rent:editingUser.monthly_rent||'0'}});}
      setPlatformUsers(await request('/users'));setEditingUser(null);notify('User updated and change recorded in audit log');}
    catch(e){fail(e)}finally{setLoading(false)}
  }
  const filteredUsers=useMemo(()=>platformUsers.filter(u=>{
    const matchesSearch=`${u.name||''} ${u.email||''} ${u.role||''} ${u.tenant_name||''}`.toLowerCase().includes(userSearch.trim().toLowerCase());
    return matchesSearch&&(userRoleFilter==='all'||u.role===userRoleFilter)&&(userOwnerFilter==='all'||String(u.tenant_id)===userOwnerFilter)&&(userStatusFilter==='all'||(userStatusFilter==='active'?u.is_active:!u.is_active));
  }),[platformUsers,userSearch,userRoleFilter,userOwnerFilter,userStatusFilter]);
  const accountGroups=[
    {key:'owner',title:'PG owners',description:'Accounts that own or administer PG organizations',roles:['owner']},
    {key:'resident',title:'Residents',description:'Registered residents across PG organizations',roles:['resident']},
    {key:'team',title:'Managers and staff',description:'Operational team members and PG managers',roles:['manager','staff']}
  ];
  const existingInvoice=invoices.find(i=>i.tenant_id===ownerId&&i.period===period);
  const invoiceEligible=Boolean(detail&&ownerId&&['active','past_due'].includes(detail.subscription.status));
  useEffect(()=>{if(editingUser)document.getElementById('comein-user-editor')?.scrollIntoView({behavior:'smooth',block:'start'});},[editingUser?.id]);
  const auditFiltered=audit.filter(a=>`${a.action||''} ${a.target||''} ${a.created_at||''}`.toLowerCase().includes(auditSearch.toLowerCase()));


  const PageIcon=nav.find(([name])=>name===tab)?.[1]||(tab==='Admin Profile'?UserRoundCog:ClipboardList);
  if(!token)return <><Toaster position="top-right" toastOptions={{duration:3500}}/><div className="login-scene"><div className="login-frame"><div className="login-top"><Logo/><div className="login-emblem"><LockKeyhole size={20}/></div></div><div className="login-copy"><h1>Platform administrator sign-in</h1></div><form onSubmit={signIn} className="login-fields"><label>Administrator email<input type="email" required autoComplete="username" value={credentials.email} onChange={e=>setCredentials({...credentials,email:e.target.value})} placeholder="admin@yourcompany.com"/></label><label>Password<div className="ss-password-wrap"><input type={showPassword?'text':'password'} required autoComplete="current-password" value={credentials.password} onChange={e=>setCredentials({...credentials,password:e.target.value})} placeholder="Administrator password"/><button className="ss-password-toggle" type="button" onClick={()=>setShowPassword(v=>!v)} aria-label={showPassword?'Hide password':'Show password'} aria-pressed={showPassword}>{showPassword?'Hide':'Show'}</button></div></label>{error&&<Banner tone="error">{error}</Banner>}<button className="primary full" disabled={loading} type="submit">{loading?'Signing in…':'Sign in to platform'} <ArrowUpRight size={17}/></button></form><Attribution login/></div></div></>;

  return <div className="app-shell"><Toaster position="top-right" toastOptions={{duration:3500}}/>
    <aside className={`sidebar ${mobileNav?'show':''}`}><div className="sidebar-head"><div className="sidebar-brand"><button type="button" onClick={()=>setNav("Overview")} aria-label="Go to Overview" title="Go to Overview" style={{border:0,background:"transparent",padding:0,cursor:"pointer",display:"block",width:"100%"}}><img className="sidebar-horizontal-logo" src="/branding/stay_sync_manage_sidebar_purple.png" alt="Stay Sync Manage" /></button></div><button className="mobile-close bare" aria-label="Close navigation" onClick={()=>setMobileNav(false)}><X/></button></div>
      <nav aria-label="Platform administration">{nav.map(([name,Icon])=><button key={name} aria-current={tab===name?"page":undefined} className={`nav-item ${tab===name?'active':''}`} onClick={()=>setNav(name)}><Icon size={19}/><span>{name}</span></button>)}</nav>
      <div className="side-bottom"><div className="sidebar-account-row"><button type="button" className={`admin-chip admin-profile-trigger ${tab==='Admin Profile'?'selected':''}`} onClick={()=>setNav('Admin Profile')} title="Open administrator profile" aria-label="Open administrator profile"><div className="avatar">{(admin?.name||'A')[0].toUpperCase()}</div><div className="admin-meta"><strong>{admin?.name||'Administrator'}</strong><small>{admin?.email||'Privileged access'}</small></div></button><button type="button" className="sidebar-signout" onClick={logout} title="Sign out of platform administrator account" aria-label="Sign out"><LogOut size={16}/><span>Sign out</span></button></div><Attribution/></div>
    </aside>
    {mobileNav&&<div className="scrim" onClick={()=>setMobileNav(false)}/>}
    <main className="content"><header className="page-header"><div className="header-left"><button className="mobile-menu bare" aria-label="Open navigation" aria-expanded={mobileNav} onClick={()=>setMobileNav(true)}><Menu/></button><div><h1 className="page-title"><span className="page-title-icon"><PageIcon size={21} aria-hidden="true"/></span>{tab}</h1></div></div><div className="header-actions">
      <button className="outline header-refresh" type="button" title="Refresh dashboard" aria-label="Refresh dashboard" onClick={()=>{refresh();setRefreshKey(k=>k+1)}} disabled={loading}><RefreshCw size={18} aria-hidden="true" className={loading?'spin':''}/></button></div></header>
    {tab==='Admin Profile'&&<>
      <div className="toolbar"><div><h2>Administrator profile</h2><p>Manage your own privileged Stay Sync Manage platform account.</p></div></div>
      <div className="two-col admin-settings">
        <section className="panel"><div className="profile-heading"><div className="avatar profile-avatar">{(admin?.name||'A')[0].toUpperCase()}</div><div><h3>{admin?.name}</h3><p className="hint">Platform administrator · {admin?.email}</p></div></div>
          <form className="stack" onSubmit={saveProfile}><label>Full name<input required minLength={2} maxLength={120} value={profileDraft?.name||''} onChange={e=>setProfileDraft({...profileDraft,name:e.target.value})}/></label><label>Email address<input type="email" required maxLength={160} value={profileDraft?.email||''} onChange={e=>setProfileDraft({...profileDraft,email:e.target.value})}/></label><label>Confirm current password<PasswordInput label="confirmation password" required autoComplete="current-password" value={profileVerification} onChange={e=>setProfileVerification(e.target.value)}/></label><button className="primary" disabled={loading}><Save size={16}/> Save profile</button></form>
        </section>
        <section className="panel"><h3><KeyRound size={18}/> Change password</h3><p className="hint">Use a unique password with at least 12 characters. You will be signed out after updating it.</p><form className="stack" onSubmit={savePassword}><label>Current password<PasswordInput label="current password" required autoComplete="current-password" value={profilePassword.current_password} onChange={e=>setProfilePassword({...profilePassword,current_password:e.target.value})}/></label><label>New password<PasswordInput label="new password" required minLength={12} maxLength={128} autoComplete="new-password" value={profilePassword.new_password} onChange={e=>setProfilePassword({...profilePassword,new_password:e.target.value})}/></label><button className="primary" disabled={loading}>Update password</button></form><Banner tone="info">Changing an administrator password does not automatically revoke existing tokens. Sessions expire according to the current backend token policy.</Banner></section>
      </div>
    </>}
    {tab==='User Management'&&<>
      <div className="toolbar"><div><h2>User management</h2><p>Manage PG owners, managers, residents and staff. Eligible PG owner and resident accounts can be deleted directly. Linked records and the last active owner are protected.</p></div></div>
      <div className="admin-filterbar">
        <div className="searchbar"><Search size={17}/><input aria-label="Search users" placeholder="Search name, email or PG" value={userSearch} onChange={e=>setUserSearch(e.target.value)}/></div>
        <label>Account type<select aria-label="Filter by role" value={userRoleFilter} onChange={e=>setUserRoleFilter(e.target.value)}><option value="all">All roles</option><option value="owner">Owners</option><option value="resident">Residents</option><option value="manager">Managers</option><option value="staff">Staff</option></select></label>
        <label>PG organization<select aria-label="Filter users by PG" value={userOwnerFilter} onChange={e=>setUserOwnerFilter(e.target.value)}><option value="all">All PGs</option>{owners.map(o=><option key={o.id} value={String(o.id)}>{o.business_name}</option>)}</select></label>
        <label>Account status<select aria-label="Filter user status" value={userStatusFilter} onChange={e=>setUserStatusFilter(e.target.value)}><option value="all">All statuses</option><option value="active">Active</option><option value="disabled">Disabled</option></select></label>
        <button type="button" className="outline small clear-filters" onClick={()=>{setUserSearch('');setUserRoleFilter('all');setUserOwnerFilter('all');setUserStatusFilter('all')}}>Clear filters</button>
      </div>
      <p className="results-summary">Showing {filteredUsers.length} of {platformUsers.length} registered accounts</p>
      {accountGroups.map(group=>{
        const users=filteredUsers.filter(u=>group.roles.includes(u.role));
        return <section className="panel account-group" key={group.key}><div className="panel-title"><div><h3>{group.title}</h3><p className="hint">{group.description}</p></div><span className="count-pill">{plural(users.length,'account')}</span></div>
          <div className="table-scroll"><table><thead><tr><th>Account</th><th>Organization</th><th>Role</th><th>Status</th><th>Action</th></tr></thead><tbody>{users.map(u=><tr key={u.id}><td><strong>{u.name}</strong><small>{u.email}</small></td><td>{u.tenant_name||'—'}</td><td><Tag value={u.role}/></td><td><Tag value={u.is_active?'active':'disabled'}/></td><td><div className="account-actions"><button type="button" className="outline small account-action" onClick={()=>setEditingUser({...u})}><UserCog size={15}/> Edit</button>{u.is_active&&u.role!=='resident'&&<button type="button" className="outline small account-action account-deactivate" disabled={loading} onClick={async()=>{if(!window.confirm(`Deactivate ${u.name}? Sign-in access will be removed; property, rent, invoices and verification history will be retained.`))return;await mutate(`/users/${u.id}`,'PUT',{name:u.name,email:u.email,role:u.role,room:u.room||'',is_active:false},'Account deactivated');setPlatformUsers(await request('/users'));}}><Power size={14}/> Deactivate</button>}{(!u.is_active||['resident','owner'].includes(u.role))&&<button type="button" className="outline small account-action account-deactivate" disabled={loading} onClick={async()=>{
            try {
              const review=await request(`/users/${u.id}/deletion-review`);
              if(!review.eligible){window.alert(`Permanent deletion blocked. Related records: ${Object.entries(review.blockers||{}).map(([k,v])=>`${k}: ${v}`).join(', ')}`);return;}
              const confirmation=window.prompt(`PERMANENT DELETE: ${u.name}. This cannot be undone. Enter the exact account email (${u.email}) to continue:`);
              if(confirmation?.trim().toLowerCase()!==u.email.toLowerCase())return;
              if(!window.confirm('Permanently delete this account?'))return;
              await request(`/users/${u.id}`,{method:'DELETE',body:{confirm_email:confirmation}});
              setPlatformUsers(await request('/users'));window.alert('Account permanently deleted.');
            } catch(e){fail(e)}
          }}><Trash2 size={14}/> Delete permanently</button>}</div></td></tr>)}</tbody></table>{!users.length&&<Empty text="No accounts match these filters."/>}</div>
        </section>;
      })}
      {editingUser&&<section id="comein-user-editor" className="panel user-editor"><div className="panel-title"><h3>Edit user #{editingUser.id}</h3><button className="outline small" onClick={()=>setEditingUser(null)}>Cancel</button></div><form className="form-grid" onSubmit={saveUser}><label>Full name<input required minLength={2} maxLength={120} value={editingUser.name} onChange={e=>setEditingUser({...editingUser,name:e.target.value})}/></label><label>Email<input required type="email" maxLength={160} value={editingUser.email} onChange={e=>setEditingUser({...editingUser,email:e.target.value})}/></label><label>Role<select value={editingUser.role} onChange={e=>setEditingUser({...editingUser,role:e.target.value})}>{['owner','manager','resident','staff'].map(role=><option key={role} value={role}>{role}</option>)}</select></label><label>Room<input maxLength={30} value={editingUser.room||''} onChange={e=>setEditingUser({...editingUser,room:e.target.value})}/></label>{editingUser.role==='resident'&&<label>Monthly rent (₹)<input type="number" min="0" step="0.01" value={editingUser.monthly_rent??'0'} onChange={e=>setEditingUser({...editingUser,monthly_rent:e.target.value})}/></label>}<label>Account access<select value={editingUser.is_active?'active':'disabled'} onChange={e=>setEditingUser({...editingUser,is_active:e.target.value==='active'})}><option value="active">Active</option><option value="disabled">Disabled</option></select></label><div className="form-actions"><button className="primary" disabled={loading}><Save size={16}/> Save user changes</button></div></form><p className="hint">Disabled users cannot sign in or use their existing sessions. The last active PG owner cannot be disabled or demoted.</p></section>}
    </>}
    {tab==='Overview'&&<>

      <div className="stats"><Stat label="PG owners" value={overview?.owners??'—'} icon={UsersRound} note="PG organizations with owner accounts"/><Stat label="Properties" value={overview?.pgs??'—'} icon={Building2} note="Registered PG locations"/><Stat label="Billable residents" value={overview?.billable_residents??'—'} icon={UsersRound} note="Residents counted for monthly charges"/><Stat label="Monthly estimate" value={overview?money(overview.estimated_monthly_revenue):'—'} icon={IndianRupee} note="Estimated from billable residents only; not collected revenue"/></div>
      <div className="two-col"><section className="panel"><div className="panel-title"><h3>PG organizations and expected charges</h3><button className="text-action" onClick={()=>setNav('PG Owners')}>View all <ArrowUpRight size={16}/></button></div><div className="table-scroll"><table><thead><tr><th>PG owner</th><th>Properties</th><th>Registered residents</th><th>Monthly estimate</th></tr></thead><tbody>{(overview?.owner_rows||[]).slice(0,8).map(o=><tr key={o.id}><td><strong>{o.business_name}</strong><small>{o.owners[0]?.name||'No owner assigned'}</small></td><td>{o.pg_count}</td><td>{o.total_residents}</td><td>{money(o.subscription.estimated_monthly)}</td></tr>)}</tbody></table>{!overview?.owner_rows?.length&&<Empty text="No PG owners yet. Add one in PG Owners."/>}</div></section>
      <section className="panel highlights"><h3>Payments and outstanding invoices</h3><div className="figure"><small>Payments verified as received</small><strong>{overview?money(overview.confirmed_collected):'—'}</strong></div><div className="detail-row"><span>Issued invoices not yet paid</span><b>{overview?money(overview.outstanding):'—'}</b></div><div className="detail-row"><span>Total invoiced (excluding cancelled invoices)</span><b>{overview?money(overview.invoiced_total):'—'}</b></div><p className="hint">Record payments after confirming receipt.</p><button className="primary" onClick={()=>setNav('Invoices')}>Open billing ledger <ArrowUpRight size={16}/></button></section></div>
    </>}
    {tab==='PG Owners'&&<><div className="toolbar"><div><h2>PG owners & operators</h2><p>Each owner can manage multiple properties under their organization.</p></div><button className="primary" onClick={()=>setShowCreate(v=>!v)}><Plus size={17}/> Add PG owner</button></div>
      {showCreate&&<section className="panel"><h3>Register a PG owner</h3><p className="hint">Create a dedicated owner account and tenant organization. Share the temporary password privately; require password rotation before production use.</p><form className="form-grid" onSubmit={addOwner}><label>Business / PG brand<input required value={create.business_name} maxLength={120} onChange={e=>setCreate({...create,business_name:e.target.value})}/></label><label>Owner full name<input required value={create.owner_name} maxLength={120} onChange={e=>setCreate({...create,owner_name:e.target.value})}/></label><label>Owner email<input type="email" required value={create.owner_email} onChange={e=>setCreate({...create,owner_email:e.target.value})}/></label><label>Temporary password (12+)<PasswordInput label="temporary password" required minLength={12} autoComplete="new-password" value={create.temporary_password} onChange={e=>setCreate({...create,temporary_password:e.target.value})}/></label><div className="form-actions"><button className="primary" disabled={loading}>Create owner</button><button type="button" className="outline" onClick={()=>setShowCreate(false)}>Cancel</button></div></form></section>}
      <section className="panel"><div className="searchbar"><Search size={18}/><input placeholder="Search owner, PG, or email" value={search} onChange={e=>setSearch(e.target.value)}/></div><div className="table-scroll"><table><thead><tr><th>Organization</th><th>PGs</th><th>Beds</th><th>Residents</th><th>Billable</th><th>Subscription</th><th>Projected charge</th><th></th></tr></thead><tbody>{matchingOwners.map(o=><tr key={o.id}><td><strong>{o.business_name}</strong><small>{o.owners[0]?.name} · {o.owners[0]?.email}</small></td><td>{o.pg_count}</td><td>{o.total_beds}</td><td>{o.total_residents}</td><td>{o.billable_residents}</td><td><Tag value={o.subscription.status}/></td><td>{money(o.subscription.estimated_monthly)}</td><td><button className="outline small" onClick={()=>{chooseOwner(o.id);setTab('Properties & Beds')}}>Manage</button></td></tr>)}</tbody></table>{!matchingOwners.length&&<Empty text="No PG owners match your search."/>}</div></section></>}
    {(tab==='Properties & Beds'||tab==='Subscriptions')&&<>
    {tab==='Subscriptions'&&<SubscriptionPayments apiBase={API} token={token} refreshKey={refreshKey}/>}
<div className="toolbar"><div><h2>{tab==='Properties & Beds'?'Properties, rooms and capacity':'Subscription details by PG'}</h2><p>{tab==='Properties & Beds'?'View room capacity and occupancy for each PG. Bed capacity is for room management only.':'Review how many residents are charged and each PG owner’s monthly subscription estimate.'}</p></div><label className="owner-picker">PG organization<select aria-label="Filter by PG organization" value={ownerId??''} onChange={e=>chooseOwner(e.target.value?Number(e.target.value):null)}><option value="">All PGs</option>{owners.map(o=><option key={o.id} value={o.id}>{o.business_name}</option>)}</select></label></div>
    {!ownerId?<>
      <div className="stats"><Stat label="PG organizations" value={owners.length} icon={Building2}/><Stat label="Properties" value={owners.reduce((n,o)=>n+Number(o.pg_count||0),0)} icon={House}/><Stat label="Beds" value={owners.reduce((n,o)=>n+Number(o.total_beds||0),0)} icon={BedDouble}/><Stat label="Residents" value={owners.reduce((n,o)=>n+Number(o.total_residents||0),0)} icon={UsersRound}/><Stat label="Monthly estimate" value={money(owners.reduce((n,o)=>n+Number(o.subscription?.estimated_monthly||0),0))} icon={IndianRupee}/></div>
      <section className="panel"><div className="panel-title"><div><h3>{tab==='Subscriptions'?'Subscriptions by PG':'PG properties and capacity'}</h3><p className="hint">All PG organizations are shown by default. Select a PG to edit its details.</p></div><span className="count-pill">{owners.length} PGs</span></div><div className="table-scroll"><table><thead><tr><th>Organization</th><th>Properties</th><th>Beds</th><th>Residents</th><th>{tab==='Subscriptions'?'Plan status':'Billable'}</th><th>Monthly estimate</th><th>Action</th></tr></thead><tbody>{owners.map(o=><tr key={o.id}><td><strong>{o.business_name}</strong><small>{o.owners?.[0]?.name||'PG organization'}</small></td><td>{o.pg_count}</td><td>{o.total_beds}</td><td>{o.total_residents}</td><td>{tab==='Subscriptions'?<Tag value={o.subscription?.status}/>:o.billable_residents}</td><td>{money(o.subscription?.estimated_monthly)}</td><td><button type="button" className="outline small" onClick={()=>chooseOwner(o.id)}>Manage</button></td></tr>)}</tbody></table>{!owners.length&&<Empty text="No PG organizations have been registered."/>}</div></section>
      </>:!detail?<Empty text="Loading selected PG organization…"/>:<>
      <div className="stats"><Stat label="Properties" value={detail.pg_count} icon={Building2}/><Stat label="Beds" value={detail.total_beds} icon={BedDouble}/><Stat label="Registered residents" value={detail.total_residents} icon={UsersRound}/><Stat label="Billable" value={detail.billable_residents} icon={WalletCards}/><Stat label="Monthly subtotal" value={money(detail.subscription.estimated_monthly)} icon={IndianRupee}/></div>
      {tab==='Properties & Beds'?<>
      {(detail.unassigned_rooms>0||detail.unassigned_residents>0)&&<p className="hint">{detail.unassigned_rooms} unassigned rooms · {detail.unassigned_residents} unassigned residents</p>}
      <div className="two-col"><section className="panel"><h3>Registered PG properties</h3>{detail?.owners?.[0]&&<div className="ss-owner-photo"><PrivatePhoto tenantId={ownerId} kind="user" id={detail.owners[0].id} token={token}/><span>PG owner profile</span></div>}{detail.properties.length?detail.properties.map(p=><div className="property" key={p.id}><div className="property-name"><PrivatePhoto tenantId={ownerId} kind="property" id={p.id} token={token}/><div><strong>{p.name}</strong><small>{p.address||'No address provided'}</small></div></div><div className="property-stats"><span>{plural(p.rooms,'room')}</span><span>{plural(p.beds,'bed')}</span><span>{plural(p.residents,'resident')}</span></div></div>):<Empty text="No PG properties registered yet."/>}</section><section className="panel"><h3>Add PG location</h3><p className="hint">A PG organization can have multiple locations. Capacity comes from existing room records; adding a property does not invent beds.</p><form className="stack" onSubmit={addPG}><label>Property name<input required value={newPG.name} onChange={e=>setNewPG({...newPG,name:e.target.value})} placeholder="e.g. Sunrise PG — North Wing"/></label><label>Address<input value={newPG.address} onChange={e=>setNewPG({...newPG,address:e.target.value})} placeholder="PG location"/></label><button className="primary" disabled={loading}>Add property</button></form></section></div>
      <div className="two-col"><section className="panel"><h3>Assign existing rooms to PGs</h3>{detail.rooms.length?detail.rooms.map(r=><div className="assign-row" key={r.id}><div><b>{r.name}</b><small>{r.beds} beds</small></div><select aria-label={`Property assignment for room ${r.name}`} value={r.property_id??''} onChange={e=>mutate(`/owners/${ownerId}/properties/${e.target.value}/rooms/${r.id}`,'PUT',undefined,'Room assigned')}><option value="">Unassigned</option>{detail.properties.map(p=><option key={p.id} value={p.id}>{p.name}</option>)}</select></div>):<Empty text="No rooms are recorded in this owner's existing backend."/>}</section><section className="panel"><h3>Assign residents and billing status</h3><p className="hint">In the uploaded backend, a registered resident has no separate active/inactive field. All registered residents are billable by default; exclusions need a reason.</p>{detail.residents.length?detail.residents.map(r=><div className="resident-row" key={r.id}><PrivatePhoto tenantId={ownerId} kind="user" id={r.id} token={token}/><div><b>{r.name}</b><small>{r.room||'Room not set'} · {r.email} · Monthly rent {money(Number(r.monthly_rent||0))}</small></div><div className="resident-controls"><select aria-label={`Property for ${r.name}`} value={r.property_id??''} onChange={e=>mutate(`/owners/${ownerId}/properties/${e.target.value}/residents/${r.id}`,'PUT',undefined,'Resident assigned')}><option value="">Unassigned</option>{detail.properties.map(p=><option key={p.id} value={p.id}>{p.name}</option>)}</select><label className="checkbox"><input type="checkbox" checked={r.billable} onChange={e=>{const billable=e.target.checked;const reason=billable?'':window.prompt('Reason for excluding this resident from billing:');if(!billable&&!reason)return;mutate(`/owners/${ownerId}/residents/${r.id}/billing`,'PUT',{excluded:!billable,reason:reason||''},'Billing eligibility updated')}}/> Billable</label></div></div>):<Empty text="No registered residents yet."/>}</section></div>
      </>:<div className="two-col"><section className="panel"><div className="panel-title"><h3>Monthly price and subscription status</h3><Tag value={detail.subscription.status}/></div><p className="hint">Billing counts billable residents plus distinct active owner accounts, with 18% GST for new invoices. Beds are not billed.</p><form className="stack" onSubmit={e=>{e.preventDefault();mutate(`/owners/${ownerId}/subscription`,'PUT',{price_per_resident:'39.00',status:subDraft.status,trial_until:subDraft.trial_until||'',billing_notes:subDraft.billing_notes||''},'Subscription settings saved')}}><div className="ss-fixed-rate"><strong>Stay Sync Manage · ₹39 / billable resident or owner / month + GST</strong><p className="hint">Single plan. This price is fixed for new invoices; beds are capacity only.</p></div><label>Status<select value={subDraft?.status||'trial'} onChange={e=>setSubDraft({...subDraft,status:e.target.value})}>{['trial','active','past_due','paused','cancelled'].map(x=><option value={x} key={x}>{x}</option>)}</select></label><label>Trial end date<input type="date" value={subDraft?.trial_until||''} onChange={e=>setSubDraft({...subDraft,trial_until:e.target.value})}/></label><label>Notes<textarea value={subDraft?.billing_notes||''} rows={3} maxLength={500} onChange={e=>setSubDraft({...subDraft,billing_notes:e.target.value})}/></label><button className="primary" disabled={loading}>Save subscription</button></form></section><section className="panel"><h3>How the monthly charge is calculated</h3><div className="calculation"><div><span>Registered residents</span><b>{detail.total_residents}</b></div><div><span>Billable residents</span><b>{detail.billable_residents}</b></div><div><span>Billable owners</span><b>{detail.billable_owners||1}</b></div><div><span>Rate / person</span><b>{money(39)}</b></div><div className="total"><span>Estimated monthly total incl. GST</span><strong>{money(39*(detail.billable_residents+(detail.billable_owners||1))*1.18)}</strong></div></div><p className="hint">New invoices snapshot billable residents, owners, GST and total; historical invoices retain original values. Tax treatment must follow registered company details.</p><div className="invoice-actions"><label>Invoice month<input type="month" value={period} onChange={e=>setPeriod(e.target.value)}/></label><button type="button" className="primary invoice-generate" disabled={loading||!inputDate.test(period)||!invoiceEligible||Boolean(existingInvoice)||subDraft?.status!==detail.subscription.status} title={!invoiceEligible?'Activate the subscription before generating invoices':existingInvoice?'An invoice already exists for this month':'Generate a monthly draft invoice'} onClick={async()=>{const ok=await mutate(`/owners/${ownerId}/invoices`,'POST',{period},'Draft subscription invoice created');if(ok)setTab('Invoices')}}><ReceiptText size={17}/> Generate draft invoice</button>{!invoiceEligible?<p className="hint invoice-hint">Activate the subscription and save it before generating an invoice.</p>:existingInvoice?<p className="hint invoice-hint">Invoice CI-{String(existingInvoice.id).padStart(5,'0')} already exists for {period}. Open Invoices to view it.</p>:subDraft?.status!==detail.subscription.status?<p className="hint invoice-hint">Save subscription changes before creating an invoice.</p>:<p className="hint invoice-hint">A draft will be created for this PG and month; issue it from the Invoices page.</p>}</div><p className="hint">Owner subscription gateway checkout is not active. For now, only verified external/manual receipts may be recorded against issued invoices.</p></section></div>}
    </>}</>}
    {tab==='Resident Verification'&&<>
      <div className="toolbar"><div><h2>Resident onboarding &amp; verification</h2><p>View photo and identity-document review progress by owner organization and property. Documents are private and are reviewed by authorized PG owners.</p></div></div>
      <div className="stats">
        <Stat label="Registered residents" value={residentVerifications.length} icon={UsersRound}/>
        <Stat label="Missing documents" value={residentVerifications.filter(v=>v.photo_status==='not_submitted'||v.identity_status==='not_submitted').length} icon={AlertCircle}/>
        <Stat label="Awaiting PG owner review" value={residentVerifications.filter(v=>v.photo_status==='pending'||v.identity_status==='pending').length} icon={ShieldCheck}/>
        <Stat label="Fully reviewed" value={residentVerifications.filter(v=>v.photo_status==='approved'&&v.identity_status==='approved').length} icon={CheckCircle2}/>
      </div>
      <section className="panel"><div className="searchbar"><Search size={17}/><input aria-label="Find resident verification" placeholder="Search name, PG or organization" value={verificationSearch} onChange={e=>setVerificationSearch(e.target.value)}/></div>
      <div className="table-scroll"><table><thead><tr><th>Resident</th><th>PG organization</th><th>Assigned property</th><th>Photograph</th><th>Identity document</th></tr></thead>
      <tbody>{residentVerifications.filter(v=>`${v.resident_name} ${v.organization} ${v.property_name}`.toLowerCase().includes(verificationSearch.toLowerCase())).map(v=><tr key={`${v.tenant_id}:${v.resident_id}`}><td><strong>{v.resident_name}</strong></td><td>{v.organization}</td><td><Building2 size={15}/> {v.property_name}</td><td><Tag value={v.photo_status}/></td><td><Tag value={v.identity_status}/></td></tr>)}</tbody></table>
      {!residentVerifications.length&&<Empty text="No residents are registered yet."/>}</div>
      <p className="hint">The dashboard displays verification status only. Identity images are not exposed to platform administrators through this page.</p></section>
    </>}
    {tab==='Trial Management'&&<>
      <div className="toolbar"><div><h2>Trial management</h2><p>Owners can activate their one-time 15-day trial. Review expiring trials, record extensions, and confirm payment before access resumes.</p></div></div>

      <div className="stats"><Stat label="Pending approval" value={trials.filter(x=>x.status==='pending').length} icon={UsersRound}/><Stat label="Active trials" value={trials.filter(x=>x.status==='trial_active').length} icon={ShieldCheck}/><Stat label="Expired" value={trials.filter(x=>x.status==='trial_expired').length} icon={AlertCircle}/><Stat label="Paid" value={trials.filter(x=>x.status==='paid').length} icon={WalletCards}/></div>
      <section className="panel"><div className="admin-filterbar"><div className="searchbar"><Search size={17}/><input placeholder="Search PG organization" aria-label="Search trial organizations" value={trialSearch} onChange={e=>setTrialSearch(e.target.value)}/></div><label>Status<select value={trialFilter} onChange={e=>setTrialFilter(e.target.value)}>{['all','pending','trial_active','trial_expired','paid','suspended'].map(x=><option key={x} value={x}>{x==='all'?'All statuses':x.replaceAll('_',' ')}</option>)}</select></label></div><div className="table-scroll"><table><thead><tr><th>PG organization</th><th>Trial status</th><th>Started</th><th>Expires</th><th>Remaining</th><th>Admin controls</th></tr></thead><tbody>{filteredTrials.map(t=><tr key={t.tenant_id}><td><strong>{t.business_name}</strong><small>PG #{t.tenant_id}</small></td><td><Tag value={t.status}/></td><td>{t.started_at?new Date(t.started_at).toLocaleDateString('en-IN'):'Not started'}</td><td>{t.expires_at?new Date(t.expires_at).toLocaleDateString('en-IN'):'—'}</td><td>{t.status==='trial_active'?`${t.days_remaining} days`:'—'}</td><td><div className="trial-actions">{t.status==='pending'&&<button className="outline small" disabled={trialBusy} onClick={()=>trialAction(t.tenant_id,'activate')}>Activate 15 days</button>}{['trial_active','trial_expired'].includes(t.status)&&<button className="outline small" disabled={trialBusy} onClick={()=>trialAction(t.tenant_id,'extend')}>Extend</button>}{['pending','trial_active','trial_expired'].includes(t.status)&&<button className="outline small" disabled={trialBusy} onClick={()=>trialAction(t.tenant_id,'suspend')}>Suspend</button>}{t.status==='suspended'&&!t.subscription_suspended&&<button className="outline small" disabled={trialBusy} onClick={()=>trialAction(t.tenant_id,'resume')}>Resume</button>}{t.status==='paid'&&<button className="outline small" disabled={trialBusy} onClick={()=>trialAction(t.tenant_id,'end-subscription')}>End subscription</button>}{t.status==='suspended'&&t.subscription_suspended&&<button className="outline small" disabled={trialBusy} onClick={()=>trialAction(t.tenant_id,'resume-subscription')}>Resume paid subscription</button>}</div></td></tr>)}</tbody></table>{!filteredTrials.length&&<Empty text="No matching PG organizations."/>}</div></section>
    </>}
    {tab==='Invoices'&&<><div className="stats">
      <Stat label="Total invoiced" value={money(invoices.reduce((sum,i)=>sum+Number(i.total??i.subtotal??0),0))} icon={ReceiptText}/>
      <Stat label="Recorded paid" value={money(invoices.filter(i=>i.status==='paid').reduce((sum,i)=>sum+Number(i.total??i.subtotal??0),0))} icon={CheckCircle2}/>
      <Stat label="Awaiting verified payment" value={invoices.filter(i=>i.status==='issued').length} icon={WalletCards}/>
      <Stat label="Draft invoices" value={invoices.filter(i=>i.status==='draft').length} icon={ClipboardList}/>
      </div><div className="toolbar"><div><h2>Monthly subscription invoices</h2><p>View amounts owed by PG owners and record only payments that have reached the bank.</p></div></div><section className="panel"><div className="table-scroll"><table><thead><tr><th>Invoice</th><th>Owner</th><th>Month</th><th>Residents</th><th>Owners</th><th>Rate per person</th><th>Subtotal</th><th>GST</th><th>Invoice total</th><th>Status</th><th>Payment action</th></tr></thead><tbody>{invoices.map(i=><tr key={i.id}><td><strong>CI-{String(i.id).padStart(5,'0')}</strong></td><td>{owners.find(o=>o.id===i.tenant_id)?.business_name||`Owner #${i.tenant_id}`}</td><td>{i.period}</td><td>{i.billable_residents}</td><td>{i.billable_owners??'—'}</td><td>{money(i.unit_rate)}</td><td>{money(i.subtotal)}</td><td>{money(i.gst_amount)}</td><td><b>{money(i.total??i.subtotal)}</b></td><td><Tag value={i.status}/></td><td>{i.status==='draft'?<button className="outline small" disabled={loading} onClick={()=>mutate(`/invoices/${i.id}/issue`,'POST',undefined,'Invoice issued')}>Issue</button>:i.status==='issued'?<div className="ref-action"><input aria-label={`Payment reference for invoice ${i.id}`} placeholder="Verified bank UTR" value={paymentRefs[i.id]||''} onChange={e=>setPaymentRefs({...paymentRefs,[i.id]:e.target.value})}/><button className="outline small" disabled={loading||(paymentRefs[i.id]||'').trim().length<4} onClick={()=>{if(window.confirm('Confirm the money was received in IntProSec bank account?'))mutate(`/invoices/${i.id}/confirm-manual-payment`,'POST',{payment_reference:paymentRefs[i.id]},'Payment recorded after manual verification')}}>Record received</button></div>:i.payment_reference?<small>Ref: {i.payment_reference}</small>:'—'}</td></tr>)}</tbody></table>{!invoices.length&&<Empty text="No subscription invoices yet. Generate an invoice from the Subscriptions tab."/>}</div></section></>}
    {tab==='Feature Controls'&&<section className="panel feature-policy">
      <h2>Subscription features</h2>
      <p className="hint">Manage access for organizations with an active paid subscription.</p>
      {featureControls?<div className="feature-grid">{featureControls.map(feature=>{
        const isFree=feature.access==='free';
        const Icon=isFree?BarChart3:feature.key==='expense_csv'?Download:WalletCards;
        return <article className="feature-card" key={feature.key}>
          <div className="feature-card-top"><div className="feature-icon"><Icon size={21} aria-hidden="true"/></div>
            <span className={`feature-plan ${isFree?'feature-plan-free':''}`}>{isFree?'Free':'Paid subscription'}</span></div>
          <h3>{feature.label}</h3>
          <p>{feature.key==='expense_analysis'?'Monthly totals and category breakdowns.':feature.key==='expense_csv'?'Download monthly expenses as a CSV file.':'Live payments require a gateway integration.'}</p>
          <div className="feature-card-footer">
            {isFree?<span className="feature-included"><CheckCircle2 size={16}/> Always included</span>
              :<><div><strong>{feature.enabled?'Enabled':'Disabled'}</strong>
                {!feature.available&&<small>Gateway integration required</small>}</div>
                <button type="button" className="feature-switch" role="switch" aria-checked={feature.enabled}
                  aria-label={`Enable ${feature.label} for paid subscriptions`} disabled={featureBusy}
                  onClick={()=>updateFeature(feature,!feature.enabled)}><span aria-hidden="true"/></button></>}
          </div>
        </article>;
      })}</div>:!error&&<p role="status">Loading feature controls…</p>}
    </section>}
    {tab==='App Feedback'&&<section className="panel">
      <h2>Owner and resident feedback</h2>
      {appFeedback?.items?.length?<div className="table-scroll"><table><thead><tr><th>Role</th><th>Rating</th><th>Comment</th><th>Updated</th></tr></thead>
      <tbody>{appFeedback.items.map(item=><tr key={item.id}><td>{item.role}</td><td>{item.rating}/5</td>
        <td style={{whiteSpace:'pre-wrap',overflowWrap:'anywhere'}}>{item.comment||'—'}</td><td>{new Date(item.updated_at).toLocaleDateString('en-IN')}</td></tr>)}</tbody></table></div>:<p>{appFeedback?'No feedback yet.':'Loading feedback…'}</p>}
      <div className="actions">{[['Previous',appFeedback?.previous_offset],['Next',appFeedback?.next_offset]].map(([label,offset])=>
        offset!=null&&<button key={label} className="outline" onClick={async()=>{try{setAppFeedback(await request('/app-feedback?offset='+offset))}catch(e){fail(e)}}}>{label}</button>)}</div>
    </section>}
    {tab==='Activity'&&<section className="panel"><h2>Administrator activity</h2><p className="hint">Latest recorded administrative changes. Search by action or affected record.</p><div className="searchbar"><Search size={16}/><input aria-label="Filter administrator activity" value={auditSearch} onChange={e=>setAuditSearch(e.target.value)} placeholder="Filter activity by action or object"/></div><div className="table-scroll"><table><thead><tr><th>Time</th><th>Action</th><th>Object</th></tr></thead><tbody>{auditFiltered.map(a=><tr key={a.id}><td>{new Date(a.created_at).toLocaleString('en-IN')}</td><td>{a.action.replaceAll('_',' ')}</td><td>{a.target}</td></tr>)}</tbody></table>{!auditFiltered.length&&<Empty text="No administrative activity matches this filter."/>}</div></section>}
    <footer className="footer"><span>Stay Sync Manage - Platform administration · © 2026</span><span>Access is restricted to authorized IntProSec administrators.</span></footer>
    </main>
  </div>
}

createRoot(document.getElementById('root')).render(<App/>);
