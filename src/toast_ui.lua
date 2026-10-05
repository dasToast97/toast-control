-- Toast Control: Oberflaeche fuer Zentrale (Monitor) und Pocket.
-- Passt sich der Bildschirmgroesse an: Liste aller Turtles mit Farbe je Zustand,
-- Antippen zeigt Details. Farm und Mining zeigen jeweils nur ihre eigenen Werte.
local common=dofile("/toast/toast_common.lua")
local M={}
-- Zustand -> Kurztext + Farbe
local WORK={["Abbau"]="Baut ab",["Ernte"]="Erntet",["Pflanzen"]="Pflanzt",["Feld pruefen"]="Prueft",
    ["Fortsetzen"]="Startet",["Neuer Versuch"]="Startet",["Faellt Baum"]="Faellt",["Baeume pruefen"]="Prueft",
    ["Kampf"]="Kaempft",["Patrouille"]="Laeuft",["Sucht Baeume"]="Sucht",["Graebt"]="Graebt",
    ["Update"]="Update",["Kiste setzen"]="Kiste"}
-- Nur echte Probleme orange; alles andere ist normale Arbeit
local WARN={"fehlt","voll","blockiert","fehlgeschlagen","unklar","Kein","beendet","Gelaende","Problem","nicht"}
-- Nachschub fehlt (Lager voll, Treibstoff, Saatgut ...): kein Fehler, nur Pause
local PAUSE={"voll","Treibstoff","Fuel","Kohle","Saatgut","Fuellmaterial","Wandblock","Ausgabekiste","Lager fehlt","Baumaterial","Stufen fehlen","Falltueren fehlen","Wassereimer","Materialkiste"}
local function isPause(t)
    t=tostring(t or "")
    for _,k in ipairs(PAUSE) do if t:find(k,1,true) then return true end end
    return false
end
M.isPause=isPause
function M.state(e,link)
    local d=e and e.data
    if not link or not e or not e.online or not d then return "Offline","off" end
    if d.recovery then return "Pos. ?","fault" end
    if d.fault and isPause(d.fault) then return "Pause","pause" end
    if d.fault or d.status=="Rueckweg blockiert" then return "Fehler","fault" end
    if isPause(d.status) then return "Pause","pause" end
    local s=tostring(d.status or "")
    if WORK[s] then return WORK[s],"work" end
    if s=="Rueckkehr" then return "Heimweg","move" end
    if s=="Warten" then return "Wartet","wait" end
    if s=="Wache" then return "Wacht","wait" end
    if s=="Tagpause" then return "Tagpause","wait" end
    if s=="Fertig" then return "Fertig","done" end
    if s=="Bereit" or s=="Reset" or s=="" then return "Bereit","idle" end
    for _,k in ipairs(WARN) do if s:find(k,1,true) then return "Problem","warn" end end
    return (s:match("^(%S+)") or s):sub(1,8),"work"
end
local COLOR={work=colors.lime,move=colors.lightBlue,wait=colors.cyan,done=colors.green,
    idle=colors.lightGray,warn=colors.orange,fault=colors.red,off=colors.gray,pause=colors.orange}
M.COLOR=COLOR
local function num(n) return common.number(n) end
local function short(n)
    n=num(n)
    if math.abs(n)>=1000000 then return string.format("%.1fM",n/1000000) end
    if math.abs(n)>=10000 then return string.format("%.1fk",n/1000) end
    return tostring(math.floor(n))
end
-- Spielzeit "11:08" (leer, wenn nicht verfuegbar)
local function clockText()
    if not (textutils and textutils.formatTime and os.time) then return "" end
    local ok,t=pcall(function() return textutils.formatTime(os.time(),true) end)
    t=ok and tostring(t) or ""
    if #t==4 then t="0"..t end
    return t
end
M.clockText=clockText
-- Rechte Kopfzeile: laengste Variante, die in "room" Zeichen passt
local function headRight(room,online,total,clock)
    local opts={online.."/"..total.." online  "..clock.." ",online.."/"..total.." online "..clock.." ",
        online.."/"..total.."  "..clock.." ",online.."/"..total.." "..clock.." ",clock.." ",online.."/"..total.." "}
    if clock=="" then opts={online.."/"..total.." online ",online.."/"..total.." "} end
    for _,o in ipairs(opts) do if #o<=room then return o end end
    return ""
end
M.headRight=headRight
-- ===== Aufgaben: Name, Hauptwert und Detailzeilen je Job =====
local MOB_MODES={farm="Mobfarm",guard="Wache",patrol="Waechter"}
local function wait(rows,d) if num(d.wait)>0 then rows[#rows+1]={"Naechste",num(d.wait).." s"} end end
local JOB={
    farm={name="Farm",plural="Farmen",metric="Ertrag",unit="Items",once="1 Runde",
        value=function(d) return num(d.total) end,aux={"Geerntet",function(d) return num(d.harvested) end," Pfl."},
        rows=function(d) local r={{"Runden",short(d.rounds)}}
            if num(d.roundYield)>0 then r[#r+1]={"Diese Runde",short(d.roundYield).." Items"} end
            r[#r+1]={"Geerntet",short(d.harvested).." Pflanzen"};r[#r+1]={"Ertrag",short(d.total).." Items"}
            if num(d.seedsGained)>0 then r[#r+1]={" davon Samen",short(d.seedsGained)} end
            if not d.cane then r[#r+1]={"Saatgut",short(d.seeds)} end
            if d.pause then r[#r+1]={"Pause",(num(d.pause)>=120 and (math.floor(num(d.pause)/60+0.5).." min") or (num(d.pause).." s"))}
                if d.lastRipe then r[#r+1]={"Zuletzt reif",d.lastRipe.."%"} end end
            wait(r,d);return r end},
    mining={name="Mine",plural="Minen",metric="Abgebaut",unit="Bl.",once="1 Gang",
        value=function(d) return num(d.harvested) end,aux={"Abgeladen",function(d) return num(d.total) end," Items"},
        rows=function(d)
            -- Seitlich mitabbauen: Spuren (alle Ebenen) statt Gaenge zaehlen
            local total=num(d.lanes)>0 and d.lanes or d.tunnels
            local pct=num(d.cells)>0 and (" ("..math.floor(math.min(1,num(d.scanned)/num(d.cells))*100).."%)") or ""
            local r={{num(d.lanes)>0 and "Spuren" or "Gaenge",short(math.min(num(d.rounds),num(total)>0 and num(total) or num(d.rounds)))..(total and (" / "..total) or "").." fertig"..pct},
            {"Abgebaut",short(d.harvested).." Bloecke"},{"Abgeladen",short(d.total).." Items"},{"Freie Slots",short(d.freeSlots)}}
            if d.useCoal then r[#r+1]={"Kohle",short(d.coal).." verbrannt"} end
            if d.placeChests then r[#r+1]={"Kisten",short(d.chestsPlaced).." gesetzt, "..short(d.chestsLeft).." dabei"} end

            if num(d.torches)>0 then r[#r+1]={"Fackeln",short(d.torchesPlaced).." gesetzt, "..short(d.torchesLeft).." dabei"} end
            if num(d.keptOres)>0 then r[#r+1]={"Erze stehen",short(d.keptOres)..(num(d.oresMined)>0 and (", "..short(d.oresMined).." am Rand abgebaut") or "")} end
            if num(d.sealed)>0 then r[#r+1]={"Zugebaut",short(d.sealed).." Stellen"} end
            if num(d.drained)>0 then r[#r+1]={"Trockengelegt",short(d.drained)} end
            if d.noFill then r[#r+1]={"Fuellmaterial","FEHLT (Bruchstein)"} end
            return r end},
    tree={name="Holz",plural="Holzfarmen",metric="Holz",unit="Staemme",once="1 Runde",
        value=function(d) return num(d.total) end,aux={"Gefaellt",function(d) return num(d.harvested) end," Baeume"},
        rows=function(d) local r={{"Runden",short(d.rounds)},{"Gefaellt",short(d.harvested).." Baeume"},
            {"Holz",short(d.total).." Staemme"},{"Setzlinge",short(d.saplings)},{"Freie Slots",short(d.freeSlots)}}
            wait(r,d);return r end},
    mob={name="Mobs",plural="Mob-Turtles",metric="Drops",unit="Items",once="EINMAL",
        value=function(d) return num(d.total) end,aux={"Treffer",function(d) return num(d.hits) end,""},
        rows=function(d) local r={{"Art",MOB_MODES[d.mobMode] or "-"},{"Treffer",short(d.hits)},{"Drops",short(d.total).." abgeliefert"}}
            if num(d.carried)>0 then r[#r+1]={"Dabei",short(d.carried).." Items"} end
            if num(d.looted)>0 then r[#r+1]={"Aufgesammelt",short(d.looted).."x"} end
            if d.lastHit and num(d.hits)>0 then r[#r+1]={"Letzter Mob","vor "..short(d.lastHit).." s"} end
            if d.mobMode=="patrol" then r[#r+1]={"Ziele",short(d.targets).." angefahren"};r[#r+1]={"Tankrunden",short(d.rounds)};wait(r,d) end
            r[#r+1]={"Freie Slots",short(d.freeSlots)};return r end},
    build={name="Mobfarm-Bau",plural="Mobfarm-Bauer",metric="Verbaut",unit="Bl.",once="Bauen",
        value=function(d) return num(d.placed) end,aux={"Fortschritt",function(d) return num(d.cells)>0 and math.floor(num(d.scanned)/num(d.cells)*100) or 0 end,"%"},
        rows=function(d) local r={{"Farm",short(d.floors).." Etage(n), Schacht "..short(d.drop)..(d.creeperOnly and ", Creeper" or "")},
            {"Abschnitt",(d.done and "FERTIG" or tostring(d.phase or "-"))},
            {"Fortschritt",short(d.scanned).." / "..short(d.cells)},{"Verbaut",short(d.placed).." Bloecke"},
            {"Dabei",short(d.fill).." Stein, "..short(d.slabs).." Stufen"}}
            if d.creeperOnly then r[#r+1]={"Falltueren",d.trapFail and "gehen nicht (ohne weiter)" or (short(d.traps).." dabei")} end
            r[#r+1]={"Wassereimer",short(d.buckets).." dabei"}
            if d.missing then r[#r+1]={"Fehlt",tostring(d.missing)} end
            r[#r+1]={"Gesamt",short(d.need).." Stein, "..short(d.needSlab).." Stufen"}
            return r end},
    dig={name="Aushub",plural="Aushub-Turtles",metric="Abgebaut",unit="Bl.",once="1 Auftrag",
        value=function(d) return num(d.harvested) end,aux={"Abgeladen",function(d) return num(d.total) end," Items"},
        rows=function(d) local r={{"Form",(common.DIG_SHAPES[d.shape] or "-")..(d.digDir=="up" and " hoch" or " runter")},
            {"Fortschritt",short(d.scanned).." / "..short(d.cells)..(d.done and " FERTIG" or "")},
            {"Abgebaut",short(d.harvested).." Bloecke"},{"Abgeladen",short(d.total).." Items"}}
            if num(d.kept)>0 then r[#r+1]={"Erze stehen",short(d.kept)} end
            if num(d.sealed)>0 then r[#r+1]={"Zugebaut",short(d.sealed).." Stellen"} end
            if num(d.drained)>0 then r[#r+1]={"Trockengelegt",short(d.drained)} end
            if d.wallBlock then
                r[#r+1]={"Wandblock",(d.noWall and "FEHLT " or short(d.wall).." ")..tostring(d.wallBlock):gsub("^minecraft:","")}
                if num(d.lined)>0 then r[#r+1]={"Verkleidet",short(d.lined).." Bloecke"} end
            end
            r[#r+1]={"Fuellmaterial",d.noFill and "FEHLT" or short(d.fill)}
            r[#r+1]={"Freie Slots",short(d.freeSlots)};return r end},
}
local ORDER={"farm","mining","tree","mob","dig","build"}
M.JOB=JOB
local function jobOf(e) return JOB[e and e.job] and e.job or "mining" end
local function hasProgress(d) return num(d.cells)>0 end
local function progress(d) return math.max(0,math.min(1,num(d.scanned)/math.max(1,num(d.cells)))) end
-- Position: "12 vor, 3 rechts, 5 hoch" ab Basis + Koordinaten (GPS oder aus Basis)
local function posText(d)
    local r=d.rel;if type(r)~="table" then return nil end
    local p={}
    local function part(v,plus,minus) v=num(v);if v~=0 then p[#p+1]=math.abs(v).." "..(v>0 and plus or minus) end end
    part(r.fwd,"vor","zur.");part(r.right,"re","li");part(r.up,"hoch","tief")
    return #p==0 and "an der Basis" or table.concat(p," ")
end
M.posText=posText
local function coordText(d)
    local c=type(d.gps)=="table" and d.gps or type(d.pos)=="table" and d.pos
    if not c then return nil end
    return "X"..num(c.x).." Y"..num(c.y).." Z"..num(c.z)..(type(d.gps)=="table" and " GPS" or "")
end
M.coordText=coordText
local function common_rows(rows,d)
    local pt=posText(d);if pt then rows[#rows+1]={"Position",pt} end
    local ct=coordText(d);if ct then rows[#rows+1]={"Koordinaten",ct} end
    if d.toast then rows[#rows+1]={"Version",tostring(d.toast)..(d.toast~=common.version and (" (Zentrale "..common.version..")") or "")} end
    if d.dim then
        local names={overworld="Oberwelt",nether="Nether",["end"]="End"}
        local t=names[d.dim] or tostring(d.dim)
        if d.dimSet and d.dimSet~=d.dim then t=t.." (Config: "..(names[d.dimSet] or d.dimSet)..")" end
        rows[#rows+1]={"Dimension",t}
    end
    rows[#rows+1]={"Fuel",d.fuel=="unlimited" and "unbegrenzt" or short(d.fuel)}
    if d.chunks then rows[#rows+1]={"Chunks",d.chunks>0 and (d.chunks..", -"..short(d.chunkFuel).." Fuel/h") or "aus"} end
    return rows
end
-- Dunkler Balken-Hintergrund: "braun" wird umdefiniert (sonst nirgends benutzt),
-- weil CC kein dunkleres Grau als colors.gray kennt.
local TRACK=colors.brown
M.TRACK=TRACK
local function setTrack(screen)
    if screen.isColor and screen.isColor() and screen.setPaletteColour then
        pcall(screen.setPaletteColour,TRACK,0x262626)
    end
end
M.setTrack=setTrack
function M.resetTrack(screen)
    if screen and screen.setPaletteColour and term.nativePaletteColour then
        pcall(function() screen.setPaletteColour(TRACK,term.nativePaletteColour(TRACK)) end)
    end
end
-- Balken in einer Listenzeile: obere 2/3 der Zeile gefuellt (Zeichen 143),
-- unten bleibt ein Spalt -> untereinander stehende Balken beruehren sich nicht.
local function thinBar(text,x,y,width,pc,fg,bg)
    local f=math.floor(width*math.max(0,math.min(1,pc))+0.5)
    text(x,y,string.rep("\143",f),fg or colors.lime,bg or colors.black)
    text(x+f,y,string.rep("\143",width-f),TRACK,bg or colors.black)
end
-- Zeichenhilfen fuer einen Bildschirm (Farbe nur, wenn der Bildschirm sie kann)
local function painter(screen)
    local w,h=screen.getSize()
    local color=screen.isColor and screen.isColor()
    local P={w=w,h=h}
    setTrack(screen)
    local function col(c)
        if color then return c end
        if c==TRACK then return colors.gray end
        if c==colors.black or c==colors.gray or c==colors.lightGray or c==colors.white then return c end
        return colors.white
    end
    function P.fill(y,bg) if y<1 or y>h then return end screen.setCursorPos(1,y);screen.setBackgroundColor(col(bg));screen.write(string.rep(" ",w)) end
    function P.text(x,y,s,fg,bg)
        if x<1 or x>w or y<1 or y>h then return end
        s=tostring(s):sub(1,w-x+1)
        screen.setCursorPos(x,y);screen.setTextColor(col(fg or colors.white));screen.setBackgroundColor(col(bg or colors.black))
        screen.write(s)
    end
    function P.right(y,s,fg,bg,margin) s=tostring(s);P.text(math.max(1,w-#s+1-(margin or 0)),y,s,fg,bg) end
    function P.bar(x,y,width,pc,fg)
        local f=math.floor(width*math.max(0,math.min(1,pc))+0.5)
        P.text(x,y,string.rep(" ",f),colors.white,fg or colors.lime)
        P.text(x+f,y,string.rep(" ",width-f),colors.white,TRACK)
    end
    function P.thin(x,y,width,pc,fg) thinBar(P.text,x,y,width,pc,fg) end
    return P
end
-- ===== Infoscreen: nur Anzeige, keine Knoepfe =====
-- st = Zustandstabelle des Infoscreens (Seite, Verlauf fuer "pro Stunde")
-- Infoscreen fuer genau eine Turtle: grosse Detailseite
local function drawTurtleInfo(screen,fleet,link,st,id)
    local P=painter(screen);local w,h=P.w,P.h
    screen.setBackgroundColor(colors.black);screen.clear()
    local e=(fleet.entries or {})[id]
    local d=e and e.data or {}
    local label,kind=M.state(e,link)
    local name=e and e.label~="" and e.label or ("Turtle #"..id)
    P.fill(1,colors.blue)
    local clock=clockText()
    local tag=(e and JOB[jobOf(e)].name or "").." #"..id
    local rt=tag.."  "..clock.." "
    if #name+#rt+2>w then rt=clock~="" and (clock.." ") or (tag.." ") end
    if #name+#rt+2>w then name=name:sub(1,math.max(1,w-#rt-2)) end
    P.text(2,1,name,colors.white,colors.blue)
    P.right(1,rt,colors.white,colors.blue)
    if not e then
        P.text(1,3,"Turtle #"..id.." ist der Zentrale",colors.orange)
        P.text(1,4,"(noch) nicht bekannt.",colors.orange)
        P.text(1,6,"ID in toast.lua config pruefen.",colors.lightGray)
        return
    end
    -- Zustand als grosses Band
    P.fill(3,COLOR[kind]);P.fill(4,COLOR[kind])
    P.text(2,3,label,colors.black,COLOR[kind])
    local why=(kind=="fault" or kind=="warn" or kind=="pause") and (d.fault or d.status) or nil
    if why then P.text(2,4,tostring(why),colors.black,COLOR[kind]) end
    local det=kind=="off" and "Keine Meldung: Chunk entladen? An der Turtle: toast.lua config -> Chunks -> An der Basis wach = j (oder /forceload)" or tostring(d.detail or "")
    local y=6
    while #det>0 and y<=7 do P.text(1,y,det:sub(1,w),colors.lightGray);det=det:sub(w+1);y=y+1 end
    -- Fortschritt (nicht bei Mobfarm/Wache: dort gibt es keine Runde)
    y=9
    if hasProgress(d) then
        local pc=progress(d)
        P.text(1,y,"Fortschritt",colors.lightGray);P.right(y,math.floor(pc*100+0.5).."%",colors.white)
        y=y+1;P.bar(1,y,w,pc,kind=="off" and colors.gray or COLOR[kind])
        if h>=20 then y=y+1;P.bar(1,y,w,pc,kind=="off" and colors.gray or COLOR[kind]) end
        y=y+2
    end
    -- pro Stunde fuer diese Turtle
    local spec=JOB[jobOf(e)]
    st.hist=st.hist or {}
    local now=os.clock();local key=spec.value(d)
    local last=st.hist[#st.hist]
    if not last or now-last.t>=30 then st.hist[#st.hist+1]={t=now,v=key};while #st.hist>31 do table.remove(st.hist,1) end end
    local first=st.hist[1]
    local perH=(first and now-first.t>=60) and short(math.max(0,(key-first.v)/(now-first.t)*3600)) or "-"
    local rows=spec.rows(d)
    -- "pro Stunde" direkt hinter dem Hauptwert
    local at=#rows+1
    for i,r in ipairs(rows) do if r[1]==spec.metric then at=i+1 end end
    table.insert(rows,math.min(at,#rows+1),{spec.metric.." / Stunde",perH})
    common_rows(rows,d)
    -- zweispaltig, wenn breit genug
    local cols=w>=56 and 2 or 1
    local cw=math.floor(w/cols)
    local per=math.ceil(#rows/cols)
    for i,r in ipairs(rows) do
        local c=math.floor((i-1)/per);local yy=y+(i-1)%per
        if yy<=h-1 then
            local x=1+c*cw
            P.text(x,yy,r[1],colors.lightGray)
            P.text(x+cw-1-#r[2]-(cols>1 and c==0 and 2 or 0),yy,r[2],colors.white)
        end
    end
    P.right(h,"Infoscreen v"..common.version,colors.gray)
end
-- show: "all", "farm", "mining" oder Turtle-ID (Zahl)
function M.drawInfo(screen,fleet,link,st,show)
    if type(show)=="number" then return drawTurtleInfo(screen,fleet,link,st,show) end
    local P=painter(screen);local w,h=P.w,P.h
    screen.setBackgroundColor(colors.black);screen.clear()
    local entries=fleet.entries or {}
    if common.job(show) then
        local ids={}
        for _,id in ipairs(fleet.ids or {}) do if (entries[id] or {}).job==show then ids[#ids+1]=id end end
        fleet={ids=ids,entries=entries}
    end
    -- Summen je Aufgabe
    local G={}
    for _,j in ipairs(ORDER) do G[j]={n=0,act=0,value=0,aux=0,progSum=0,progN=0} end
    local fuel,chunk=0,0
    local problems,list={},{}
    for _,id in ipairs(fleet.ids or {}) do
        local e=entries[id] or {};local d=e.data or {}
        local job=jobOf(e);local g=G[job];local spec=JOB[job]
        local label,kind=M.state(e,link)
        g.n=g.n+1
        if kind=="work" or kind=="move" or kind=="wait" then g.act=g.act+1 end
        g.value=g.value+spec.value(d);g.aux=g.aux+spec.aux[2](d)
        if hasProgress(d) then g.progSum=g.progSum+progress(d);g.progN=g.progN+1 end
        if kind~="off" then
            if d.fuel~="unlimited" then fuel=fuel+num(d.fuel) end
            if num(d.chunks)>0 then chunk=chunk+num(d.chunkFuel) end
        end
        if kind=="fault" or kind=="warn" then problems[#problems+1]={id=id,e=e,label=label,kind=kind} end
        list[#list+1]={id=id,e=e,label=label,kind=kind,job=job}
    end
    -- Verlauf fuer "pro Stunde" (alle 30 s ein Messpunkt, 15 min behalten)
    st.hist=st.hist or {}
    local now=os.clock()
    local last=st.hist[#st.hist]
    if not last or now-last.t>=30 then
        local p={t=now};for _,j in ipairs(ORDER) do p[j]=G[j].value end
        st.hist[#st.hist+1]=p
        while #st.hist>31 do table.remove(st.hist,1) end
    end
    local function rate(key,cur)
        local first=st.hist[1]
        if not first or not first[key] or now-first.t<60 then return "-" end
        return short(math.max(0,(cur-first[key])/(now-first.t)*3600))
    end
    -- Kopf
    P.fill(1,colors.blue)
    local online=0;for _,l in ipairs(list) do if l.kind~="off" then online=online+1 end end
    local clock=clockText()
    local rt=link and headRight(w-7,online,#list,clock) or "keine Verbindung "
    local title=JOB[show] and JOB[show].plural or "Uebersicht"
    P.text(2,1,(#rt+10+#title<=w) and ("TOAST  "..title) or "TOAST",colors.white,colors.blue)
    P.right(1,rt,link and colors.white or colors.orange,colors.blue)
    -- Kacheln je Aufgabe (zwei nebeneinander, wenn Platz)
    local y=3
    local function panel(x,y0,pw,title,a,n,rows)
        P.text(x,y0,title,colors.white)
        local s=a.."/"..n.." aktiv"
        P.text(x+pw-#s,y0,s,a>0 and colors.lime or colors.lightGray)
        local yy=y0+1
        for _,r in ipairs(rows) do
            P.text(x,yy,r[1],colors.lightGray)
            P.text(x+pw-#r[2],yy,r[2],colors.white)
            if r.bar then
                -- gruener Balken zwischen Bezeichnung und Prozent
                local bx=x+#r[1]+1;local bw=pw-#r[1]-#r[2]-2
                if bw>=3 then P.thin(bx,yy,bw,r.bar,colors.lime) end
            end
            yy=yy+1
        end
        return yy
    end
    local present={};for _,j in ipairs(ORDER) do if G[j].n>0 then present[#present+1]=j end end
    local side=w>=50 and #present>1
    -- Kleiner Bildschirm: nur die wichtigsten Zeilen, damit die Liste Platz hat
    local compact=(not side and h<26 and #present>1) or (h<26 and #present>2)
    local function rowsFor(j)
        local g,spec=G[j],JOB[j]
        local rows
        if compact then rows={{spec.metric,short(g.value).."  ("..rate(j,g.value).."/h)"}}
        else rows={{spec.metric,short(g.value).." "..spec.unit},{"pro Stunde",rate(j,g.value)},
            {spec.aux[1],short(g.aux)..spec.aux[3]}} end
        if g.progN>0 and (j=="mining" or not compact) then
            local pc=g.progSum/g.progN
            rows[#rows+1]={"Fortschritt",math.floor(pc*100+0.5).."%",bar=pc}
        end
        return rows
    end
    if side then
        local pw=math.floor((w-3)/2)
        for i=1,#present,2 do
            local a,b=present[i],present[i+1]
            local y1=panel(1,y,pw,JOB[a].name:upper(),G[a].act,G[a].n,rowsFor(a))
            local y2=b and panel(pw+4,y,w-pw-3,JOB[b].name:upper(),G[b].act,G[b].n,rowsFor(b)) or y1
            y=math.max(y1,y2)+(compact and 0 or 1)
        end
        if compact then y=y+1 end
    else
        for i,j in ipairs(present) do
            y=panel(1,y,w,JOB[j].name:upper(),G[j].act,G[j].n,rowsFor(j))
            if not compact or i==#present then y=y+1 end
        end
    end
    if #list==0 then
        P.text(1,y,"Noch keine Turtles gemeldet.",colors.lightGray)
        return
    end
    -- Probleme zuerst
    if #problems>0 and y<h-1 then
        local maxP=math.max(1,math.floor((h-y-2)/2))   -- Platz fuer die Liste lassen
        P.text(1,y,"PROBLEME",colors.orange);y=y+1
        for n,p in ipairs(problems) do
            if y>=h-1 or n>maxP then break end
            local d=p.e.data or {}
            local name=p.e.label~="" and p.e.label or ("#"..p.id)
            P.text(1,y,"\7",COLOR[p.kind]);P.text(3,y,name,colors.white)
            local msg=tostring(d.fault or d.status or p.label)
            P.text(math.min(w,4+#name),y,(" "..msg):sub(1,math.max(0,w-3-#name)),COLOR[p.kind])
            y=y+1
        end
        if not compact then y=y+1 end
    end
    -- Alle Turtles (blaettert automatisch)
    local footer=h
    local avail=footer-1-y
    if avail>=2 then
        P.text(1,y,"TURTLES",colors.white);y=y+1;avail=avail-1
        local pages=math.max(1,math.ceil(#list/math.max(1,avail)))
        st.page=st.page or 1
        if not st.flip then st.flip=now
        elseif now-st.flip>=6 then st.page=st.page%pages+1;st.flip=now end
        if st.page>pages then st.page=1 end
        if pages>1 then P.right(y-1,st.page.."/"..pages,colors.lightGray) end
        local barW=w>=60 and 20 or w>=40 and math.min(14,w-30) or w>=30 and 6 or 0
        for i=1,avail do
            local l=list[(st.page-1)*avail+i];if not l then break end
            local d=l.e.data or {}
            local name=l.e.label~="" and l.e.label or (JOB[l.job].name.." #"..l.id)
            P.text(1,y,l.kind=="pause" and "!" or "\7",COLOR[l.kind])
            local stx=w-8
            local val=""
            if l.kind~="off" then val=short(JOB[l.job].value(d)) end
            if barW>0 then
                -- [Zustand] [gruener Balken] [Prozent] [Wert]
                local valW=w>=40 and 6 or 0
                local bx=w-valW-5-barW+1
                stx=bx-9
                if l.kind~="off" and hasProgress(d) then
                    local pc=progress(d)
                    P.thin(bx,y,barW,pc,colors.lime)
                    P.text(bx+barW,y,string.format("%4d%%",math.floor(pc*100+0.5)),colors.lightGray)
                end
                if valW>0 then P.right(y,val,colors.lightGray) end
                P.text(stx,y,l.label,COLOR[l.kind])
            else
                P.text(stx,y,l.label,COLOR[l.kind])
            end
            P.text(3,y,name:sub(1,math.max(1,stx-4)),l.kind=="off" and colors.gray or colors.white)
            y=y+1
        end
    end
    -- Fusszeile
    local fl=("Fuel "..short(fuel)..(chunk>0 and ("  Chunks -"..short(chunk).."/h") or ""))
    local ver="v"..common.version
    P.text(1,footer,fl:sub(1,w),colors.lightGray)
    if #fl+#ver+2<=w then P.right(footer,ver,colors.gray) end
end
function M.new(screen,cfg)
    -- kbd: Tastatur-Bedienung sichtbar (Markierung + Tastenhinweise).
    -- Auf dem eigenen Bildschirm (Pocket/Computer) immer, am Monitor sobald
    -- eine Taste gedrueckt wurde.
    local ui={filter="all",selected=nil,page=1,buttons={},ids={},cursor=nil,kbd=screen==term,help=false}
    function ui.setScreen(s) screen=s;ui.kbd=ui.kbd or s==term end
    local CONFIRM=5
    local function confirming() return ui.confirm and os.clock()-ui.confirm.at<CONFIRM and ui.confirm end
    function ui.draw(fleet,link,notice)
        local w,h=screen.getSize();ui.buttons={}
        local color=screen.isColor and screen.isColor()
        setTrack(screen)
        -- Ohne Farbbildschirm nur Grautoene verwenden
        local function col(c)
            if color then return c end
            if c==TRACK then return colors.gray end
        if c==colors.black or c==colors.gray or c==colors.lightGray or c==colors.white then return c end
            return colors.white
        end
        local function fill(y,bg) screen.setCursorPos(1,y);screen.setBackgroundColor(col(bg));screen.write(string.rep(" ",w)) end
        local function text(x,y,s,fg,bg)
            if x<1 or x>w or y<1 or y>h then return end
            s=tostring(s):sub(1,w-x+1)
            screen.setCursorPos(x,y);screen.setTextColor(col(fg or colors.white));screen.setBackgroundColor(col(bg or colors.black))
            screen.write(s)
        end
        local function right(y,s,fg,bg) s=tostring(s);text(math.max(1,w-#s+1),y,s,fg,bg) end
        -- Knopf; height>1 = groesserer Knopf (leichter zu treffen am Monitor).
        -- Zwischen nebeneinanderliegenden Knoepfen bleibt 1 Spalte Luft (gap).
        local function button(x,y,width,label,action,bg,enabled,height,gap)
            if width<1 then return end
            height=height or 1
            local bw=width-(gap and width>4 and 1 or 0)
            local b=enabled and bg or colors.gray
            local l=tostring(label):sub(1,bw)
            local pad=math.floor((bw-#l)/2)
            local mid=y+math.floor((height-1)/2)
            for yy=y,y+height-1 do
                text(x,yy,string.rep(" ",bw),colors.white,b)
                ui.buttons[#ui.buttons+1]={x=x,y=yy,w=bw,action=action,enabled=enabled}
            end
            text(x+pad,mid,l,enabled and colors.white or colors.lightGray,b)
        end
        -- Schlichter, eckiger Knopf (einfarbig, Text mittig).
        local color=screen.isColor and screen.isColor()
        local function pill(x,y,width,label,action,bg,enabled,fgc)
            if width<1 then return end
            local b=enabled and bg or TRACK
            local f=fgc or (enabled and colors.white or colors.gray)
            if not enabled then f=colors.gray end
            if false then   -- runde Enden sahen im Spiel ausgefranst aus: eckig ist sauberer
                text(x,y,"\145",colors.black,b)
                text(x+1,y,string.rep(" ",width-2),f,b)
                text(x+width-1,y,"\157",b,colors.black)
                local l=tostring(label):sub(1,width-2)
                text(x+1+math.floor((width-2-#l)/2),y,l,f,b)
            else
                local l=tostring(label):sub(1,width)
                text(x,y,string.rep(" ",width),f,b)
                text(x+math.floor((width-#l)/2),y,l,f,b)
            end
            ui.buttons[#ui.buttons+1]={x=x,y=y,w=width,action=action,enabled=enabled}
        end
        screen.setBackgroundColor(colors.black);screen.setTextColor(colors.white);screen.clear()
        if not confirming() then ui.confirm=nil end
        if ui.help then
            fill(1,colors.blue);text(2,1,"TOAST - Tasten",colors.white,colors.blue)
            local L={{"\24 \25","Turtle waehlen"},{"Enter","Details oeffnen"},{"\27 Back","zurueck"},
                {"\27 \26 Tab","Reiter wechseln"},{"S","Start"},{"X","Stop"},{"E","einmal (1 Runde)"},
                {"R",w>=30 and "Reset (2x druecken)" or "Reset (2x)"},{"U","Update alle (2x)"},{"Bild\24\25","Seite blaettern"},{"H / ?","diese Hilfe"},{"Q","beenden"}}
            local kw=w>=34 and 11 or 9
            for i,l in ipairs(L) do
                if i+2>h-1 then break end
                text(2,i+2,l[1],colors.yellow);text(2+kw,i+2,l[2],colors.white)
            end
            text(1,h,("Taste druecken = weiter"):sub(1,w),colors.lightGray)
            right(1,"v"..common.version.." ",colors.white,colors.blue)
            ui.buttons={{x=1,y=1,w=w,action="help",enabled=true}}
            for y=2,h do ui.buttons[#ui.buttons+1]={x=1,y=y,w=w,action="help",enabled=true} end
            return
        end
        if w<24 or h<12 then
            text(1,1,"TOAST",colors.cyan);text(1,3,"Bildschirm zu klein",colors.orange)
            text(1,4,"mind. 24 x 12 Zeichen");text(1,5,"(Monitor groesser oder");text(1,6," Schrift kleiner)");return
        end
        local entries=fleet.entries or {}
        -- Zaehlen + Gruppenwerte
        local ids,count={},{}
        local g={}
        for _,j in ipairs(ORDER) do count[j]=0;g[j]={on=0,act=0,value=0} end
        local online,faults,chunkFuel=0,0,0
        for _,id in ipairs(fleet.ids or {}) do
            local e=entries[id] or {};local d=e.data or {}
            local job=jobOf(e)
            count[job]=count[job]+1
            local _,kind=M.state(e,link)
            local gg=g[job]
            gg.value=gg.value+JOB[job].value(d)
            if kind~="off" then gg.on=gg.on+1 end
            if kind=="work" or kind=="move" or kind=="wait" then gg.act=gg.act+1 end
            if ui.filter=="all" or job==ui.filter then
                ids[#ids+1]=id
                if kind~="off" then online=online+1 end
                if kind=="fault" or kind=="warn" then faults=faults+1 end
                if kind~="off" and num(d.chunks)>0 then chunkFuel=chunkFuel+num(d.chunkFuel) end
            end
        end
        -- Probleme zuerst, dann aktive, dann der Rest (sonst stabile Reihenfolge)
        local rank,pos={fault=1,warn=2,pause=2,work=3,move=3,wait=3,done=4,idle=4,off=5},{}
        for i,id in ipairs(ids) do local _,k=M.state(entries[id] or {},link);pos[id]=(rank[k] or 4)*10000+i end
        table.sort(ids,function(a,b) return pos[a]<pos[b] end)
        if ui.filter~="net" and ui.filter~="store" then
            ui.ids=ids
            if ui.selected and not common.contains(ids,ui.selected) then ui.selected=nil end
            if ui.cursor and not common.contains(ids,ui.cursor) then ui.cursor=nil end
            if not ui.cursor then ui.cursor=ui.selected or ids[1] end
        end
        -- Kopfzeile
        fill(1,colors.blue)
        if ui.storeOnly then
            -- Lager-Computer: nur die Lageransicht, oben Fuellstand + Uhr
            local nd=fleet.nodes or {ids={},entries={}}
            local sz,fl=0,0
            for _,nid in ipairs(nd.ids) do local st1=nd.entries[nid].data and nd.entries[nid].data.stats or {}
                sz=sz+num(st1.size);fl=fl+num(st1.pct)*num(st1.size) end
            text(2,1,"TOAST LAGER",colors.white,colors.blue)
            local clock=clockText()
            local r=(sz>0 and (math.floor(fl/sz+0.5).."% voll") or "").."  "..clock.." "
            if #r+13>w then r=clock.." " end
            right(1,r,colors.white,colors.blue)
            return ui.drawStore(nd,true,text,right,fill,pill,w,h,notice,2)
        end
        text(2,1,"TOAST",colors.white,colors.blue)
        -- Update-Knopf: alle Geraete holen sich die neue Version und machen weiter
        if ui.canUpdate~=false then
            local up=confirming() and ui.confirm.action=="update"
            local lab=up and "Sicher?" or "Update"
            local x=8
            text(x,1," "..lab.." ",up and colors.white or colors.blue,up and colors.red or colors.lightBlue)
            ui.buttons[#ui.buttons+1]={x=x,y=1,w=#lab+2,action="update",enabled=link}
        end
        -- rechts: online + Uhr (auf kleinen Pockets gekuerzt: "7/8 11:08")
        local room=w-(ui.canUpdate~=false and 16 or 7)
        local clock=clockText()
        if link and ui.filter=="net" and fleet.nodes then
            local on=0;for _,id in ipairs(fleet.nodes.ids) do if fleet.nodes.entries[id].online then on=on+1 end end
            right(1,headRight(room,on,#fleet.nodes.ids,clock),colors.white,colors.blue)
        elseif link then right(1,headRight(room,online,#ids,clock),colors.white,colors.blue)
        else right(1,(#clock>0 and room>=#clock+18) and ("keine Verbindung  "..clock.." ") or "keine Verbindung ",colors.orange,colors.blue) end
        -- Reiter
        -- Reiter: Alle + jede Aufgabe, die es gibt (Farm und Mine immer)
        local total=0;for _,j in ipairs(ORDER) do total=total+count[j] end
        local tabs={{"Alle",total,"all"}}
        for _,j in ipairs(ORDER) do
            if count[j]>0 or j=="farm" or j=="mining" or ui.filter==j then tabs[#tabs+1]={JOB[j].name,count[j],j} end
        end
        -- Netz: Repeater, GPS-Sender, Infoscreens, Pockets
        local nodes=fleet.nodes or {ids={},entries={}}
        local nStore=0;for _,nid in ipairs(nodes.ids) do if nodes.entries[nid].role=="storage" then nStore=nStore+1 end end
        if nStore>0 or ui.filter=="store" then tabs[#tabs+1]={"Lager",nStore,"store"} end
        if #nodes.ids>0 or ui.filter=="net" then tabs[#tabs+1]={"Netz",#nodes.ids,"net"} end
        ui.tabs={};for i,t in ipairs(tabs) do ui.tabs[i]=t[3] end
        local tw=math.floor(w/#tabs)
        for i,t in ipairs(tabs) do
            local active=ui.filter==t[3]
            local width=i==#tabs and w-(#tabs-1)*tw or tw
            local lab=t[1].." "..t[2]
            if #lab>width-2 then
                -- schmaler Bildschirm (Pocket): Kurzname + Anzahl, z.B. "M3"
                local SH={Alle="*",Farm="F",Mine="M",Holz="H",Mobs="Mo",Aushub="A",["Mobfarm-Bau"]="B",Lager="L",Netz="N"}
                local sh=SH[t[1]] or t[1]:sub(1,1)
                lab=(#t[1]<=width-1) and t[1] or ((#(sh..t[2])<=width-1) and (sh..t[2]) or sh)
            end
            local x=1+(i-1)*tw
            if active then pill(x,2,width,lab,"filter:"..t[3],colors.lightBlue,true,colors.black)
            else
                local l=lab:sub(1,width)
                text(x+math.floor((width-#l)/2),2,l,colors.lightGray,colors.black)
                ui.buttons[#ui.buttons+1]={x=x,y=2,w=width,action="filter:"..t[3],enabled=true}
            end
        end
        if ui.filter=="net" then return ui.drawNet(nodes,link,text,right,fill,pill,w,h,notice) end
        if ui.filter=="store" then return ui.drawStore(nodes,link,text,right,fill,pill,w,h,notice,3) end
        local third=math.floor(w/3)
        -- Fusszeile: Hinweiszeile + grosse Tastenreihe + untere Reihe
        -- Grosse Bildschirme bekommen hoehere Knoepfe (leichter zu treffen).
        local bh=1
        local foot=h-1-bh
        local sel=ui.selected and entries[ui.selected]
        local job=sel and jobOf(sel) or (ui.filter~="all" and ui.filter) or nil
        -- Was ist bei den Zielen gerade moeglich?
        local canStart,canStop,faultsT,running=false,false,0,0
        for _,id in ipairs(ids) do
            local e=entries[id]
            if (not ui.selected or ui.selected==id) and e then
                local d=e.data or {}
                local _,k=M.state(e,link)
                local active=d.mode=="auto" or d.mode=="once" or (d.mode==nil and (k=="work" or k=="move" or k=="wait"))
                if link and e.online and e.data and not d.recovery and not active then canStart=true end
                if link and e.online and active then canStop=true;running=running+1 end
                if link and (k=="fault" or k=="warn") then canStop=true;faultsT=faultsT+1 end
                if link and k=="pause" then canStop=true end
            end
        end
        ui.state={canStart=canStart,canStop=canStop,faults=faultsT,running=running}
        local startL="Start"
        local stopL="Stopp"
        local onceL=JOB[job] and JOB[job].once or "Einmal"
        onceL=onceL:sub(1,1)..onceL:sub(2):lower()
        local gap=w>=30 and 2 or 1
        local bw=math.floor((w-2*gap)/3)
        for i,b in ipairs({{startL,"start",colors.green,canStart},{stopL,"stop",colors.red,canStop},{onceL,"once",colors.blue,canStart}}) do
            local x=1+(i-1)*(bw+gap)
            pill(x,foot+1,i==3 and w-x+1 or bw,b[1],b[2],b[3],b[4])
        end
        local perPage
        -- ===== Detailansicht =====
        if sel then
            local d=sel.data or {}
            local label,kind=M.state(sel,link)
            local name=(sel.label and sel.label~="" and sel.label or JOB[jobOf(sel)].name).." #"..ui.selected
            local chests=type(d.chestList)=="table" and #d.chestList or 0
            if chests==0 and ui.detailView=="chests" then ui.detailView=nil end
            ui.chestView=ui.detailView=="chests"
            pill(1,3,math.min(w,#name+(w>=30 and 14 or 4)),(w>=30 and "\27 Zurueck  " or "\27 ")..name,"group",colors.gray,true)
            -- Reiter der Turtle: Info | Steuern | Einstellungen | Kisten
            local dtabs={{"Info","dv:info",nil},{w>=30 and "Steuern" or "Steuer","dv:drive","drive"},{w>=30 and "Einstellungen" or "Einst.","dv:config","config"}}
            if chests>0 then dtabs[#dtabs+1]={(w>=30 and "Kisten " or "K")..chests,"chests","chests"} end
            local tw2=math.floor(w/#dtabs)
            for i,t in ipairs(dtabs) do
                local act=ui.detailView==t[3]
                local width=i==#dtabs and w-(i-1)*tw2 or tw2-1
                pill(1+(i-1)*tw2,4,width,t[1],t[2],act and colors.lightBlue or colors.gray,true,act and colors.black or colors.white)
            end
            if ui.detailView=="chests" then
                -- Liste der gesetzten Abladekisten (scrollbar)
                local lines={}
                for _,k in ipairs(d.chestList) do
                    lines[#lines+1]={"Kiste "..tostring(k.n),colors.yellow}
                    local p=type(k.pos)=="table" and ("X:"..num(k.pos.x).." Y:"..num(k.pos.y).." Z:"..num(k.pos.z))
                        or (type(k.rel)=="table" and M.posText({rel=k.rel})) or "Position unbekannt"
                    lines[#lines+1]={p,colors.white}
                end
                local top=5
                local avail=math.max(2,foot-1-top);avail=avail-avail%2      -- immer ganze Kisten (2 Zeilen)
                ui.chestMax=math.max(0,#lines-avail)
                ui.chestScroll=math.max(0,math.min(ui.chestScroll or 0,ui.chestMax))
                if ui.chestScroll%2==1 then ui.chestScroll=ui.chestScroll-1 end
                for i=1,avail do
                    local l=lines[ui.chestScroll+i];if not l then break end
                    text(1,top+i-1,l[1]:sub(1,w-2),l[2])
                end
                if ui.chestMax>0 then
                    pill(w,top,1,"\24","cup",colors.gray,ui.chestScroll>0,colors.white)
                    pill(w,top+avail-1,1,"\25","cdown",colors.gray,ui.chestScroll<ui.chestMax,colors.white)
                end
            elseif ui.detailView=="drive" then
                ui.drawDrive(sel,d,link,text,right,fill,pill,button,w,foot)
            elseif ui.detailView=="config" then
                ui.drawConfig(sel,d,link,text,right,fill,pill,w,foot,fleet.configs and fleet.configs[ui.selected])
            else
            fill(5,COLOR[kind])
            local why=(kind=="fault" or kind=="warn" or kind=="pause") and (d.fault or d.status) or nil
            text(2,5,label..(why and (": "..tostring(why)) or ""),colors.black,COLOR[kind])
            -- Detailtext umbrechen (max. 2 Zeilen)
            local det=kind=="off" and "Keine Meldung: Chunk entladen? An der Turtle: toast.lua config -> Chunks -> An der Basis wach = j (oder /forceload)" or tostring(d.detail or "")
            local y=6
            while #det>0 and y<=7 do text(1,y,det:sub(1,w),colors.lightGray);det=det:sub(w+1);y=y+1 end
            y=8
            -- Fortschrittsbalken (nur wenn es eine Runde gibt)
            if hasProgress(d) then
                local pc=progress(d)
                local barW=math.max(4,w-6)
                local fillW=math.floor(barW*pc+0.5)
                text(1,y,string.rep(" ",fillW),colors.white,colors.lime)
                text(1+fillW,y,string.rep(" ",barW-fillW),colors.white,TRACK)
                right(y,math.floor(pc*100+0.5).."%",colors.white)
                y=y+2
            end
            local rows=common_rows(JOB[jobOf(sel)].rows(d),d)
            for _,r in ipairs(rows) do
                if y>=foot-1 then break end
                text(1,y,r[1],colors.lightGray);text(13,y,r[2],colors.white);y=y+1
            end
            end
        else
        -- ===== Uebersicht =====
            local y=3
            for _,j in ipairs(ORDER) do
                local gg=g[j]
                if count[j]>0 and (ui.filter=="all" or ui.filter==j) then
                    text(1,y,JOB[j].name,colors.white)
                    text(6,y,gg.act.."/"..count[j]..(w>=34 and " aktiv" or ""),gg.act>0 and colors.lime or colors.lightGray)
                    right(y,JOB[j].metric.." "..short(gg.value),colors.lightGray)
                    y=y+1
                end
            end
            local pl=faults>0 and ("! "..faults.." Problem"..(faults>1 and "e" or "")) or ""
            local cl=chunkFuel>0 and ("Chunks -"..short(chunkFuel).."/h") or ""
            if #pl+#cl+1>w then
                text(1,y,pl,colors.orange);y=y+1;right(y,cl,colors.lightGray);y=y+1
            elseif #pl+#cl>0 then
                text(1,y,pl,colors.orange);right(y,cl,colors.lightGray);y=y+1
            end
            if #ids==0 then
                text(1,y+1,"Keine Turtles.",colors.lightGray)
                text(1,y+2,"Turtles melden sich",colors.lightGray)
                text(1,y+3,"automatisch, sobald sie",colors.lightGray)
                text(1,y+4,"laufen.",colors.lightGray)
            end
            -- Liste
            local top=y
            local avail=math.max(1,foot-1-top)
            perPage=cfg.display.pageSize>0 and math.min(avail,cfg.display.pageSize) or avail
            local pages=math.max(1,math.ceil(#ids/perPage));ui.pages=pages;ui.page=math.min(ui.page,pages)
            local wide=w>=44
            ui.perPage=perPage
            -- Seite folgt der Tastatur-Markierung
            if ui.kbd and ui.cursor and ui.followCursor then
                for i,id in ipairs(ids) do if id==ui.cursor then ui.page=math.ceil(i/perPage) end end
                ui.followCursor=false
            end
            for row=1,perPage do
                local id=ids[(ui.page-1)*perPage+row];if not id then break end
                local e=entries[id] or {};local d=e.data or {}
                local label,kind=M.state(e,link)
                local yy=top+row-1
                local spec=JOB[jobOf(e)]
                local name=e.label and e.label~="" and e.label or (spec.name.." #"..id)
                local stW=8
                -- Rechts: [gruener Balken] [Prozent] [Wert] [Zustand]
                local barW=w>=70 and 20 or w>=44 and 10 or w>=34 and 6 or 0
                local value=wide and string.format("  %-8s%6s",spec.metric,short(spec.value(d))) or ""
                local block=barW>0 and (barW+5+#value) or 0      -- Balken + " 100%" + Wert
                local nameW=w-2-stW-1-(block>0 and block+1 or 0)
                local mark=ui.kbd and id==ui.cursor
                local bg=mark and colors.gray or colors.black
                local sc=(mark and kind=="off") and colors.lightGray or COLOR[kind]
                text(1,yy,string.rep(" ",w),colors.white,bg)
                text(1,yy,mark and "\16" or (kind=="pause" and "!" or "\7"),mark and colors.white or sc,bg)
                text(3,yy,name:sub(1,nameW),kind=="off" and (mark and colors.lightGray or colors.gray) or colors.white,bg)
                if block>0 and kind~="off" then
                    local x0=w-stW-block
                    if hasProgress(d) then
                        local pc=progress(d)
                        thinBar(text,x0,yy,barW,pc,colors.lime,bg)
                        text(x0+barW,yy,string.format("%4d%%",math.floor(pc*100+0.5)),mark and colors.white or colors.lightGray,bg)
                    end
                    if #value>0 then text(x0+barW+5,yy,value,mark and colors.white or colors.lightGray,bg) end
                end
                right(yy,string.format("%-8s",label),sc,bg)
                ui.buttons[#ui.buttons+1]={x=1,y=yy,w=w,action="id:"..id,enabled=true}
            end
        end
        -- Hinweiszeile + untere Tastenreihe
        local info=tostring(notice or "")
        if info:find("Warte auf Geraete",1,true) then info="" end
        local infoCol=colors.lightGray
        local goal=sel and "diese Turtle" or (ui.filter=="all" and "alle" or ("alle "..(JOB[ui.filter] and JOB[ui.filter].plural or ui.filter)))
        if confirming() and ui.confirm.action=="update" then
            info=w>=40 and "Alle Geraete updaten? Update nochmal tippen" or "Update? Nochmal tippen";infoCol=colors.cyan
        elseif confirming() then
            info=#goal+24<=w and ("Reset fuer "..goal.."? Nochmal = ja") or "Reset? Nochmal = ja";infoCol=colors.orange
        elseif info=="" or info:find("bestaetigt",1,true) then
            info="Ziel: "..goal
            local tip
            if ui.kbd then
                tip=sel and (w>=40 and "\24\25 Turtle  \27 zurueck  H Hilfe" or "\27 zurueck  H Hilfe")
                    or (w>=40 and "\24\25 Wahl  Enter Details  H Hilfe" or "\24\25 Enter  H Hilfe")
            else tip=not sel and "Tippen = Details" or nil end
            -- rechts die eigene Version (nicht bei Seitenzahl)
            local ver=((ui.pages or 1)>1 and not sel) and "" or (" v"..common.version)
            local W2=w-#ver
            if tip and #info+2+#tip<=W2 then info=info..string.rep(" ",W2-#info-#tip)..tip
            elseif tip and #tip<=W2 and ui.kbd and #info>W2 then info=tip end
            info=info:sub(1,W2)..string.rep(" ",math.max(0,W2-#info))
            if ver~="" then text(W2+1,foot,ver,colors.gray) end
        end
        text(1,foot,info:sub(1,w),infoCol)
        local pages=ui.pages or 1
        local sure=confirming() and ui.confirm.action=="reset"
        -- Reset: orange, wenn es Fehler gibt ("Fehler loeschen"), sonst unauffaellig grau
        -- Reset als dezenter Knopf: dunkelgrau, Schrift orange bei Fehlern, rot bei Nachfrage
        local function resetLabel(width)
            if sure then return width>=22 and "Sicher? Nochmal tippen" or "Sicher?" end
            if faultsT>0 then return width>=22 and "Fehler loeschen + heim" or width>=17 and "Fehler loeschen" or "Reset" end
            return width>=20 and "Reset (Stopp + heim)" or "Reset"
        end
        local rfg=sure and colors.white or (faultsT>0 and colors.orange or colors.lightGray)
        local rbg=sure and colors.red or colors.gray
        local y2=h
        if not sel and pages>1 then
            local pw=math.max(5,math.floor(w/6))
            pill(1,y2,pw,"\27","pageprev",colors.gray,ui.page>1,colors.white)
            pill(w-pw+1,y2,pw,"\26","pagenext",colors.gray,ui.page<pages,colors.white)
            local mw=w-2*pw-2*gap
            local lab=resetLabel(mw-2)
            pill(pw+gap+1,y2,mw,lab,"reset",rbg,link and #ids>0,rfg)
        else
            local lab=resetLabel(w-2)
            local rw=math.min(w,math.max(#lab+6,bw))
            pill(math.floor((w-rw)/2)+1,y2,rw,lab,"reset",rbg,link and #ids>0,rfg)
        end
        if not sel and pages>1 then right(foot,ui.page.."/"..pages,colors.gray) end
    end
    -- ===== Netz-Ansicht =====
    local NODE_NAMES={repeater="Repeater",gps="GPS-Sender",info="Infoscreen",pocket="Pocket",storage="Lager"}
    -- ===== Lager (Kistenueberwachung) =====
    -- Kisten mit Fuellstand oder Inhalt (alle Lager zusammen, mit Suche).
    -- Tippen auf ein Item zeigt, in welchen Kisten es liegt.
    local function fillColor(p,warn)
        p=num(p);if p>=100 then return colors.red elseif p>=num(warn or 90) then return colors.orange end
        return colors.lime
    end
    -- ===== Fernsteuerung: von Hand fahren =====
    local function bname(n)
        if not n then return "-" end
        n=tostring(n):gsub("^[^:]+:",""):gsub("_"," ")
        return n
    end
    function ui.drawDrive(sel,d,link,text,right,fill,pill,button,w,foot)
        local on=d.manual==true
        local can=link and sel.online and d.mode=="off" and not d.recovery
        local y=5
        if on then
            fill(y,colors.lime);text(2,y,"Fernsteuerung AN",colors.black,colors.lime)
            local l=w>=30 and " Beenden + heim " or " Beenden "
            pill(w-#l+1,y,#l,l,"rc:manual_off",colors.red,link,colors.white)
        else
            fill(y,colors.gray);text(2,y,can and "Fernsteuerung aus" or (d.mode~="off" and "Erst stoppen" or "nicht erreichbar"),colors.white,colors.gray)
            local l=" Steuern "
            pill(w-#l+1,y,#l,l,"rc:manual_on",colors.green,can,colors.white)
        end
        y=y+1
        if on then
            text(1,y,"Vorne",colors.lightGray);text(8,y,bname(d.mFront):sub(1,w-8));y=y+1
            local ou="Oben "..bname(d.mUp):sub(1,math.floor(w/2)-6)
            text(1,y,ou,colors.lightGray);text(math.floor(w/2)+1,y,("Unten "..bname(d.mDown)):sub(1,w-math.floor(w/2)),colors.lightGray);y=y+1
            -- Modus: Abbau/Angriff <-> Bauen (Taste B oder Tab), im Bau-Modus Block (Taste T)
            local build=ui.driveMode=="build"
            local half=math.floor(w/2)
            pill(1,y,half-1,(build and "Bauen" or "Abbau/Angriff")..(ui.kbd and " B" or ""),"dm:toggle",build and colors.green or colors.brown,true,colors.white)
            if build then
                local nl=(w>=30 and "Naechster Block" or "Block \26")..(ui.kbd and " T" or "")
                pill(half+1,y,w-half,nl,"rc:nextblock",colors.blue,link,colors.white)
                y=y+1
                local bl=d.mBlock and (bname(d.mBlock)..(d.mBlockN and (" x"..d.mBlockN) or "")) or "kein Block (nach 'Steuern' einlegen)"
                text(1,y,("Setzt: "..bl):sub(1,w),d.mBlock and colors.white or colors.orange)
            else
                text(half+1,y,("Hand "..bname(d.mLeft)):sub(1,w-half),colors.gray)
            end
            y=y+1
        else
            text(1,y,"Turtle stoppen, dann 'Steuern'.",colors.lightGray);y=y+1
            text(1,y,"Beenden = sie faehrt zur Basis.",colors.lightGray);y=y+1
            y=y+1
        end
        local msg=tostring(d.mMsg or "")
        text(1,y,msg:sub(1,w),msg:find("Geht nicht",1,true) and colors.orange or colors.cyan);y=y+1
        -- Steuerkreuz 3x3 (Tasten in Klammern):
        --   Hoch(E)      Vor(W)        oben(R)
        --   Links(A)     Leertaste     Rechts(D)
        --   Runter(C)    Zurueck(S)    unten(F)
        -- Mitte/oben/unten = abbauen ODER angreifen, je nach Werkzeug (Schwert = Angriff)
        local sword=tostring(d.mLeft or ""):find("sword",1,true) or tostring(d.mRight or ""):find("sword",1,true)
        local use=sword and "Angriff" or "Abbau"
        local k=ui.kbd
        local function L(long,short,key) local s=w>=30 and long or short;return k and (s.." "..key) or s end
        local u3=sword and "Ang" or "Abb"
        local uc=sword and colors.red or colors.brown
        if ui.driveMode=="build" then use,u3,uc="Setzen","Setz",colors.green end
        local grid={
            {{L("Hoch","Hoch","E"),"up",colors.cyan},{L("\24 Vor","\24 Vor","W"),"forward",colors.blue},{L(use.." \24",u3.." \24","R"),"useUp",colors.brown}},
            {{L("\27 Links","\27 Links","A"),"left",colors.blue},{L(use,ui.driveMode=="build" and "Setzen" or (sword and "Angr." or "Abbau"),"[ ]"),"use",uc},{L("Rechts \26","Rechts\26","D"),"right",colors.blue}},
            {{L("Runter","Runter","C"),"down",colors.cyan},{L("\25 Zurueck","\25 Zur.","S"),"back",colors.blue},{L(use.." \25",u3.." \25","F"),"useDown",colors.brown}},
        }
        local free=foot-1-y
        local bh=free>=9 and 3 or free>=6 and 2 or 1
        local cw=math.floor(w/3)
        for _,r in ipairs(grid) do
            if y+bh-1>foot-1 then break end
            for i,b in ipairs(r) do
                local x=1+(i-1)*cw
                local width=i==3 and w-x+1 or cw
                button(x,y,width,b[1],"rc:"..b[2],b[3],on and link,bh,true)
            end
            y=y+bh
        end
        if y<=foot-1 and not k then
            text(1,y,(w>=36 and "Tastatur: WASD, Leer, E/C, R/F, B Modus, T Block" or "WASD Leer E/C R/F B T"):sub(1,w),colors.gray)
        end
    end
    -- ===== Fernsteuerung: Einstellungen abrufen/aendern =====
    ui.cfgEdits={}
    local function cfgLines(cf,id)
        local ed=ui.cfgEdits[id] or {values={}}
        local L={}
        local jobs=cf.jobs or common.JOBS
        L[#L+1]={kind="job",label="Aufgabe",value=ed.job or cf.job,opts=jobs,changed=ed.job~=nil}
        L[#L+1]={kind="name",label="Name",value=ed.name or cf.name or "",changed=ed.name~=nil}
        for _,sec in ipairs(cf.sections or {}) do
            L[#L+1]={kind="title",label=sec.title or sec.name}
            for _,f in ipairs(sec.fields or {}) do
                local ev=ed.values[sec.name] and ed.values[sec.name][f.k]
                local v=ev;if v==nil then v=f.v end
                L[#L+1]={kind="field",sec=sec.name,k=f.k,label=f.d or f.k,value=v,opts=f.o,changed=ev~=nil,orig=f.v}
            end
        end
        return L
    end
    local function showVal(l)
        local v=l.value
        if l.kind=="job" then return common.JOB_NAMES[v] or tostring(v) end
        if type(v)=="boolean" then return v and "ja" or "nein" end
        if v=="" then return "-" end
        return tostring(v)
    end
    function ui.drawConfig(sel,d,link,text,right,fill,pill,w,foot,cfgEntry)
        local id=ui.selected
        local y=5
        fill(y,colors.gray);text(2,y,"Einstellungen",colors.white,colors.gray)
        local rl=w>=30 and " Neu laden " or " Laden "
        pill(w-#rl+1,y,#rl,rl,"rc:getconfig",colors.blue,link and sel.online,colors.white)
        y=y+1
        local cf=cfgEntry and cfgEntry.config
        if not cf then
            text(1,y+1,"Lade Einstellungen ...",colors.lightGray)
            text(1,y+2,link and sel.online and "(Turtle muss erreichbar sein)" or "Turtle nicht erreichbar",colors.gray)
            return
        end
        local L=cfgLines(cf,id)
        ui.cfgLinesCache=L
        -- unten: Beschreibung, Bearbeiten, Speichern
        local editY=foot-3
        local listTop,listBot=y,editY-1
        local avail=listBot-listTop+1
        ui.cfgSel=ui.cfgSel or 1
        if not L[ui.cfgSel] or L[ui.cfgSel].kind=="title" then
            for i,l in ipairs(L) do if l.kind~="title" then ui.cfgSel=i;break end end
        end
        ui.cfgScroll=ui.cfgScroll or 0
        if ui.cfgSel<=ui.cfgScroll then ui.cfgScroll=ui.cfgSel-1 end
        if ui.cfgSel>ui.cfgScroll+avail then ui.cfgScroll=ui.cfgSel-avail end
        ui.cfgScroll=math.max(0,math.min(ui.cfgScroll,math.max(0,#L-avail)))
        for i=1,avail do
            local idx=ui.cfgScroll+i;local l=L[idx];if not l then break end
            local yy=listTop+i-1
            if l.kind=="title" then
                text(1,yy,("- "..l.label):sub(1,w),colors.cyan)
            else
                local val=showVal(l)
                local selc=idx==ui.cfgSel
                local bg=selc and colors.gray or colors.black
                local vw=math.min(#val,math.floor(w/2))
                text(1,yy,string.rep(" ",w),colors.white,bg)
                text(1,yy,l.label:sub(1,w-vw-1),colors.lightGray,bg)
                text(w-vw+1,yy,val:sub(1,vw),l.changed and colors.yellow or colors.white,bg)
                ui.buttons[#ui.buttons+1]={x=1,y=yy,w=w-1,action="cf:sel:"..idx,enabled=true}
            end
        end
        if #L>avail then
            pill(w,listTop,1,"\24","cf:scroll:-1",colors.gray,ui.cfgScroll>0,colors.white)
            pill(w,listBot,1,"\25","cf:scroll:1",colors.gray,ui.cfgScroll<#L-avail,colors.white)
        end
        -- Bearbeiten
        local l=L[ui.cfgSel]
        local msgOk=cfgEntry.msg and os.clock()-(cfgEntry.at or 0)<20
        if msgOk then text(1,editY,tostring(cfgEntry.msg):sub(1,w),cfgEntry.ok==false and colors.orange or colors.lime)
        elseif l then text(1,editY,(l.k and (l.k..": ") or "")..tostring(l.label):sub(1,w),colors.gray) end
        local ey=editY+1
        if l and l.kind~="title" then
            local v=l.value
            if l.kind=="job" or (l.opts and type(v)=="string") then
                local q=math.floor(w/4)
                pill(1,ey,q,"\27","cf:opt:-1",colors.blue,true,colors.white)
                local vs=showVal(l);text(q+1+math.floor((w-2*q-#vs)/2),ey,vs:sub(1,w-2*q),colors.yellow)
                pill(w-q+1,ey,q,"\26","cf:opt:1",colors.blue,true,colors.white)
            elseif type(v)=="boolean" then
                pill(1,ey,w,v and "ja  (tippen = nein)" or "nein  (tippen = ja)","cf:toggle",colors.blue,true,colors.white)
            elseif type(v)=="number" then
                local q=math.floor(w/4)
                for i,st in ipairs({{"-10",-10},{"-1",-1},{"+1",1},{"+10",10}}) do
                    pill(1+(i-1)*q,ey,i==4 and w-3*q or q-1,st[1],"cf:add:"..st[2],colors.blue,true,colors.white)
                end
            else
                text(1,ey,(ui.kbd and "Tastatur: tippen, Back = loeschen" or "Text: am Pocket/PC tippen"):sub(1,w-8),colors.lightGray)
                pill(w-6,ey,7,"Leeren","cf:clear",colors.gray,true,colors.white)
            end
        end
        local ed=ui.cfgEdits[id]
        local dirty=ed and (ed.job or ed.name or next(ed.values or {}))
        local half=math.floor(w/2)
        pill(1,foot-1,half-1,"Speichern","cf:save",colors.green,dirty and link and sel.online and true or false,colors.white)
        pill(half+1,foot-1,w-half,"Verwerfen","cf:discard",colors.gray,dirty and true or false,colors.white)
    end
    local function cfgEdit(id) ui.cfgEdits[id]=ui.cfgEdits[id] or {values={}};return ui.cfgEdits[id] end
    local function cfgSet(l,v)
        l.value=v;l.changed=true          -- sofort sichtbar (auch ohne Neuzeichnen dazwischen)
        local ed=cfgEdit(ui.selected)
        if l.kind=="job" then ed.job=v
        elseif l.kind=="name" then ed.name=v
        else
            ed.values[l.sec]=ed.values[l.sec] or {}
            if v==l.orig then ed.values[l.sec][l.k]=nil;if not next(ed.values[l.sec]) then ed.values[l.sec]=nil end
            else ed.values[l.sec][l.k]=v end
        end
    end
    -- Aktionen der Fernsteuerung -> nil oder {id=,payload=} (an die Turtle)
    function ui.remoteAction(a)
        local id=ui.selected;if not id then return end
        if a:match("^rc:") then
            local op=a:sub(4)
            if ui.driveMode=="build" then
                op=({use="place",useUp="placeUp",useDown="placeDown"})[op] or op
            end
            return {id=id,payload={op=op}}
        end
        local L=ui.cfgLinesCache or {}
        local l=L[ui.cfgSel or 0]
        if a:match("^cf:sel:") then ui.cfgSel=tonumber(a:sub(8));return end
        if a:match("^cf:scroll:") then ui.cfgScroll=(ui.cfgScroll or 0)+tonumber(a:sub(11));return end
        if a=="cf:discard" then ui.cfgEdits[id]=nil;return end
        if a=="cf:save" then
            local ed=ui.cfgEdits[id];if not ed then return end
            ui.cfgEdits[id]=nil
            return {id=id,payload={op="setconfig",job=ed.job,name=ed.name,values=ed.values}}
        end
        if not l or l.kind=="title" then return end
        if a=="cf:toggle" and type(l.value)=="boolean" then cfgSet(l,not l.value)
        elseif a:match("^cf:add:") and type(l.value)=="number" then cfgSet(l,l.value+tonumber(a:sub(8)))
        elseif a:match("^cf:opt:") then
            local opts=l.opts;if not opts then return end
            local i=1;for k,o in ipairs(opts) do if o==l.value then i=k end end
            i=(i-1+tonumber(a:sub(8)))%#opts+1;cfgSet(l,opts[i])
        elseif a=="cf:clear" and (l.kind=="name" or type(l.value)=="string") then cfgSet(l,"")
        end
    end
    -- Texteingabe im Einstellungs-Reiter (freie Texte, z.B. keepOres, Name)
    local function cfgTextField()
        if ui.detailView~="config" or not ui.selected then return end
        local l=(ui.cfgLinesCache or {})[ui.cfgSel or 0]
        if l and (l.kind=="name" or (l.kind=="field" and type(l.value)=="string" and not l.opts)) then return l end
    end
    -- Texteingabe / Steuermodus: Q beendet dann nicht das Programm
    function ui.textInput() return ui.filter=="store" or cfgTextField()~=nil or (ui.selected~=nil and ui.detailView=="drive") end
    function ui.drawStore(nodes,link,text,right,fill,pill,w,h,notice,y0)
        ui.ids={};ui.selected=nil
        local stores={}
        for _,id in ipairs(nodes.ids or {}) do
            local e=nodes.entries[id]
            if e.role=="storage" then stores[#stores+1]={id=id,e=e,st=(e.data and e.data.stats) or {}} end
        end
        ui.storeView=ui.storeView or "chests"
        ui.search=ui.search or ""
        local y=y0 or 3
        -- Umschalter Kisten / Inhalt
        local half=math.floor(w/2)
        local isC=ui.storeView=="chests" and not ui.storeItem
        pill(1,y,half-1,"Kisten","sview:chests",isC and colors.lightBlue or colors.gray,true,isC and colors.black or colors.white)
        pill(half+1,y,w-half,"Inhalt","sview:items",(not isC) and colors.lightBlue or colors.gray,true,(not isC) and colors.black or colors.white)
        y=y+1
        if #stores==0 then
            text(1,y+1,"Noch kein Lager gemeldet.",colors.lightGray)
            text(1,y+2,"Computer an die Kisten stellen",colors.lightGray)
            text(1,y+3,"(oder per Netzwerkkabel) und",colors.lightGray)
            text(1,y+4,"als 5 'Lager' installieren.",colors.lightGray)
            return
        end
        local multi=#stores>1
        local rows={}
        if ui.storeItem then
            -- Wo liegt das Item?
            local name,total=ui.storeItem,0
            local where={}
            for _,s in ipairs(stores) do
                for _,it in ipairs(s.st.items or {}) do
                    if it.id==ui.storeItem then
                        name=it.n or it.id;total=total+num(it.c)
                        for _,wh in ipairs(it.w or {}) do
                            local ch=(s.st.chests or {})[wh.i] or {}
                            where[#where+1]={label=(multi and ((s.e.label~="" and s.e.label or ("Lager #"..s.id)).." / ") or "")..tostring(ch.n or ("Kiste "..wh.i)),c=num(wh.c),p=ch.p}
                        end
                    end
                end
            end
            pill(1,y,math.min(w,#name+(w>=30 and 12 or 3)),(w>=30 and "\27 Zurueck  " or "\27 ")..name,"sback",colors.gray,true)
            y=y+1
            text(1,y,"Gesamt",colors.lightGray);right(y,short(total).." Stueck",colors.white);y=y+1
            for _,wh in ipairs(where) do rows[#rows+1]={kind="where",label=wh.label,c=wh.c,p=wh.p} end
            if #where==0 then rows[1]={kind="note",label="Nicht mehr im Lager."} end
        elseif ui.storeView=="chests" then
            for _,s in ipairs(stores) do
                local st=s.st
                local lname=s.e.label~="" and s.e.label or ("Lager #"..s.id)
                rows[#rows+1]={kind="head",label=lname..(s.e.online and "" or " (offline)"),p=st.pct,warn=st.warn,
                    info=short(st.count).." Kisten, "..short(st.types).." Sorten",on=s.e.online}
                for _,ch in ipairs(st.chests or {}) do
                    rows[#rows+1]={kind="chest",label=tostring(ch.n),p=ch.p,warn=st.warn,slots=num(ch.u).."/"..num(ch.s)}
                end
            end
        else
            -- Inhalt aller Lager, zusammengezaehlt, mit Suche
            local byId,list={},{}
            for _,s in ipairs(stores) do
                for _,it in ipairs(s.st.items or {}) do
                    local e=byId[it.id]
                    if not e then e={id=it.id,n=tostring(it.n or it.id),c=0,first=nil};byId[it.id]=e;list[#list+1]=e end
                    e.c=e.c+num(it.c)
                    if not e.first and it.w and it.w[1] then local ch=(s.st.chests or {})[it.w[1].i];e.first=ch and ch.n end
                end
            end
            local q=ui.search:lower()
            local shown={}
            for _,e in ipairs(list) do
                if q=="" or e.n:lower():find(q,1,true) or e.id:lower():find(q,1,true) then shown[#shown+1]=e end
            end
            table.sort(shown,function(a,b) return a.c>b.c end)
            if ui.kbd or q~="" then
                text(1,y,"Suche: ",colors.lightGray);text(8,y,(q~="" and q or "")..(ui.kbd and "_" or ""),colors.yellow)
                right(y,#shown.." Sorten",colors.lightGray);y=y+1
            end
            for _,e in ipairs(shown) do rows[#rows+1]={kind="item",label=e.n,c=e.c,id=e.id,first=e.first} end
            if #shown==0 then rows[1]={kind="note",label=q~="" and ("Nichts gefunden: "..q) or "Lager ist leer."} end
        end
        -- Seiten
        local avail=math.max(1,h-y)
        local pages=math.max(1,math.ceil(#rows/avail))
        ui.page=math.max(1,math.min(ui.page or 1,pages));ui.storePages=pages
        local first=(ui.page-1)*avail
        for i=1,avail do
            local r=rows[first+i];if not r then break end
            local yy=y+i-1
            if r.kind=="head" then
                local pc=string.format("%3d%%",num(r.p))
                text(1,yy,r.label:sub(1,w-6),r.on and colors.white or colors.gray)
                right(yy,pc,fillColor(r.p,r.warn))
                if w>=40 then text(math.max(#r.label+3,w-6-#r.info-1),yy,r.info,colors.lightGray) end
            elseif r.kind=="chest" or r.kind=="where" then
                local nameW=math.min(w>=40 and 18 or 10,math.max(6,w-16))
                local tail=r.kind=="where" and short(r.c) or string.format("%3d%%",num(r.p))
                local barX=nameW+3
                local barW=w-barX-#tail-1
                text(2,yy,r.label:sub(1,nameW),colors.white)
                if r.kind=="chest" and barW>=3 then thinBar(text,barX,yy,barW,num(r.p)/100,fillColor(r.p,r.warn),colors.black)
                elseif r.kind=="where" and r.p and barW>=3 then thinBar(text,barX,yy,barW,num(r.p)/100,fillColor(r.p,90),colors.black) end
                right(yy,tail,r.kind=="chest" and fillColor(r.p,r.warn) or colors.white)
            elseif r.kind=="item" then
                local cnt=short(r.c)
                local loc=(w>=44 and r.first) and tostring(r.first) or nil
                local nameW=w-#cnt-2-(loc and (#loc+2) or 0)
                text(1,yy,r.label:sub(1,nameW),colors.white)
                if loc then text(w-#cnt-#loc-2,yy,loc,colors.gray) end
                right(yy,cnt,colors.lightGray)
                ui.buttons[#ui.buttons+1]={x=1,y=yy,w=w,action="sitem:"..r.id,enabled=true}
            else text(1,yy,r.label:sub(1,w),colors.lightGray) end
        end
        -- Fusszeile
        if pages>1 then
            local pw=math.max(4,math.floor(w/6))
            pill(1,h,pw,"\27","pageprev",colors.gray,ui.page>1,colors.white)
            pill(w-pw+1,h,pw,"\26","pagenext",colors.gray,ui.page<pages,colors.white)
            local m=ui.page.."/"..pages
            text(math.floor((w-#m)/2)+1,h,m,colors.lightGray)
        else
            local info=tostring(notice or "")
            if info:find("Warte auf",1,true) or info:find("bestaetigt",1,true) or info:find("Verbunden",1,true) then info="" end
            if info=="" then
                info=ui.storeItem and "Zurueck: Pfeil links / Backspace"
                    or (ui.storeView=="items" and (ui.kbd and "Tippen = suchen, Item = wo liegt es" or "Item antippen = wo liegt es")
                    or (w>=30 and "Orange = fast voll, Rot = voll" or "Orange fast voll, Rot voll"))
            end
            local ver=" v"..common.version
            if #info+#ver<=w then text(1,h,info,colors.lightGray);text(w-#ver+1,h,ver,colors.gray)
            else text(1,h,info:sub(1,w),colors.lightGray) end
        end
    end
    function ui.drawNet(nodes,link,text,right,fill,pill,w,h,notice)
        local ids=nodes.ids
        ui.ids=ids
        if ui.selected and not common.contains(ids,ui.selected) then ui.selected=nil end
        if ui.cursor and not common.contains(ids,ui.cursor) then ui.cursor=nil end
        if not ui.cursor then ui.cursor=ui.selected or ids[1] end
        local function coords(d)
            local p=d and d.pos;if type(p)~="table" then return nil end
            return "X"..num(p.x).." Y"..num(p.y).." Z"..num(p.z)
        end
        local foot=h-1
        local sel=ui.selected and nodes.entries[ui.selected]
        if sel then
            local d=sel.data or {}
            local name=(sel.label~="" and sel.label or NODE_NAMES[sel.role] or "Geraet").." #"..ui.selected
            pill(1,3,math.min(w,#name+(w>=30 and 14 or 4)),(w>=30 and "\27 Zurueck  " or "\27 ")..name,"group",colors.gray,true)
            local kind=sel.online and "done" or "off"
            fill(4,COLOR[kind])
            text(2,4,sel.online and "Online" or "Offline - keine Meldung seit 30 s",colors.black,COLOR[kind])
            local rows={{"Typ",NODE_NAMES[sel.role] or tostring(sel.role)},
                {"Version",tostring(d.toast)..((d.toast and d.toast~=common.version) and (" (Zentrale "..common.version..")") or "")}}
            local c=coords(d)
            rows[#rows+1]={"Koordinaten",c and (c..(d.pos.src and (" "..d.pos.src) or "")) or "unbekannt"}
            local st=d.stats or {}
            if st.gps then rows[#rows+1]={"GPS-Anfragen",short(st.gps)} end
            if st.repeated then rows[#rows+1]={"Weitergeleitet",short(st.repeated).." Nachrichten"} end
            local y=6
            for _,r in ipairs(rows) do if y<foot then text(1,y,r[1],colors.lightGray);text(15,y,r[2],colors.white);y=y+1 end end
        else
            local y=3
            if #ids==0 then
                text(1,y+1,"Keine Netzgeraete gemeldet.",colors.lightGray)
                text(1,y+2,"Repeater/GPS-Sender melden sich",colors.lightGray)
                text(1,y+3,"nach dem Update auf 3.4 selbst.",colors.lightGray)
            end
            local avail=foot-y
            for row=1,avail do
                local id=ids[row];if not id then break end
                local e=nodes.entries[id];local d=e.data or {}
                local yy=y+row-1
                local mark=ui.kbd and id==ui.cursor
                local bg=mark and colors.gray or colors.black
                text(1,yy,string.rep(" ",w),colors.white,bg)
                text(1,yy,mark and "\16" or "\7",e.online and colors.lime or colors.gray,bg)
                local name=e.label~="" and e.label or ((NODE_NAMES[e.role] or "Geraet").." #"..id)
                local typ=NODE_NAMES[e.role] or e.role
                local c=coords(d)
                if w>=60 then
                    text(3,yy,name:sub(1,24),e.online and colors.white or colors.gray,bg)
                    text(29,yy,typ,colors.lightGray,bg)
                    if c then text(42,yy,c,colors.lightGray,bg) end
                    right(yy,(e.online and "" or "Offline ").."v"..tostring(d.toast),e.online and colors.lightGray or colors.gray,bg)
                else
                    text(3,yy,name:sub(1,w-13),e.online and colors.white or colors.gray,bg)
                    right(yy,e.online and typ:sub(1,10) or "Offline",e.online and colors.lightGray or colors.gray,bg)
                end
                ui.buttons[#ui.buttons+1]={x=1,y=yy,w=w,action="id:"..id,enabled=true}
            end
        end
        local info=tostring(notice or "")
        if info:find("Warte auf Geraete",1,true) or info:find("bestaetigt",1,true) then info="" end
        if info=="" then info=sel and "Update oben aktualisiert alle Geraete" or "Tippen = Details, Position, Version" end
        local ver=" v"..common.version
        if #info+#ver<=w then info=info..string.rep(" ",w-#info-#ver) end
        text(1,h,info:sub(1,w),colors.lightGray)
        if #info+#ver<=w+#ver and #info<=w-#ver then text(w-#ver+1,h,ver,colors.gray) end
    end
    local function indexOf(id) for i,v in ipairs(ui.ids) do if v==id then return i end end return 0 end
    function ui.action(a)
        if not a then return end
        if a~="reset" and a~="update" then ui.confirm=nil end
        if a=="redraw" then return
        elseif type(a)=="string" and (a:match("^rc:") or a:match("^cf:")) then return ui.remoteAction(a)
        elseif a=="dm:toggle" then ui.driveMode=ui.driveMode=="build" and "use" or "build";return
        elseif a=="dv:info" then ui.detailView=nil;return
        elseif a=="dv:drive" then ui.detailView="drive";return
        elseif a=="dv:config" then
            ui.detailView="config";ui.cfgSel=nil;ui.cfgScroll=0
            if ui.selected then return {id=ui.selected,payload={op="getconfig"}} end
            return
        elseif a=="chests" then ui.detailView=ui.detailView~="chests" and "chests" or nil;ui.chestView=ui.detailView=="chests";ui.chestScroll=0;return
        elseif a=="cup" or a=="cdown" or (ui.chestView and ui.selected and (a=="up" or a=="down" or a=="pageprev" or a=="pagenext")) then
            local d=(a=="cup" or a=="up" or a=="pageprev") and -2 or 2
            if a=="pageprev" or a=="pagenext" then d=d*4 end
            ui.chestScroll=math.max(0,math.min(ui.chestMax or 0,(ui.chestScroll or 0)+d));return
        elseif a:match("^sview:") then ui.storeView=a:sub(7);ui.storeItem=nil;ui.page=1;return
        elseif a:match("^sitem:") then ui.storeItem=a:sub(7);ui.page=1;return
        elseif a=="sback" then ui.storeItem=nil;return
        elseif ui.filter=="store" and (a=="up" or a=="down") then
            if a=="up" then ui.page=math.max(1,(ui.page or 1)-1) else ui.page=math.min(ui.storePages or 1,(ui.page or 1)+1) end
            return
        elseif ui.filter=="store" and a=="group" then
            if ui.storeItem then ui.storeItem=nil elseif (ui.search or "")~="" then ui.search=ui.search:sub(1,-2);ui.page=1 end
            return
        elseif a=="help" then ui.help=not ui.help
        elseif a:match("^filter:") then ui.filter=a:sub(8);ui.selected=nil;ui.page=1;ui.cursor=nil
        elseif a:match("^id:") then ui.selected=tonumber(a:sub(4));ui.cursor=ui.selected;ui.chestView=nil;ui.detailView=nil
        elseif a=="group" then
            if ui.detailView then ui.detailView=nil;ui.chestView=nil;return end
            ui.cursor=ui.selected or ui.cursor;ui.selected=nil;ui.followCursor=true
        elseif a=="pageprev" then ui.page=math.max(1,ui.page-1)
        elseif a=="pagenext" then ui.page=math.min((ui.filter=="store" and ui.storePages) or ui.pages or 1,ui.page+1)
        elseif a=="tabprev" or a=="tabnext" then
            local TABS=ui.tabs or {"all","farm","mining"}
            local i=1;for k,t in ipairs(TABS) do if t==ui.filter then i=k end end
            i=(i-1+(a=="tabnext" and 1 or -1))%#TABS+1
            return ui.action("filter:"..TABS[i])
        elseif a=="up" or a=="down" then
            if #ui.ids==0 then return end
            local i=indexOf(ui.selected or ui.cursor)
            if i==0 then i=a=="down" and 1 or #ui.ids else i=math.max(1,math.min(#ui.ids,i+(a=="down" and 1 or -1))) end
            ui.cursor=ui.ids[i];ui.followCursor=true
            if ui.selected then ui.selected=ui.cursor end
        elseif a=="first" or a=="last" then
            if #ui.ids==0 then return end
            ui.cursor=ui.ids[a=="first" and 1 or #ui.ids];ui.followCursor=true
            if ui.selected then ui.selected=ui.cursor end
        elseif a=="open" then
            if not ui.selected and ui.cursor and indexOf(ui.cursor)>0 then ui.selected=ui.cursor end
        elseif a=="next" or a=="prev" then
            local index=indexOf(ui.selected)
            index=(index+(a=="next" and 1 or -1))%(#ui.ids+1)
            ui.selected=ui.ids[index];if ui.selected then ui.cursor=ui.selected end
        elseif a=="reset" or a=="update" then
            -- Sicherheitsabfrage: zweimal innerhalb von 5 s druecken/tippen
            if confirming() and ui.confirm.action==a then ui.confirm=nil;return a end
            ui.confirm={at=os.clock(),action=a};return
        else return a end
    end
    -- Tastatur: Sondertasten (Name aus keys.getName) und Zeichen
    local KEYS={up="up",down="down",enter="open",numPadEnter="open",space="open",backspace="group",
        tab="tabnext",pageUp="pageprev",pageDown="pagenext",home="first",["end"]="last"}
    function ui.key(name)
        if not name then return end
        ui.kbd=true
        if ui.help then ui.help=false;return "redraw" end
        if ui.selected and ui.detailView=="drive" then
            local K={up="rc:forward",down="rc:back",left="rc:left",right="rc:right",pageUp="rc:up",pageDown="rc:down",
                space="rc:use",leftShift="rc:down",rightShift="rc:down",leftCtrl="rc:useDown",tab="dm:toggle"}
            if K[name] then return K[name] end
            if name=="backspace" then return "group" end
        end
        if ui.selected and ui.detailView=="config" then
            local tf=cfgTextField()
            if name=="backspace" and tf then
                local v=tostring(tf.value or "");if #v>0 then cfgSet(tf,v:sub(1,-2));return "redraw" end
                return "group"
            end
            if name=="up" or name=="down" then
                local L=ui.cfgLinesCache or {};local i=ui.cfgSel or 1
                repeat i=i+(name=="down" and 1 or -1) until not L[i] or L[i].kind~="title"
                if L[i] then ui.cfgSel=i end
                return "redraw"
            end
            if name=="left" then return "cf:opt:-1" end
            if name=="right" then return "cf:opt:1" end
            if name=="enter" then return "cf:toggle" end
        end
        if ui.filter=="store" and name=="left" and ui.storeItem then return "sback" end
        if ui.filter=="store" and ui.storeOnly and (name=="left" or name=="right" or name=="tab") then
            return "sview:"..(ui.storeView=="items" and "chests" or "items")
        end
        if name=="left" then return ui.selected and "group" or "tabprev" end
        if name=="right" then return ui.selected and nil or "tabnext" end
        local a=KEYS[name]
        if ui.selected and (a=="pageprev" or a=="pagenext") then return a=="pageprev" and "up" or "down" end
        return a
    end
    function ui.char(ch)
        if not ch then return end
        ui.kbd=true
        if ui.help then ui.help=false;return "redraw" end
        if ui.selected and ui.detailView=="drive" then
            local K={w="rc:forward",s="rc:back",a="rc:left",d="rc:right",e="rc:up",c="rc:down",r="rc:useUp",f="rc:useDown",
                b="dm:toggle",t="rc:nextblock",[" "]="redraw"}           -- Leertaste kommt schon als Taste (space)
            if K[ch:lower()] then return K[ch:lower()] end
            return "redraw"               -- andere Tasten im Steuermodus nicht als Befehle (z.B. R = Reset)
        end
        local tf=cfgTextField()
        if tf and ch:match("^[%w _,%.:%-]$") then cfgSet(tf,(tostring(tf.value or "")..ch):sub(1,48));return "redraw" end
        if ui.selected and ui.detailView=="config" then
            if ch=="+" then return "cf:add:1" elseif ch=="-" then return "cf:add:-1" end
        end
        if ui.filter=="store" and ch:match("^[%w _%-]$") then
            -- Lager: Buchstaben = Suche im Inhalt
            ui.search=((ui.search or "")..ch:lower()):sub(1,24);ui.storeView="items";ui.storeItem=nil;ui.page=1
            return "redraw"
        end
        return ui.keys[ch:lower()] or ui.keys[ch]
    end
    function ui.target() return ui.selected or ui.filter end
    function ui.click(x,y)
        for i=#ui.buttons,1,-1 do
            local b=ui.buttons[i]
            if b.enabled and y==b.y and x>=b.x and x<b.x+b.w then return b.action end
        end
    end
    ui.keys={k="chests",["0"]="group",["1"]="start",["2"]="stop",["3"]="once",["4"]="reset",
        s="start",x="stop",e="once",r="reset",h="help",["?"]="help",u="update",
        a="filter:all",f="filter:farm",m="filter:mining"}
    return ui
end
-- fuer Tests: Detailzeilen einer Aufgabe
function M.jobRows(job,d) local j=JOB[job];return j and j.rows and j.rows(d) end
return M
