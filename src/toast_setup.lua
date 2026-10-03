-- Toast Control: Einstellungsmenue (Installer und "toast.lua config").
-- Eine Uebersicht mit Nummern; Nummer = aendern, Enter = fertig.
local S={}
function S.new(common)
    local M={}
    local W=({term.getSize()})[1]
    local color=term.isColor and term.isColor()
    local function fg(c) if color then term.setTextColor(c) end end
    local function cut(s) return tostring(s):sub(1,W) end
    local function header(sub)
        term.setBackgroundColor(colors.black);term.clear();term.setCursorPos(1,1)
        fg(colors.cyan);print(cut("TOAST SETUP "..common.version));fg(colors.lightGray);print(cut(sub));fg(colors.white)
    end
    local function hint(s) fg(colors.lightGray);print(cut(s));fg(colors.white) end
    local function ask(label,default,lo,hi)
        while true do
            write(cut(label.." ["..tostring(default).."]: "))
            local v=read()
            if v=="" then return default end
            local n=tonumber(v)
            if n and n%1==0 and n>=lo and n<=hi then return n end
            fg(colors.orange);print(cut("  Bitte "..lo.." bis "..hi));fg(colors.white)
        end
    end
    local function askText(label,default)
        write(cut(label..(default~="" and " ["..default.."]" or "")..": "))
        local v=read()
        if v=="" then return default end
        if v=="-" then return "" end
        return common.label(v)
    end
    local function yesno(label,default)
        while true do
            write(cut(label.." (j/n) ["..(default and "j" or "n").."]: "))
            local v=read():lower()
            if v=="" then return default end
            if v=="j" or v=="ja" or v=="y" then return true end
            if v=="n" or v=="nein" then return false end
        end
    end
    local function askSide(label,default)
        while true do
            write(cut(label.." r/l ["..(default=="left" and "l" or "r").."]: "))
            local v=read():lower()
            if v=="" then return default or "right" end
            if v=="r" or v=="rechts" or v=="right" then return "right" end
            if v=="l" or v=="links" or v=="left" then return "left" end
        end
    end
    local function sideName(s) return s=="left" and "links" or "rechts" end
    local showText,editShow
    -- ---- Zusammenfassungen ----
    local function mineText(m)
        return m.length.."x"..m.height.."x"..m.tunnels.." Abst."..m.gap.." "..sideName(m.side)
            ..(m.sideDig and m.gap==0 and " +seitl" or "")..(m.useCoal~=false and " +Kohle" or "")
    end
    local function farmText(f)
        return f.length.."x"..f.width.." "..sideName(f.side).." "..(common.CROP_NAMES[f.crop] or f.crop)
    end
    local function chunkText(cl)
        if not cl.enabled then return "aus" end
        return cl.chunks.."  -"..common.chunkFuelPerHour(cl.chunks).." Fuel/h"..(cl.idle and " +Basis" or "")
    end
    local function radioText(t) return t==0 and "ohne Zentrale weiter" or ("Stopp nach "..t.." s") end
    -- ---- Bearbeiten ----
    local function editMine(c)
        local m=c.mine
        header("Mine (von der Basis aus nach vorne)")
        hint("Enter = Wert behalten")
        m.length=ask("Laenge (1-1024)",m.length,1,1024)
        m.height=ask("Hoehe (1-64, 3/6/9 sparsam)",m.height,1,64)
        m.tunnels=ask("Gaenge (1-64)",m.tunnels,1,64)
        if m.tunnels>1 then
            m.gap=ask("Abstand (0-16)",m.gap,0,16)
            m.side=askSide("Gaenge nach",m.side)
            if m.gap==0 then
                hint("Seitlich mitabbauen: weniger Fuel,")
                hint("dafuer langsamer.")
                m.sideDig=yesno("Seitlich mitabbauen?",m.sideDig==true)
            else m.sideDig=false end
        else m.sideDig=false end
        hint("Kohle aus der Mine: direkt verbrennen")
        hint("(spart Fahrten) oder abliefern.")
        m.useCoal=yesno("Gefundene Kohle als Fuel nutzen?",m.useCoal~=false)
    end
    local function editFarm(c)
        local f=c.farm
        header("Feld (von der Basis aus nach vorne)")
        hint("Enter = behalten. Wasser wird erkannt.")
        f.length=ask("Laenge (1-32)",f.length,1,32)
        f.width=ask("Breite (1-32)",f.width,1,32)
        if f.width>1 then f.side=askSide("Feld nach",f.side) end
        local crops={"wheat","carrots","potatoes","beetroot"}
        local cur=1;for i,v in ipairs(crops) do if v==f.crop then cur=i end end
        hint("1 Weizen 2 Karotten 3 Kartoffeln 4 Rote Bete")
        f.crop=crops[ask("Pflanze",cur,1,4)]
        f.interval=ask("Pause zwischen Runden (s)",f.interval,1,86400)
        hint("Saatgut aus der Ernte wird behalten.")
        hint("0 = automatisch passend zum Feld")
        f.seedReserve=ask("Saatgut behalten (0-256)",f.seedReserve or 0,0,256)
        f.water={}
    end
    local function editChunks(c,job)
        local cl=c.chunkload
        header("Chunks laden (Mod CCChunkloader)")
        hint("0 = aus")
        for _,n in ipairs({1,9,21}) do
            local fph=common.chunkFuelPerHour(n)
            hint(n.." = ~"..fph.." Fuel/h (~"..math.ceil(fph/80).." Kohle/h)")
        end
        local wasOn=cl.enabled
        local cur=cl.enabled and cl.chunks or 0
        while true do
            local n=ask("Chunks",cur,0,21)
            if n==0 then cl.enabled=false;break end
            if common.CHUNK_RADIUS[n] then cl.enabled=true;cl.chunks=n;break end
            fg(colors.orange);print("  0, 1, 9 oder 21");fg(colors.white)
        end
        if cl.enabled then
            hint("Auch an der Basis geladen lassen?")
            hint("Noetig, damit sie START hoert, wenn")
            hint("niemand in der Naehe ist (z.B. Nether)")
            cl.idle=yesno("An der Basis wach",(not wasOn) or cl.idle==true)
            hint("Anbau: Chunkloader + "..(job=="farm" and "Werkzeug" or "Spitzhacke"))
            hint("Funkmodem ins Turtle-Inventar legen.")
            sleep(1.5)
        end
    end
    local function editRadio(c,job)
        local sec=job=="farm" and c.farm or c.mine
        header("Funk")
        hint("Keine Verbindung zur Zentrale:")
        hint("nach x Sekunden stoppen + heimfahren.")
        hint("0 = trotzdem weiterarbeiten")
        while true do
            local t=ask("Sekunden (0, 10-300)",sec.radioTimeout,0,300)
            if t==0 or t>=10 then sec.radioTimeout=t;break end
        end
    end
    local function editMonitor(c,role)
        local d=c.display
        local kind=role=="info" and "info" or "control"
        header(role=="info" and "Bildschirm des Infoscreens" or "Bildschirm der Zentrale")
        hint("Monitor: auto = Advanced Monitor suchen,")
        hint("terminal = Computerbildschirm")
        local names={}
        for _,n in ipairs(peripheral.getNames()) do if peripheral.getType(n)=="monitor" then names[#names+1]=n end end
        if #names>0 then hint("Gefunden: "..table.concat(names,", ")) end
        write(cut("Monitor ["..d.monitor.."]: "))
        local v=read();if v~="" then d.monitor=v end
        hint("Groesse in Bloecken: Hoehe x Breite")
        hint("z.B. 3x4 (max 6x8), auto = ausmessen")
        while true do
            write(cut("Groesse ["..tostring(d.size).."]: "))
            local sv=read():lower():gsub("%s","")
            if sv=="" then sv=d.size end
            if sv=="auto" or common.parseSize(sv) then d.size=sv;break end
            fg(colors.orange);print("  z.B. 3x4 oder auto");fg(colors.white)
        end
        if d.size~="auto" then
            local s,w,h=common.scaleFor(d.size,kind)
            hint("-> Schrift "..s..", "..w.." x "..h.." Zeichen")
        end
        sleep(1.5)
    end
    function showText(v)
        if type(v)=="number" then return "Turtle #"..v end
        return ({all="Alle Turtles",farm="Alle Farmen",mining="Alle Minen"})[v] or tostring(v)
    end
    function editShow(c)
        header("Was soll der Infoscreen zeigen?")
        print("")
        hint("1 Alle Turtles")
        hint("2 Alle Farmen")
        hint("3 Alle Minen")
        hint("4 Eine bestimmte Turtle")
        local cur=c.show=="farm" and 2 or c.show=="mining" and 3 or type(c.show)=="number" and 4 or 1
        local n=ask("Auswahl",cur,1,4)
        if n==1 then c.show="all" elseif n==2 then c.show="farm" elseif n==3 then c.show="mining"
        else
            hint("ID steht an der Zentrale hinter dem Namen")
            hint("(z.B. Mine Nord #12 -> 12)")
            c.show=ask("Turtle-ID",type(c.show)=="number" and c.show or 1,0,65500)
        end
    end
    local function editDevices(c)
        header("Geraete")
        c.autoDiscover=yesno("Neue Turtles automatisch aufnehmen?",c.autoDiscover)
        c.autoPairPockets=yesno("Neue Pockets automatisch aufnehmen?",c.autoPairPockets)
    end
    local function editController(c)
        header("Zentrale")
        while true do
            local id=ask("ID der Zentrale",c.controllerId,0,65500)
            if id==os.getComputerID() and c.controllerId==id then break end
            if id~=os.getComputerID() then c.controllerId=id;break end
            fg(colors.orange);print("  Das ist die eigene ID.");fg(colors.white)
        end
    end
    local function items(c,info)
        local role,job=info.role,info.job
        local list={{"Name",function() return c.name~="" and c.name or "-" end,function()
            header("Name");hint("Leer lassen = behalten, - = loeschen")
            c.name=askText("Name",c.name);c.label=c.name end}}
        if role~="controller" and role~="repeater" then
            list[#list+1]={"Zentrale",function() return "#"..c.controllerId end,function() editController(c) end}
        end
        if role=="turtle" and job=="mining" then
            list[#list+1]={"Mine",function() return mineText(c.mine) end,function() editMine(c) end}
        elseif role=="turtle" then
            list[#list+1]={"Feld",function() return farmText(c.farm) end,function() editFarm(c) end}
        end
        if role=="turtle" then
            list[#list+1]={"Chunks",function() return chunkText(c.chunkload) end,function() editChunks(c,job) end}
            list[#list+1]={"Funk",function() return radioText((job=="farm" and c.farm or c.mine).radioTimeout) end,
                function() editRadio(c,job) end}
        end
        if role=="controller" or role=="info" then
            list[#list+1]={"Monitor",function() return (c.display.monitor=="auto" and "" or (c.display.monitor.." "))
                ..(c.display.size=="auto" and "Groesse auto" or (tostring(c.display.size).." Bloecke"))
                end,
                function() editMonitor(c,role) end}
        end
        if role=="info" then
            list[#list+1]={"Anzeige",function() return showText(c.show) end,function() editShow(c) end}
        end
        if role=="controller" then
            list[#list+1]={"Geraete",function() return (c.autoDiscover and "Turtles auto" or "Turtles fest")..", "
                ..(c.autoPairPockets and "Pockets auto" or "Pockets fest") end,function() editDevices(c) end}
        end
        return list
    end
    -- Uebersicht; true = uebernehmen, false = abbrechen
    function M.run(c,info)
        local what=info.role=="turtle" and ("Turtle #"..os.getComputerID().." / "..(info.job=="farm" and "Farm" or "Mining"))
            or (({controller="Zentrale",pocket="Pocket",repeater="Repeater",info="Infoscreen"})[info.role].." #"..os.getComputerID())
        while true do
            local list=items(c,info)
            header(what)
            print("")
            for i,it in ipairs(list) do
                fg(colors.yellow);write(i.." ");fg(colors.white)
                write(string.format("%-9s",it[1]))
                fg(colors.lightGray);print(tostring(it[2]()):sub(1,math.max(1,W-12)));fg(colors.white)
            end
            print("")
            hint("Nummer = aendern, Enter = "..(info.installer and "weiter" or "speichern")
                ..(info.installer and "" or ", q = Abbruch"))
            write("> ")
            local v=read()
            if v=="" then return true end
            if v:lower()=="q" and not info.installer then return false end
            local n=tonumber(v)
            if n and list[n] then list[n][3]() end
        end
    end
    -- Neue Minenmasse bei vorhandenem Fortschritt -> neuer Auftrag (Turtle an der Basis)
    function M.layoutKey(c,job)
        if job=="mining" then local m=c.mine
            return table.concat({m.length,m.height,m.tunnels,m.gap,m.side,tostring(m.sideDig==true)},":") end
        if job=="farm" then local f=c.farm return table.concat({f.length,f.width,f.side,f.crop},":") end
        return ""
    end
    function M.confirmReset(job)
        if job~="mining" then return end
        local file="/toast_mining_state"
        if not (fs.exists(file) or fs.exists(file..".tmp")) then return end
        header("Neue Minenmasse")
        print("Neue Masse = neuer Auftrag.")
        print("Die Turtle muss an ihrer Basis stehen")
        print("(Blick in die Mine).")
        if yesno("Steht sie an der Basis?",true) then
            for _,p in ipairs({file,file..".tmp"}) do if fs.exists(p) then fs.delete(p) end end
            return true
        end
        printError("Erst an die Basis stellen, dann: toast.lua --dock --new")
        sleep(2)
    end
    M.yesno=yesno;M.header=header;M.hint=hint;M.ask=ask
    return M
end
return S
