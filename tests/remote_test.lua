package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,failc=0,0
local function check(name,cond,info)
    if cond then pass=pass+1;print("  PASS "..name) else failc=failc+1;print("  FAIL "..name.."  "..tostring(info or "")) end
end
local function tail(S,n)local t={}for i=math.max(1,#S.log-(n or 6)),#S.log do t[#t+1]=S.log[i]end;return table.concat(t," | ")end
local serial=1000
local function remote(S,t,payload)
    S.actions[#S.actions+1]={t=t,fn=function(S) serial=serial+1
        table.insert(S.queue,table.pack("rednet_message",4,{kind="remote",serial=serial,payload=payload},S.protocol)) end}
    table.sort(S.actions,function(a,b) return a.t<b.t end)
end
local function lastWith(S,f) for i=#S.sent,1,-1 do local m=S.sent[i].msg;if type(m)=="table" and f(m) then return m end end end

print("R1 Aushub-Turtle: von Hand fahren, abbauen, Steuerung beenden -> faehrt heim")
local CFG=[[return {role="turtle",job="dig",controllerId=4,name="Grabi",network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},
 dig={shape="room",direction="down",width=3,length=3,height=2,side="right",seal="off",drain=false,keepOres="",useCoal=true,fuelTarget=500,freeSlots=2,radioTimeout=0,protectedBlocks={}}}]]
local S=Sim.new({config=CFG,fuel=4000})
S.protocol="toast.dig.v1"
S.world[S.key(0,0,1)]=false            -- vorne frei
S.world[S.key(0,0,2)]="minecraft:dirt"
remote(S,2,{op="forward"})             -- ohne 'Steuern' -> abgelehnt
remote(S,3,{op="manual_on"})
remote(S,4,{op="forward"})
remote(S,5,{op="dig"})                 -- Erde vorne abbauen
remote(S,6,{op="forward"})
remote(S,7,{op="left"})
remote(S,8,{op="up"})                  -- (Stein darueber -> geht nicht)
local midPos
S.actions[#S.actions+1]={t=8.9,fn=function(S) midPos={x=S.p.x,y=S.p.y,z=S.p.z,dir=S.p.dir} end}
remote(S,9,{op="manual_off"})
table.sort(S.actions,function(a,b) return a.t<b.t end)
Sim.run(S,25)
check("Fahrt + Abbau: auf z=2, nach links gedreht",midPos and midPos.z==2 and midPos.x==0 and midPos.dir==3,midPos and (midPos.x..","..midPos.y..","..midPos.z.." d"..midPos.dir))
check("Erde abgebaut",S.world[S.key(0,0,2)]==false)
local m=lastWith(S,function(m) return m.kind=="status" and m.mMsg and m.mMsg:find("Hoch",1,true) end)
check("'Hoch' geht nicht (Stein) -> Meldung",m and m.mMsg:find("Geht nicht",1,true),m and m.mMsg)
local seen=lastWith(S,function(m) return m.kind=="status" and m.manual==true and m.mFront end)
check("Status zeigt Bloecke + Werkzeug",seen and seen.mFront and seen.mUp and seen.mDown,seen and seen.mFront)
check("nach 'Beenden' wieder an der Basis",S.p.x==0 and S.p.y==0 and S.p.z==0,S.p.x..","..S.p.y..","..S.p.z.." "..tail(S))
local first=nil;for _,x in ipairs(S.sent) do if x.msg.kind=="status" and x.msg.mMsg then first=x.msg.mMsg;break end end
check("Ohne 'Steuern' keine Fahrt",first and first:find("Steuern",1,true),first)

print("R2 Einstellungen abrufen und aendern (Breite 3 -> 5): Turtle startet mit neuer Config")
S=Sim.new({config=CFG,fuel=4000})
S.protocol="toast.dig.v1"
remote(S,2,{op="getconfig"})
remote(S,4,{op="setconfig",values={dig={width=5,keepOres="diamond",bogus=1}}})
remote(S,6,{op="setconfig",values={dig={width=2000}}})
Sim.run(S,12)
local cf=lastWith(S,function(m) return m.kind=="config" end)
local first2;for _,x in ipairs(S.sent) do if x.msg.kind=="config" then first2=x.msg;break end end
local digSec;for _,sec in ipairs(first2 and first2.config.sections or {}) do if sec.name=="dig" then digSec=sec end end
local wf;for _,f in ipairs(digSec and digSec.fields or {}) do if f.k=="width" then wf=f end end
check("Config abgerufen: Abschnitt dig mit Breite 3 + Beschreibung",wf and wf.v==3 and wf.d and #wf.d>3,wf and wf.v)
local shapeF;for _,f in ipairs(digSec and digSec.fields or {}) do if f.k=="shape" then shapeF=f end end
check("Auswahlwerte fuer Form mitgeliefert",shapeF and shapeF.o and #shapeF.o==4)
local newCfg=load(S.files["/toast.config.lua"])()
check("Breite 5 + keepOres gespeichert, Unsinn ignoriert",newCfg.dig.width==5 and newCfg.dig.keepOres=="diamond" and newCfg.dig.bogus==nil,newCfg.dig.width)
check("ungueltiger Wert (2000) abgelehnt mit Meldung",cf and cf.ok==false and tostring(cf.msg):find("1024",1,true),cf and cf.msg)
check("Turtle laeuft nach Neustart weiter (Programm aktiv)",S.result==nil or S.result=="timeout",S.result)

print("R3 Aendern waehrend sie arbeitet: abgelehnt")
S=Sim.new({config=[[return {role="turtle",job="mob",controllerId=4,name="Wache",network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},
 mob={mode="farm",attack="front",nightOnly=false,length=16,width=16,side="right",climb=8,interval=10,fuelTarget=2000,radioTimeout=0}}]],
    fuel=4000,actions={{t=2,fn=function(S) Sim.cmd(S,"start",10) end}}})
S.protocol="toast.mob.v1"
remote(S,2.5,{op="setconfig",values={mob={attack="up"}}})
remote(S,2.6,{op="manual_on"})
Sim.run(S,4)
cf=lastWith(S,function(m) return m.kind=="config" end)
check("Speichern abgelehnt (erst stoppen)",cf and cf.ok==false and tostring(cf.msg):find("stoppen",1,true),cf and cf.msg)
local ms=lastWith(S,function(m) return m.kind=="status" and m.mMsg end)
check("Steuern abgelehnt (erst stoppen)",ms and ms.mMsg:find("stoppen",1,true),ms and ms.mMsg)

print("R4 Mining-Turtle: fahren ohne Abbau (Block im Weg -> Meldung), Positionszaehlung stimmt")
local MCFG=[[return {role="auto",job="mining",controllerId=4,label="Test",autoDiscover=true,autoPairPockets=true,
    devices={},pocketIds={},display={monitor="auto",textScale=0.5,pageSize=0},
    network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},
    farm={width=3,length=3,crop="wheat",interval=5,seedReserve=16,radioTimeout=10,water={}},
    mine={length=6,height=3,tunnels=1,gap=1,fuelTarget=200,radioTimeout=0,freeSlots=2,digRetries=16,protectedBlocks={}}}]]
S=Sim.new({config=MCFG,fuel=4000})
S.protocol="toast.mine.v1"
S.world[S.key(0,0,1)]=false
remote(S,2,{op="manual_on"});remote(S,3,{op="forward"});remote(S,4,{op="forward"})
local p4
S.actions[#S.actions+1]={t=4.9,fn=function(S) p4={x=S.p.x,z=S.p.z} end}
remote(S,5,{op="digUp"})
remote(S,6,{op="manual_off"})
table.sort(S.actions,function(a,b) return a.t<b.t end)
Sim.run(S,20)
check("ein Feld vor, zweites blockiert (kein Abbau beim Fahren)",p4 and p4.z==1,p4 and p4.z)
local bl=lastWith(S,function(m) return m.kind=="status" and m.mMsg and m.mMsg:find("Vor",1,true) end)
check("Meldung 'Geht nicht: Vor'",bl and bl.mMsg:find("Geht nicht",1,true),bl and bl.mMsg)
check("oben abgebaut",S.world[S.key(0,-1,1)]==false)
check("wieder an der Basis",S.p.x==0 and S.p.y==0 and S.p.z==0,S.p.x..","..S.p.y..","..S.p.z.." "..tail(S))
print("R5 Oberflaeche: Reiter Steuern/Einstellungen auf Pocket und Zentrale")
do
    local S3=Sim.new({config=""});local G=Sim.env(S3)
    for _,n in ipairs({"toast_common.lua","toast_model.lua","toast_ui.lua"}) do S3.files["/toast/"..n]=io.open("/home/claude/toast/"..n):read("a") end
    do local n=0;local c={};G.colors=setmetatable({},{__index=function(_,k)if not c[k] then n=n+1;c[k]=2^n end;return c[k] end}) end
    G.os.getComputerID=function() return 4 end;G.turtle=nil
    G.textutils.formatTime=function()return "9:15" end;G.os.time=function()return 9 end
    local sent={};G.rednet.send=function(id,msg,p) sent[#sent+1]={id=id,msg=msg,p=p};return true end
    G.rednet.broadcast=function() end
    local common=G.dofile("/toast/toast_common.lua")
    local cfg=common.load({role="controller",controllerId=4})
    local model=G.dofile("/toast/toast_model.lua").new(cfg)
    local UI=G.dofile("/toast/toast_ui.lua")
    local function screen(W,H)
        local rows={};for y=1,H do rows[y]=string.rep(" ",W) end;local cx,cy=1,1
        return {getSize=function()return W,H end,isColor=function()return true end,setBackgroundColor=function()end,setTextColor=function()end,
            clear=function()for y=1,H do rows[y]=string.rep(" ",W) end end,setCursorPos=function(x,y)cx,cy=x,y end,setCursorBlink=function()end,
            write=function(t)if cy<1 or cy>H then return end;t=tostring(t):gsub("[\128-\255]","="):gsub("[\1-\31]","*");local r=rows[cy];rows[cy]=(r:sub(1,cx-1)..t..r:sub(cx+#t)):sub(1,W);cx=cx+#t end,
            text=function() return table.concat(rows,"\n") end}
    end
    model.ingest(12,{kind="status",version=2,id=12,status="Bereit",mode="off",ack=0,controllerId=4,label="Grabi",manual=true,
        mFront="minecraft:stone",mUp="Luft",mDown="minecraft:dirt",mLeft="minecraft:diamond_pickaxe",mRight="modem",mMsg="Vor"},"toast.dig.v1")
    local conf={job="dig",name="Grabi",jobs=common.JOBS,sections={{name="dig",title="Aushub",fields={
        {k="shape",d="Form",v="room",o={"room","cylinder","sphere","dome"}},{k="width",d="Breite",v=3},{k="drain",d="Trockenlegen",v=false},{k="keepOres",d="Erze stehen lassen",v=""}}}}}
    check("Config-Antwort angenommen",model.turtleConfig(12,{kind="config",id=12,config=conf},"toast.dig.v1"))
    for _,size in ipairs({{26,20,"Pocket"},{39,19,"Zentrale"}}) do
        local sc=screen(size[1],size[2]);local ui=UI.new(sc,cfg)
        ui.action("id:12")
        local r=ui.action("dv:drive");ui.draw(model.fleet(),true,"")
        local t=sc.text()
        if size[3]=="Pocket" then print(t) end
        check(size[3]..": Steuern-Reiter mit Steuerkreuz",t:find("Fernsteuerung AN",1,true) and t:find("Vor",1,true) and t:find("Abbau",1,true) and t:find("Hoch",1,true) and t:find("Runter",1,true),t)
        local fwd;for _,b in ipairs(ui.buttons) do if b.action=="rc:forward" then fwd=b end end
        local cmd=fwd and ui.action(ui.click(fwd.x,fwd.y))
        check(size[3]..": 'Vor' tippen -> Befehl an Turtle 12",type(cmd)=="table" and cmd.id==12 and cmd.payload.op=="forward")
        cmd=ui.action("dv:config")
        check(size[3]..": Einstellungen oeffnen fragt Config an",type(cmd)=="table" and cmd.payload.op=="getconfig")
        ui.draw(model.fleet(),true,"");t=sc.text()
        check(size[3]..": Einstellungen sichtbar",t:find("Breite",1,true) and t:find("Form",1,true),t)
        -- Breite auswaehlen und +1
        local sel;for _,b in ipairs(ui.buttons) do if type(b.action)=="string" and b.action:match("^cf:sel:") then
            local l=ui.cfgLinesCache[tonumber(b.action:sub(8))];if l and l.k=="width" then sel=b end end end
        ui.action(ui.click(sel.x,sel.y));ui.action("cf:add:1");ui.action("cf:add:1")
        -- Form weiterschalten
        for i,l in ipairs(ui.cfgLinesCache) do if l.k=="shape" then ui.cfgSel=i end end
        ui.action("cf:opt:1")
        -- Text per Tastatur
        for i,l in ipairs(ui.cfgLinesCache) do if l.k=="keepOres" then ui.cfgSel=i end end
        ui.draw(model.fleet(),true,"")
        check(size[3]..": Textfeld nimmt Tastatur",ui.textInput()==true)
        for ch in ("diamond"):gmatch(".") do ui.action(ui.char(ch)) end
        ui.draw(model.fleet(),true,"");t=sc.text()
        check(size[3]..": geaenderte Werte sichtbar",t:find("5",1,true) and t:find("cylinder",1,true) and t:find("Speichern",1,true),t)
        cmd=ui.action("cf:save")
        check(size[3]..": Speichern schickt nur Aenderungen",type(cmd)=="table" and cmd.payload.op=="setconfig" and cmd.payload.values.dig.width==5
            and cmd.payload.values.dig.shape=="cylinder" and cmd.payload.values.dig.keepOres=="diamond" and cmd.payload.values.dig.drain==nil)
    end
    -- Zentrale leitet weiter
    sent={}
    check("remoteCmd an Turtle",model.remoteCmd(12,{op="forward"}))
    local got;for _,m in ipairs(sent) do if m.id==12 and m.msg.kind=="remote" and m.msg.payload.op=="forward" then got=true end end
    check("Befehl gesendet (Protokoll Aushub)",got)
    model.remote(30,{kind="hello",role="pocket",version=1,controllerId=4,info={role="pocket",name="P"}},common.remoteProtocol)
    -- vorigen Befehl bestaetigen, sonst steht der naechste in der Warteschlange
    model.ingest(12,{kind="status",version=2,id=12,status="Bereit",ack=model.pending[12].message.serial,controllerId=4},"toast.dig.v1")
    sent={}
    model.remote(30,{kind="remote",version=1,controllerId=4,target=12,payload={op="left"},serial=99999999999999},common.remoteProtocol)
    got=nil;for _,m in ipairs(sent) do if m.id==12 and m.msg.kind=="remote" and m.msg.payload.op=="left" then got=true end end
    check("Pocket -> Zentrale -> Turtle",got)
    sent={}
    model.turtleConfig(12,{kind="config",id=12,config=conf,ok=true,msg="Gespeichert"},"toast.dig.v1")
    got=nil;for _,m in ipairs(sent) do if m.id==30 and m.msg.kind=="turtleconfig" then got=true end end
    check("Config-Antwort geht an Pockets",got)
end
print("R6 Mine mit Chunkloader: nach 'Abbauen' wieder Modem -> naechster Befehl kommt an")
S=Sim.new({config=MCFG:gsub("network=","chunkload={enabled=true,chunks=1,reportEvery=10},network="),fuel=4000,
    gear={left="ccchunkloader:chunkloader",right="minecraft:diamond_pickaxe"}})
S.inv[16]={name="computercraft:wireless_modem_advanced",count=1}
S.protocol="toast.mine.v1"
S.world[S.key(0,0,1)]="minecraft:dirt"
remote(S,2,{op="manual_on"});remote(S,3,{op="dig"});remote(S,4,{op="forward"})
local p6
S.actions[#S.actions+1]={t=5.5,fn=function(S) p6={z=S.p.z,right=S.equip.right} end}
table.sort(S.actions,function(a,b) return a.t<b.t end)
Sim.run(S,7)
check("Erde abgebaut (Werkzeug angelegt)",S.world[S.key(0,0,1)]==false)
check("danach wieder Modem dran + 'Vor' ausgefuehrt",p6 and p6.z==1 and tostring(p6.right):find("modem",1,true),p6 and (p6.z.." "..tostring(p6.right)))
print("R7 Farm-Turtle: nur waagrecht, Einstellungen abrufen")
S=Sim.new({config=MCFG:gsub('job="mining"','job="farm"'),default=false,fuel=4000})
S.protocol="toast.farm.v2"
remote(S,2,{op="manual_on"});remote(S,3,{op="forward"});remote(S,4,{op="up"});remote(S,5,{op="getconfig"})
local p7
S.actions[#S.actions+1]={t=5.5,fn=function(S) p7={z=S.p.z,y=S.p.y} end}
remote(S,6,{op="manual_off"})
table.sort(S.actions,function(a,b) return a.t<b.t end)
Sim.run(S,15)
check("ein Feld vor, nicht hoch",p7 and p7.z==1 and p7.y==0,p7 and (p7.z..","..p7.y))
local up7=lastWith(S,function(m) return m.kind=="status" and m.mMsg and m.mMsg:find("Hoch",1,true) end)
check("Hoch: 'nur waagrecht'",up7 and up7.mMsg:find("waagrecht",1,true),up7 and up7.mMsg)
local c7=lastWith(S,function(m) return m.kind=="config" end)
local farmSec;for _,sec in ipairs(c7 and c7.config.sections or {}) do if sec.name=="farm" then farmSec=sec end end
check("Farm-Einstellungen geliefert",farmSec and #farmSec.fields>3)
check("wieder zu Hause",S.p.x==0 and S.p.z==0,S.p.x..","..S.p.z.." "..tail(S))
print("R8 Mine (alte Config mit role=auto): Ganglaenge per Funk aendern, Rest bleibt")
S=Sim.new({config=MCFG,fuel=4000})
S.protocol="toast.mine.v1"
remote(S,2,{op="setconfig",values={mine={length=8}}})
Sim.run(S,6)
local okc8,c8=pcall(load(S.files["/toast.config.lua"]))
check("Config gueltig, Mine-Laenge 8, Aufgabe Mine, Hoehe unveraendert",okc8 and c8 and c8.job=="mining" and c8.mine and c8.mine.length==8 and c8.mine.height==3,
    okc8 and c8 and c8.mine and c8.mine.length or tostring(c8))
print("R9 Leertaste-Logik + Warteschlange")
do
    -- Aushub-Turtle (Spitzhacke): Leertaste baut ab, ohne Block greift sie an
    S=Sim.new({config=CFG,fuel=4000})
    S.protocol="toast.dig.v1"
    S.world[S.key(0,0,1)]="minecraft:dirt"
    remote(S,2,{op="manual_on"});remote(S,3,{op="use"});remote(S,4,{op="use"});remote(S,5,{op="useUp"})
    Sim.run(S,7)
    check("Leertaste: Erde vorne abgebaut",S.world[S.key(0,0,1)]==false)
    local u=lastWith(S,function(m) return m.kind=="status" and m.mMsg and m.mMsg:find("vorne",1,true) end)
    check("zweimal Leertaste ohne Block: Meldung 'nichts da'",u and u.mMsg:find("nichts da",1,true),u and u.mMsg)
    check("oben (Stein) abgebaut",S.world[S.key(0,-1,0)]==false)
    -- Zentrale: 3 schnelle Befehle -> nacheinander
    local S3=Sim.new({config=""});local G=Sim.env(S3)
    for _,n in ipairs({"toast_common.lua","toast_model.lua"}) do S3.files["/toast/"..n]=io.open("/home/claude/toast/"..n):read("a") end
    G.os.getComputerID=function() return 4 end;G.turtle=nil
    local sent={};G.rednet.send=function(id,msg,p) sent[#sent+1]={id=id,msg=msg,p=p};return true end
    G.rednet.broadcast=function() end
    local common=G.dofile("/toast/toast_common.lua")
    local model=G.dofile("/toast/toast_model.lua").new(common.load({role="controller",controllerId=4}))
    model.ingest(12,{kind="status",version=2,id=12,status="Bereit",ack=0,controllerId=4},"toast.dig.v1")
    model.remoteCmd(12,{op="forward"});model.remoteCmd(12,{op="forward"});model.remoteCmd(12,{op="left"})
    local ops={};for _,m in ipairs(sent) do if m.msg.kind=="remote" then ops[#ops+1]=m.msg.payload.op end end
    check("erst nur der erste Befehl unterwegs",#ops==1 and ops[1]=="forward",table.concat(ops,","))
    local s1=model.pending[12].message.serial
    model.ingest(12,{kind="status",version=2,id=12,status="Bereit",ack=s1,controllerId=4},"toast.dig.v1")
    local s2=model.pending[12] and model.pending[12].message
    check("nach Bestaetigung kommt der zweite",s2 and s2.payload.op=="forward" and s2.serial>s1)
    model.ingest(12,{kind="status",version=2,id=12,status="Bereit",ack=s2.serial,controllerId=4},"toast.dig.v1")
    check("dann der dritte (links)",model.pending[12] and model.pending[12].message.payload.op=="left")
end
print(pass.." bestanden, "..failc.." fehlgeschlagen")
if failc>0 then os.exit(1) end
