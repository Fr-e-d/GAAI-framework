export function getBookingWidgetStyles(): string {
  return `.bw-container { max-height:0; overflow:hidden; transition:max-height 0.3s ease; border-top:1px solid #e5e7eb; margin-top:0.5rem; }
.bw-container--open { max-height:2000px; }
.bw-inner { padding:1.5rem 0; }
.bw-header { display:flex; justify-content:space-between; align-items:center; margin-bottom:1.25rem; }
.bw-title { font-weight:700; font-size:1rem; color:#1a1a2e; }
.bw-close-btn { background:none; border:none; cursor:pointer; color:#6b7280; font-size:1.25rem; padding:0.25rem; min-width:44px; min-height:44px; display:flex; align-items:center; justify-content:center; }
.bw-close-btn:hover { color:#1a1a2e; }
.bw-tz-label { font-size:0.8125rem; color:#6b7280; margin-bottom:1rem; }
@keyframes bw-shimmer { 0%{background-position:-468px 0} 100%{background-position:468px 0} }
.bw-skeleton-row { display:flex; gap:0.5rem; margin-bottom:0.5rem; flex-wrap:wrap; }
.bw-skeleton-day { width:38px; height:38px; border-radius:0.375rem; background:linear-gradient(to right,#f0f0f0 8%,#e0e0e0 18%,#f0f0f0 33%); background-size:800px 104px; animation:bw-shimmer 1.2s linear infinite; }
.bw-cal-grid { display:grid; grid-template-columns:repeat(7,1fr); gap:0.375rem; margin-bottom:1.25rem; }
.bw-cal-header { display:grid; grid-template-columns:repeat(7,1fr); gap:0.375rem; margin-bottom:0.5rem; }
.bw-cal-header-cell { text-align:center; font-size:0.75rem; color:#6b7280; font-weight:600; padding:0.25rem 0; }
.bw-cal-day { min-height:38px; min-width:38px; border:1.5px solid #e5e7eb; border-radius:0.375rem; background:#fff; cursor:default; font-size:0.875rem; display:flex; align-items:center; justify-content:center; }
.bw-cal-day--available { border-color:var(--color-primary,#4F46E5); color:var(--color-primary,#4F46E5); cursor:pointer; font-weight:600; }
.bw-cal-day--available:hover { background:var(--color-primary,#4F46E5); color:#fff; }
.bw-cal-day--unavailable { color:#d1d5db; background:#f9fafb; }
.bw-cal-day--selected { background:var(--color-primary,#4F46E5); color:#fff; border-color:var(--color-primary,#4F46E5); }
.bw-cal-day--empty { border:none; background:transparent; }
.bw-slots-heading { font-size:0.875rem; font-weight:600; color:#1a1a2e; margin-bottom:0.75rem; }
.bw-slots-grid { display:flex; flex-wrap:wrap; gap:0.5rem; margin-bottom:1.25rem; }
.bw-slot-chip { padding:0.5rem 0.875rem; border:1.5px solid #e5e7eb; border-radius:999px; background:#fff; font-size:0.875rem; cursor:pointer; min-height:44px; min-width:60px; display:flex; align-items:center; justify-content:center; }
.bw-slot-chip:hover { border-color:var(--color-primary,#4F46E5); color:var(--color-primary,#4F46E5); }
.bw-slot-chip--selected { background:var(--color-primary,#4F46E5); color:#fff; border-color:var(--color-primary,#4F46E5); }
.bw-no-slots { color:#6b7280; font-size:0.875rem; margin-bottom:1rem; }
.bw-back-btn { background:none; border:none; color:var(--color-primary,#4F46E5); font-size:0.875rem; cursor:pointer; padding:0; text-decoration:underline; margin-bottom:1rem; display:block; }
.bw-countdown { font-size:0.875rem; font-weight:600; color:#d97706; background:#fef3c7; padding:0.375rem 0.75rem; border-radius:0.375rem; display:inline-block; margin-bottom:1.25rem; }
.bw-label { display:block; font-size:0.875rem; font-weight:600; color:#374151; margin-bottom:0.25rem; margin-top:0.75rem; }
.bw-input { display:block; width:100%; padding:0.625rem 0.75rem; border:1.5px solid #d1d5db; border-radius:var(--radius-card,0.375rem); font-size:0.9375rem; font-family:var(--font-family,'Inter, sans-serif'); color:#1a1a2e; background:#fff; }
.bw-input:focus { outline:none; border-color:var(--color-primary,#4F46E5); }
.bw-input:read-only { background:#f3f4f6; color:#6b7280; }
.bw-textarea { display:block; width:100%; padding:0.625rem 0.75rem; border:1.5px solid #d1d5db; border-radius:var(--radius-card,0.375rem); font-size:0.9375rem; font-family:var(--font-family,'Inter, sans-serif'); color:#1a1a2e; background:#fff; resize:vertical; min-height:80px; }
.bw-textarea:focus { outline:none; border-color:var(--color-primary,#4F46E5); }
.bw-field-error { color:#dc2626; font-size:0.8125rem; margin-top:0.25rem; }
.bw-confirm-btn { display:block; width:100%; padding:0.75rem 1rem; background:var(--color-primary,#4F46E5); color:#fff; border:none; border-radius:var(--radius-card,0.5rem); font-size:0.9375rem; font-weight:600; font-family:var(--font-family,'Inter, sans-serif'); cursor:pointer; margin-top:1.25rem; min-height:44px; }
.bw-confirm-btn:hover:not(:disabled) { opacity:0.9; }
.bw-confirm-btn:disabled { opacity:0.5; cursor:not-allowed; }
.bw-confirm-error { color:#dc2626; font-size:0.875rem; margin-top:0.75rem; background:#fef2f2; border-left:3px solid #dc2626; border-radius:0.25rem; padding:0.5rem 0.75rem; }
.bw-retry-btn { background:none; border:none; color:#dc2626; font-size:0.875rem; cursor:pointer; text-decoration:underline; padding:0; margin-top:0.25rem; display:block; }
.bw-step-success { text-align:center; padding:1.5rem 0; }
.bw-success-check { font-size:2.5rem; margin-bottom:0.75rem; }
.bw-success-title { font-size:1.125rem; font-weight:700; color:#059669; margin-bottom:1rem; }
.bw-success-detail { font-size:0.9375rem; color:#374151; margin-bottom:0.5rem; }
.bw-success-meet { display:inline-block; margin-top:0.75rem; margin-bottom:0.75rem; padding:0.625rem 1.25rem; background:#059669; color:#fff; border-radius:var(--radius-card,0.5rem); text-decoration:none; font-weight:600; font-size:0.9375rem; }
.bw-success-email-note { font-size:0.875rem; color:#6b7280; margin-top:0.5rem; }
.bw-success-prep { display:block; margin-top:0.75rem; font-size:0.875rem; color:var(--color-primary,#4F46E5); }
.bw-resend-btn { background:none; border:1.5px solid var(--color-primary,#4F46E5); color:var(--color-primary,#4F46E5); font-size:0.875rem; cursor:pointer; padding:0.5rem 1rem; border-radius:var(--radius-card,0.375rem); font-family:var(--font-family,'Inter, sans-serif'); margin-top:0.5rem; min-height:44px; }
.bw-resend-btn:hover:not(:disabled) { background:var(--color-primary,#4F46E5); color:#fff; }
.bw-resend-btn:disabled { opacity:0.5; cursor:not-allowed; }
.bw-step-expired { text-align:center; padding:1.5rem 0; }
.bw-expired-title { font-size:1rem; font-weight:600; color:#dc2626; margin-bottom:0.75rem; }
.bw-reselect-btn { padding:0.625rem 1.25rem; background:var(--color-primary,#4F46E5); color:#fff; border:none; border-radius:var(--radius-card,0.5rem); cursor:pointer; font-weight:600; font-family:var(--font-family,'Inter, sans-serif'); min-height:44px; }
.bw-gcal-fallback { color:#6b7280; font-size:0.875rem; padding:1rem 0; }
.bw-inline-error { color:#dc2626; font-size:0.875rem; margin-bottom:0.75rem; background:#fef2f2; border-left:3px solid #dc2626; border-radius:0.25rem; padding:0.5rem 0.75rem; }
@media (max-width:480px) {
  .bw-cal-grid { grid-template-columns:repeat(7,1fr); overflow-x:auto; display:flex; flex-wrap:nowrap; }
  .bw-cal-header { display:flex; flex-wrap:nowrap; overflow-x:auto; }
  .bw-cal-header-cell { min-width:38px; }
  .bw-cal-day { min-width:38px; flex-shrink:0; }
  .bw-confirm-btn { font-size:1rem; }
}
@keyframes bw-spin { from{transform:rotate(0deg)} to{transform:rotate(360deg)} }
.bw-spinner { width:16px; height:16px; border:2px solid rgba(255,255,255,0.4); border-top-color:#fff; border-radius:50%; animation:bw-spin 0.7s linear infinite; flex-shrink:0; display:inline-block; }`;
}

export function getBookingWidgetScript(): string {
  return `<script>(function(){
  var STATE='IDLE';
  var currentExpertId='';
  var currentExpertName='';
  var currentSlots=[];
  var slotsByDate={};
  var selectedDate='';
  var selectedSlot=null;
  var bookingId='';
  var heldUntil=null;
  var countdownInterval=null;
  var containerEl=null;
  var triggerBtn=null;

  if(!window.__SAT__)return;
  var apiUrl=window.__SAT__.apiUrl;
  var satelliteId=window.__SAT__.satelliteId;

  window.addEventListener('booking-open',function(e){
    var detail=e.detail||{};
    var expertId=detail.expertId||'';
    var expertName=detail.expertName||'';
    if(!expertId)return;
    if(STATE!=='IDLE'&&currentExpertId===expertId){
      closeWidget();
      return;
    }
    if(STATE!=='IDLE'){
      closeWidget();
    }
    openWidget(expertId,expertName);
  });

  function openWidget(expertId,expertName){
    currentExpertId=expertId;
    currentExpertName=expertName;
    STATE='DATE_STEP';
    var btn=document.querySelector('.booking-btn[data-expert-id="'+escHtml(expertId)+'"]');
    triggerBtn=btn;
    var card=btn?btn.closest('.match-card'):null;
    if(!card){
      card=document.body;
    }
    containerEl=document.createElement('div');
    containerEl.className='bw-container';
    containerEl.setAttribute('role','region');
    containerEl.setAttribute('aria-label','R\u00e9servation avec '+escHtml(expertName));
    card.appendChild(containerEl);
    requestAnimationFrame(function(){containerEl.classList.add('bw-container--open');});
    containerEl.setAttribute('tabindex','-1');
    setTimeout(function(){if(containerEl)containerEl.focus();},350);
    firePostHog('satellite.booking_widget_opened',{satellite_id:satelliteId,expert_id:expertId,source:'match_results'});
    fetchAvailability();
  }

  function closeWidget(){
    clearCountdown();
    if(containerEl){
      containerEl.classList.remove('bw-container--open');
      setTimeout(function(){
        if(containerEl&&containerEl.parentNode){containerEl.parentNode.removeChild(containerEl);}
        containerEl=null;
      },350);
    }
    if(triggerBtn)triggerBtn.focus();
    triggerBtn=null;
    STATE='IDLE';
    currentExpertId='';
    currentExpertName='';
    currentSlots=[];
    slotsByDate={};
    selectedDate='';
    selectedSlot=null;
    bookingId='';
    heldUntil=null;
  }

  function fetchAvailability(){
    if(!containerEl)return;
    var tz=Intl.DateTimeFormat().resolvedOptions().timeZone||'UTC';
    containerEl.innerHTML='<div class="bw-inner">'+buildHeaderHTML(currentExpertName)+buildSkeletonHTML()+'</div>';
    wireCancelBtn();
    fetch(apiUrl+'/api/experts/'+encodeURIComponent(currentExpertId)+'/availability?tz='+encodeURIComponent(tz))
    .then(function(res){
      if(res.status===422){
        return res.json().then(function(d){
          if(d&&d.error==='gcal_not_connected'){handleGcalNotConnected();return null;}
          throw{status:422};
        });
      }
      if(!res.ok){throw{status:res.status};}
      return res.json();
    })
    .then(function(data){
      if(!data)return;
      currentSlots=data.slots||[];
      slotsByDate=buildSlotsByDate(currentSlots);
      renderDateStep();
    })
    .catch(function(){
      if(!containerEl)return;
      renderInlineError('Impossible de charger les disponibilit\u00e9s.',fetchAvailability);
    });
  }

  function buildSlotsByDate(slots){
    var map={};
    var tz=Intl.DateTimeFormat().resolvedOptions().timeZone||'UTC';
    slots.forEach(function(utcStr){
      var d=new Date(utcStr);
      var dateKey=formatLocalDate(d,tz);
      if(!map[dateKey])map[dateKey]=[];
      map[dateKey].push(utcStr);
    });
    return map;
  }

  function renderDateStep(){
    if(!containerEl)return;
    STATE='DATE_STEP';
    var tz=Intl.DateTimeFormat().resolvedOptions().timeZone||'UTC';
    var today=new Date();
    var days=[];
    for(var i=0;i<14;i++){
      var d=new Date(today);
      d.setDate(today.getDate()+i);
      days.push(d);
    }
    var dayNames=['Dim','Lun','Mar','Mer','Jeu','Ven','Sam'];
    var headerCells='';
    for(var h=0;h<7;h++){headerCells+='<div class="bw-cal-header-cell">'+escHtml(dayNames[h])+'</div>';}
    var firstDow=days[0].getDay();
    var calCells='';
    for(var off=0;off<firstDow;off++){calCells+='<div class="bw-cal-day bw-cal-day--empty" aria-hidden="true"></div>';}
    days.forEach(function(d){
      var dateKey=formatLocalDate(d,tz);
      var hasSlots=slotsByDate[dateKey]&&slotsByDate[dateKey].length>0;
      var cls='bw-cal-day '+(hasSlots?'bw-cal-day--available':'bw-cal-day--unavailable');
      var ariaLabel=formatDayAriaLabel(d)+(hasSlots?'':' \u2014 indisponible');
      var dayNum=d.getDate();
      if(hasSlots){
        calCells+='<button class="'+cls+'" data-date="'+escHtml(dateKey)+'" aria-label="'+escHtml(ariaLabel)+'">'+dayNum+'</button>';
      }else{
        calCells+='<div class="'+cls+'" aria-label="'+escHtml(ariaLabel)+'" aria-disabled="true">'+dayNum+'</div>';
      }
    });
    var tzName=tz.replace(/_/g,' ');
    var html='<div class="bw-inner">'
      +buildHeaderHTML(currentExpertName)
      +'<div class="bw-tz-label">Horaires en '+escHtml(tzName)+'</div>'
      +'<div class="bw-cal-header">'+headerCells+'</div>'
      +'<div class="bw-cal-grid" role="grid" aria-label="Calendrier de disponibilit\u00e9s">'+calCells+'</div>'
      +'</div>';
    containerEl.innerHTML=html;
    wireCancelBtn();
    containerEl.querySelectorAll('.bw-cal-day--available').forEach(function(btn){
      btn.addEventListener('click',function(){
        var dateKey=btn.getAttribute('data-date')||'';
        handleDateSelect(dateKey);
      });
    });
  }

  function handleDateSelect(dateKey){
    selectedDate=dateKey;
    firePostHog('satellite.booking_date_selected',{satellite_id:satelliteId,expert_id:currentExpertId,date:dateKey});
    renderSlotStep();
  }

  function renderSlotStep(){
    if(!containerEl)return;
    STATE='SLOT_STEP';
    var slots=slotsByDate[selectedDate]||[];
    var tz=Intl.DateTimeFormat().resolvedOptions().timeZone||'UTC';
    var slotsHtml='';
    if(slots.length===0){
      slotsHtml='<p class="bw-no-slots">Aucun cr\u00e9neau disponible pour cette date.</p>';
    }else{
      slots.forEach(function(utcStr){
        var d=new Date(utcStr);
        var label=formatTimeLabel(d,tz);
        slotsHtml+='<button class="bw-slot-chip" data-slot="'+escHtml(utcStr)+'" aria-label="'+escHtml(label)+'">'+escHtml(label)+'</button>';
      });
    }
    var d0=new Date(selectedDate+'T12:00:00');
    var heading=formatHumanDate(d0);
    var html='<div class="bw-inner">'
      +buildHeaderHTML(currentExpertName)
      +'<button class="bw-back-btn" type="button">\u2190 Changer de date</button>'
      +'<div class="bw-slots-heading">Cr\u00e9neaux disponibles \u2014 '+escHtml(heading)+'</div>'
      +'<div class="bw-slots-grid" role="list" aria-label="Cr\u00e9neaux disponibles">'+slotsHtml+'</div>'
      +'</div>';
    containerEl.innerHTML=html;
    wireCancelBtn();
    containerEl.querySelector('.bw-back-btn').addEventListener('click',function(){renderDateStep();});
    containerEl.querySelectorAll('.bw-slot-chip').forEach(function(btn){
      btn.addEventListener('click',function(){
        var slotStr=btn.getAttribute('data-slot')||'';
        firePostHog('satellite.booking_slot_selected',{satellite_id:satelliteId,expert_id:currentExpertId,slot_start:slotStr});
        holdSlot(slotStr);
      });
    });
  }

  function holdSlot(slotStart){
    var tz=Intl.DateTimeFormat().resolvedOptions().timeZone||'UTC';
    var start=new Date(slotStart);
    var end=new Date(start.getTime()+20*60*1000);
    var prospectId=null;
    try{prospectId=sessionStorage.getItem('match:prospect_id');}catch(e){}
    var token=null;
    try{token=sessionStorage.getItem('match:token');}catch(e){}
    selectedSlot={start_at:start.toISOString(),end_at:end.toISOString()};
    if(containerEl){
      var chip=containerEl.querySelector('.bw-slot-chip[data-slot="'+CSS.escape(slotStart)+'"]');
      if(chip){chip.disabled=true;chip.innerHTML='<span class="bw-spinner"></span>';}
    }
    fetch(apiUrl+'/api/bookings/hold',{
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({expert_id:currentExpertId,start_at:selectedSlot.start_at,end_at:selectedSlot.end_at,prospect_id:prospectId,token:token})
    })
    .then(function(res){
      if(res.status===409){
        return res.json().then(function(d){
          if(d&&d.error==='max_holds_reached'){
            if(containerEl){
              var err=document.createElement('p');
              err.className='bw-inline-error';
              err.textContent='Vous avez trop de r\u00e9servations en attente. Finalisez ou annulez une r\u00e9servation existante.';
              var inner=containerEl.querySelector('.bw-inner');
              if(inner)inner.insertBefore(err,inner.firstChild);
            }
          }else{
            currentSlots=currentSlots.filter(function(s){return s!==slotStart;});
            slotsByDate=buildSlotsByDate(currentSlots);
            renderSlotStep();
            showToast('Ce cr\u00e9neau vient d\'être r\u00e9serv\u00e9. Choisissez un autre horaire.');
          }
          return null;
        });
      }
      if(!res.ok){throw{status:res.status};}
      return res.json();
    })
    .then(function(data){
      if(!data)return;
      bookingId=data.booking_id||data.id||'';
      heldUntil=data.held_until;
      firePostHog('satellite.booking_held',{satellite_id:satelliteId,expert_id:currentExpertId,booking_id:bookingId});
      renderHoldStep();
    })
    .catch(function(){
      if(!containerEl)return;
      renderInlineError('Impossible de r\u00e9server ce cr\u00e9neau.',function(){holdSlot(slotStart);});
    });
  }

  function renderHoldStep(){
    if(!containerEl)return;
    STATE='HOLD_STEP';
    var identifiedEmail='';
    try{identifiedEmail=sessionStorage.getItem('match:identified_email')||'';}catch(e){}
    var emailReadonly=identifiedEmail?'readonly':''
    var html='<div class="bw-inner">'
      +buildHeaderHTML(currentExpertName)
      +'<div class="bw-countdown" role="status" aria-live="polite" id="bw-countdown-display">Cr\u00e9neau r\u00e9serv\u00e9 pendant --:--</div>'
      +'<div class="bw-form">'
      +'<label class="bw-label" for="bw-name">Votre nom *</label>'
      +'<input class="bw-input" id="bw-name" type="text" placeholder="Pr\u00e9nom Nom" autocomplete="name" required>'
      +'<div class="bw-field-error" id="bw-name-error" role="alert" style="display:none"></div>'
      +'<label class="bw-label" for="bw-email">Votre email *</label>'
      +'<input class="bw-input" id="bw-email" type="email" placeholder="votre@email.com" autocomplete="email" required value="'+escHtml(identifiedEmail)+'" '+emailReadonly+'>'
      +'<div class="bw-field-error" id="bw-email-error" role="alert" style="display:none"></div>'
      +'<label class="bw-label" for="bw-desc">D\u00e9crivez bri\u00e8vement votre besoin <span style="color:#6b7280">(optionnel)</span></label>'
      +'<textarea class="bw-textarea" id="bw-desc" maxlength="500" placeholder="D\u00e9crivez bri\u00e8vement votre besoin..."></textarea>'
      +'<button class="bw-confirm-btn" id="bw-confirm-btn" type="button">Confirmer la r\u00e9servation</button>'
      +'<div class="bw-confirm-error" id="bw-confirm-error" role="alert" style="display:none"></div>'
      +'</div>'
      +'</div>';
    containerEl.innerHTML=html;
    wireCancelBtn();
    startCountdown();
    document.getElementById('bw-confirm-btn').addEventListener('click',handleConfirm);
    var nameInput=document.getElementById('bw-name');
    if(nameInput)nameInput.focus();
  }

  function startCountdown(){
    clearCountdown();
    if(!heldUntil)return;
    var expiresAt=new Date(heldUntil).getTime();
    countdownInterval=setInterval(function(){
      var now=Date.now();
      var remaining=Math.max(0,Math.floor((expiresAt-now)/1000));
      var mm=Math.floor(remaining/60);
      var ss=remaining%60;
      var display=(mm<10?'0'+mm:mm)+':'+(ss<10?'0'+ss:ss);
      var el=document.getElementById('bw-countdown-display');
      if(el)el.textContent='Cr\u00e9neau r\u00e9serv\u00e9 pendant '+display;
      if(remaining<=0){
        clearCountdown();
        handleHoldExpired();
      }
    },1000);
  }

  function clearCountdown(){
    if(countdownInterval){clearInterval(countdownInterval);countdownInterval=null;}
  }

  function handleHoldExpired(){
    firePostHog('satellite.booking_hold_expired',{satellite_id:satelliteId,expert_id:currentExpertId,booking_id:bookingId});
    if(!containerEl)return;
    STATE='EXPIRED';
    var html='<div class="bw-inner">'
      +buildHeaderHTML(currentExpertName)
      +'<div class="bw-step-expired">'
      +'<div class="bw-expired-title">Le cr\u00e9neau a expir\u00e9.</div>'
      +'<button class="bw-reselect-btn" id="bw-reselect-btn" type="button">Choisir un nouveau cr\u00e9neau</button>'
      +'</div>'
      +'</div>';
    containerEl.innerHTML=html;
    wireCancelBtn();
    document.getElementById('bw-reselect-btn').addEventListener('click',function(){
      fetchAvailability();
    });
  }

  function handleConfirm(){
    var nameInput=document.getElementById('bw-name');
    var emailInput=document.getElementById('bw-email');
    var descInput=document.getElementById('bw-desc');
    var confirmBtn=document.getElementById('bw-confirm-btn');
    var name=(nameInput?nameInput.value.trim():'');
    var email=(emailInput?emailInput.value.trim():'');
    var desc=(descInput?descInput.value.trim():'');
    showFieldError('bw-name','');
    showFieldError('bw-email','');
    var valid=true;
    if(!name){showFieldError('bw-name','Le nom est requis.');valid=false;}
    if(!email||!/^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$/.test(email)){showFieldError('bw-email','Email invalide.');valid=false;}
    if(!valid)return;
    if(confirmBtn){confirmBtn.disabled=true;confirmBtn.innerHTML='<span class="bw-spinner"></span> Confirmation...';}
    var errorEl=document.getElementById('bw-confirm-error');
    if(errorEl)errorEl.style.display='none';
    fetch(apiUrl+'/api/bookings/'+encodeURIComponent(bookingId)+'/confirm',{
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({prospect_name:name,prospect_email:email,description:desc})
    })
    .then(function(res){
      if(res.status===409){
        return res.json().then(function(){
          clearCountdown();
          fetchAvailability();
          return null;
        });
      }
      if(res.status===410){
        clearCountdown();
        handleHoldExpired();
        return null;
      }
      if(res.status===422){
        return res.json().then(function(d){
          if(confirmBtn){confirmBtn.disabled=false;confirmBtn.textContent='Confirmer la r\u00e9servation';}
          if(d&&d.details){
            d.details.forEach(function(issue){
              if(issue.path&&issue.path[0]==='prospect_name')showFieldError('bw-name',issue.message||'Invalide.');
              if(issue.path&&issue.path[0]==='prospect_email')showFieldError('bw-email',issue.message||'Email invalide.');
            });
          }else{
            showConfirmError('Donn\u00e9es invalides.',false);
          }
          return null;
        });
      }
      if(res.status===502){
        if(confirmBtn){confirmBtn.disabled=false;confirmBtn.textContent='Confirmer la r\u00e9servation';}
        showConfirmError('Erreur de connexion au calendrier. Veuillez r\u00e9essayer dans quelques instants.',true);
        return null;
      }
      if(!res.ok){
        if(confirmBtn){confirmBtn.disabled=false;confirmBtn.textContent='Confirmer la r\u00e9servation';}
        showConfirmError('Une erreur est survenue. Veuillez r\u00e9essayer.',true);
        return null;
      }
      return res.json();
    })
    .then(function(data){
      if(!data)return;
      clearCountdown();
      firePostHog('satellite.booking_confirmed',{satellite_id:satelliteId,expert_id:currentExpertId,booking_id:bookingId});
      if(data.booking_id)bookingId=data.booking_id;
      renderPendingConfirmation(data.confirmation_sent_to||email);
    })
    .catch(function(){
      if(confirmBtn){confirmBtn.disabled=false;confirmBtn.textContent='Confirmer la r\u00e9servation';}
      showConfirmError('Une erreur r\u00e9seau est survenue. V\u00e9rifiez votre connexion et r\u00e9essayez.',true);
    });
  }

  function renderPendingConfirmation(email){
    if(!containerEl)return;
    STATE='SUCCESS';
    var countdown=60;
    var html='<div class="bw-inner">'
      +'<div class="bw-step-success">'
      +'<div class="bw-success-check">\u2709</div>'
      +'<div class="bw-success-title">V\u00e9rifiez votre email</div>'
      +'<p class="bw-success-detail">Un email de confirmation a \u00e9t\u00e9 envoy\u00e9 \u00e0 <strong>'+escHtml(email)+'</strong>.</p>'
      +'<p class="bw-success-detail">Cliquez sur le lien dans l\'email pour finaliser votre r\u00e9servation.</p>'
      +'<div id="bw-resend-container">'
      +'<p class="bw-success-email-note" id="bw-countdown-msg">Renvoyer l\'email dans <span id="bw-countdown-sec">'+countdown+'</span>s</p>'
      +'</div>'
      +'</div>'
      +'</div>';
    containerEl.innerHTML=html;
    containerEl.setAttribute('aria-label','Email de confirmation envoy\u00e9');

    var resendInterval=setInterval(function(){
      countdown--;
      var secEl=document.getElementById('bw-countdown-sec');
      var msgEl=document.getElementById('bw-countdown-msg');
      if(secEl)secEl.textContent=String(countdown);
      if(countdown<=0){
        clearInterval(resendInterval);
        if(msgEl){
          msgEl.innerHTML='<button class="bw-resend-btn" id="bw-resend-btn">Renvoyer l\'email</button>';
          var btn=document.getElementById('bw-resend-btn');
          if(btn){
            btn.addEventListener('click',function(){
              btn.disabled=true;
              btn.textContent='Envoi...';
              var resendUrl=apiUrl+'/api/bookings/'+encodeURIComponent(bookingId)+'/confirmation/resend';
              fetch(resendUrl,{
                method:'POST',
                headers:{'Content-Type':'application/json'}
              }).then(function(r){
                if(r.ok){
                  btn.textContent='Email renvoy\u00e9 !';
                  btn.disabled=true;
                }else{
                  btn.textContent='Erreur, r\u00e9essayez';
                  btn.disabled=false;
                }
              }).catch(function(){
                btn.textContent='Erreur, r\u00e9essayez';
                btn.disabled=false;
              });
            });
          }
        }
      }
    },1000);
  }

  function handleGcalNotConnected(){
    if(!containerEl)return;
    containerEl.innerHTML='<div class="bw-inner">'
      +buildHeaderHTML(currentExpertName)
      +'<div class="bw-gcal-fallback">Cet expert n\'a pas encore configur\u00e9 son calendrier. <a href="/contact">Contactez-nous</a></div>'
      +'</div>';
    wireCancelBtn();
    firePostHog('satellite.booking_error',{satellite_id:satelliteId,expert_id:currentExpertId,error_type:'gcal_not_connected'});
  }

  function renderInlineError(msg,retryFn){
    if(!containerEl)return;
    var inner=containerEl.querySelector('.bw-inner');
    if(!inner){containerEl.innerHTML='<div class="bw-inner"></div>';inner=containerEl.querySelector('.bw-inner');}
    var id='bw-err-'+Date.now();
    var errHtml='<div class="bw-inline-error" id="'+id+'">'+escHtml(msg)+(retryFn?'<br><button class="bw-retry-btn" type="button">R\u00e9essayer</button>':'')+'</div>';
    inner.innerHTML=errHtml;
    if(retryFn){
      var btn=document.getElementById(id);
      if(btn){
        var retryBtnEl=btn.querySelector('.bw-retry-btn');
        if(retryBtnEl)retryBtnEl.addEventListener('click',retryFn);
      }
    }
  }

  function showFieldError(inputId,msg){
    var errEl=document.getElementById(inputId+'-error');
    if(!errEl)return;
    errEl.textContent=msg;
    errEl.style.display=msg?'':'none';
    var inputEl=document.getElementById(inputId);
    if(inputEl)inputEl.setAttribute('aria-describedby',msg?inputId+'-error':'');
  }

  function showConfirmError(msg,showRetry){
    var errorEl=document.getElementById('bw-confirm-error');
    if(!errorEl)return;
    errorEl.textContent=msg;
    errorEl.style.display='block';
    firePostHog('satellite.booking_error',{satellite_id:satelliteId,expert_id:currentExpertId,error_type:'confirm_error'});
  }

  function showToast(msg){
    var toast=document.createElement('div');
    toast.style.cssText='position:fixed;bottom:1.5rem;right:1.5rem;background:#1a1a2e;color:#fff;padding:0.75rem 1.25rem;border-radius:0.5rem;font-size:0.875rem;z-index:9999;max-width:320px;';
    toast.textContent=msg;
    document.body.appendChild(toast);
    setTimeout(function(){if(toast.parentNode)toast.parentNode.removeChild(toast);},4000);
  }

  function buildHeaderHTML(expertName){
    return '<div class="bw-header">'
      +'<div class="bw-title">R\u00e9server un appel \u2014 '+escHtml(expertName)+'</div>'
      +'<button class="bw-close-btn" id="bw-close-btn" type="button" aria-label="Fermer le widget de r\u00e9servation">\u00d7</button>'
      +'</div>';
  }

  function buildSkeletonHTML(){
    var row='<div class="bw-skeleton-row">';
    for(var i=0;i<7;i++)row+='<div class="bw-skeleton-day"></div>';
    row+='</div>';
    return row+row;
  }

  function wireCancelBtn(){
    var btn=document.getElementById('bw-close-btn');
    if(btn){btn.addEventListener('click',closeWidget);}
  }

  function formatLocalDate(d,tz){
    try{
      var parts=new Intl.DateTimeFormat('fr-CA',{timeZone:tz,year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(d);
      var yr='',mo='',dy='';
      parts.forEach(function(p){if(p.type==='year')yr=p.value;if(p.type==='month')mo=p.value;if(p.type==='day')dy=p.value;});
      return yr+'-'+mo+'-'+dy;
    }catch(e){return d.toISOString().substring(0,10);}
  }

  function formatTimeLabel(d,tz){
    try{
      return new Intl.DateTimeFormat('fr-FR',{timeZone:tz,hour:'2-digit',minute:'2-digit',hour12:false}).format(d);
    }catch(e){
      var hh=d.getHours();var mm=d.getMinutes();
      return (hh<10?'0'+hh:hh)+':'+(mm<10?'0'+mm:mm);
    }
  }

  function formatDayAriaLabel(d){
    try{
      return new Intl.DateTimeFormat('fr-FR',{weekday:'long',day:'numeric',month:'long'}).format(d);
    }catch(e){return String(d.getDate());}
  }

  function formatHumanDate(d){
    try{
      return new Intl.DateTimeFormat('fr-FR',{weekday:'long',day:'numeric',month:'long'}).format(d);
    }catch(e){return String(d.getDate());}
  }

  function formatSlotLabel(d,tz){
    try{
      var dateStr=new Intl.DateTimeFormat('fr-FR',{timeZone:tz,weekday:'long',day:'numeric',month:'long'}).format(d);
      var timeStr=new Intl.DateTimeFormat('fr-FR',{timeZone:tz,hour:'2-digit',minute:'2-digit',hour12:false}).format(d);
      return dateStr+' \u00e0 '+timeStr;
    }catch(e){return d.toISOString();}
  }

  function firePostHog(event,props){
    if(typeof posthog!=='undefined')posthog.capture(event,props);
  }

  function escHtml(str){
    if(!str)return'';
    return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
  }
})();<\/script>`;
}
