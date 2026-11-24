-- Owner-local layout/settings transactions. No cross-mod userdata or config.json.
local M={version=1};local owner
local function copy(v)
  if type(v)~='table' then return v end
  local t={};for k,x in pairs(v) do t[k]=copy(x) end;return t
end
local function same(a,b)
  if type(a)~=type(b) then return false end
  if type(a)~='table' then return a==b end
  for k,v in pairs(a) do if not same(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end;return true
end
function M.active()return owner and owner.session~=nil or false end
function M.read(key,base)if owner then return owner.get(key) end;return base.get(key) end
function M.new(base,schema,hooks)
  assert(not owner,'Only one config adapter per owning VM')
  local A={schema=schema,hooks=hooks or {},revision=0,serial=0};owner=A
  local bykey={};for _,f in ipairs(schema) do bykey[f.key]=f end
  local function valid(key,value)
    local f=bykey[key];if not f then return false end
    if f.type=='bool' then return type(value)=='boolean' end
    return type(value)=='number' and value==value and value%1==0 and value>=f.min and value<=f.max
  end
  local function saved()
    local bucket=storage.account.xiv_ui_player_v1
    return type(bucket)=='table' and type(bucket.values)=='table' and bucket.values or {}
  end
  local function native_value(key)
    local f=bykey[key]
    local v=A.hooks.base and A.hooks.base(key)
    if v==nil then v=base.get(key) end
    if v==nil and f then v=f.default end
    return v
  end
  local function bases()
    local result={};for _,f in ipairs(schema) do result[f.key]=native_value(f.key) end;return result
  end
  function A.get(key)
    if not bykey[key] then return base.get(key) end
    if key == 'on' then
      if A.session and A.session.preview then return true end
      return native_value('on')
    end
    local values=A.session and A.session.draft or saved()
    if valid(key,values[key]) then return values[key] end
    return native_value(key) -- one native accessor, not a full-schema scan per HUD field.
  end
  A.settings={get=A.get}
  function A.info()
    local values={};local native=bases();local draft=A.session and A.session.draft or saved()
    for _,f in ipairs(schema) do
      if valid(f.key,draft[f.key]) then values[f.key]=draft[f.key] else values[f.key]=native[f.key] end
    end
    return {version=1,revision=A.revision,fields=copy(schema),values=values,
      defaults=native,preview_supported=A.hooks.preview~=nil,preview=A.session and A.session.preview or false,editing=A.session~=nil}
  end
  function A.cancel(token)
    local s=A.session
    if not s or s.token~=token then return {ok=false,reason='Expired/stale editor'} end
    A.session=nil
    if A.hooks.restore then A.hooks.restore(copy(s.state)) end
    return {ok=true}
  end
  function A.begin()
    if A.session then return {ok=false,reason='Owner already has an editor'} end
    if A.hooks.busy and A.hooks.busy() then return {ok=false,reason='Close this component editor first'} end
    A.serial=A.serial+1
    local token=tostring(A.serial)..':'..tostring(A.revision)
    A.session={token=token,draft=copy(saved()),before=copy(saved()),bases=bases(),
      raw=copy(storage.account.xiv_ui_player_v1),state=A.hooks.capture and A.hooks.capture() or {},at=clock(),preview=false}
    return {ok=true,token=token,info=A.info()}
  end
  function A.check(token)
    local s=A.session
    if not s or s.token~=token then return {ok=false,reason='Expired/stale editor'} end
    if not same(s.raw,storage.account.xiv_ui_player_v1) or not same(s.bases,bases()) then return {ok=false,reason='Owner settings changed; cancel/reopen, preserving external changes'} end
    return {ok=true}
  end
  function A.set(token,key,value)
    if not A.session or A.session.token~=token then return {ok=false,reason='Expired/stale editor'} end
    if not valid(key,value) then return {ok=false,reason='Unknown key or out-of-range value'} end
    A.session.draft[key]=value;A.session.at=clock();return {ok=true,info=A.info()}
  end
  function A.preview(token,on)
    if not A.session or A.session.token~=token then return {ok=false,reason='Expired/stale editor'} end
    if type(on)~='boolean' or not A.hooks.preview then return {ok=false,reason='Safe sample not supported'} end
    A.session.preview=on;A.session.at=clock()
    if on then A.hooks.preview(true) elseif A.hooks.restore then A.hooks.restore(copy(A.session.state)) end
    return {ok=true}
  end
  function A.defaults(token)
    if not A.session or A.session.token~=token then return {ok=false,reason='Expired/stale editor'} end
    for key in pairs(bykey) do A.session.draft[key]=nil end
    return {ok=true,info=A.info()}
  end
  function A.commit(token)
    local result=A.check(token);if not result.ok then return result end
    local s=A.session
    if storage.account.xiv_ui_player_v1~=nil and type(storage.account.xiv_ui_player_v1)~='table' then return {ok=false,reason='Unrecognised owner config; preserving it'} end
    if type(storage.account.xiv_ui_player_v1)=='table' and storage.account.xiv_ui_player_v1.version~=nil and storage.account.xiv_ui_player_v1.version~=1 then
      return {ok=false,reason='Unrecognised owner config version; preserving it'}
    end
    local draft=copy(s.draft);draft.on=nil
    local bucket=copy(storage.account.xiv_ui_player_v1 or {});bucket.version=1;bucket.values=draft
    local old=copy(storage.account.xiv_ui_player_v1);storage.account.xiv_ui_player_v1=bucket
    local ok=pcall(storage.save)
    if not ok then storage.account.xiv_ui_player_v1=old;return {ok=false,reason='Owner save failed; draft retained'} end
    A.revision=A.revision+1
    A.rollback={revision=A.revision,before=old,after=copy(bucket)}
    A.cancel(token);return {ok=true,receipt={revision=A.revision}}
  end
  function A.undo(receipt)
    local rollback=A.rollback
    if type(receipt)~='table' or not rollback or receipt.revision~=A.revision or rollback.revision~=receipt.revision or not same(storage.account.xiv_ui_player_v1,rollback.after) then
      return {ok=false,reason='Rollback conflict; preserving newer owner edit'}
    end
    local current=copy(storage.account.xiv_ui_player_v1);storage.account.xiv_ui_player_v1=copy(rollback.before)
    if not pcall(storage.save) then storage.account.xiv_ui_player_v1=current;return {ok=false,reason='Rollback save failed'} end
    A.revision=A.revision+1;A.rollback=nil;return {ok=true}
  end
  mods.provide('xiv_config',function(op,...)
    if op=='info' then return A.info() end
    if op=='renew' then local token=...;if A.session and A.session.token==token then A.session.at=clock();return {ok=true} end;return {ok=false} end
    if op=='begin' or op=='set' or op=='preview' or op=='check' or op=='commit' or op=='cancel' or op=='defaults' or op=='undo' then return A[op](...) end
    return {ok=false,reason='Unsupported config operation'}
  end)
  timer.every(0.25,function()if A.session and clock()-A.session.at>2 then A.cancel(A.session.token) end end)
  for _,event in ipairs({'zone_change','logout','unload'}) do events.on(event,function()if A.session then A.cancel(A.session.token) end end) end
  return A
end
return M
