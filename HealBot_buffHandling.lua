--==============================================================================
--[[
    Author: Ragnarok.Lorand
    HealBot buff handling functions
--]]
--==============================================================================

local buffs = {
    debuffList = {},
    buffList = {},
    ignored_debuffs = {},
	gaol_auras = S{146,147,148,149,167,174,175,404}, -- [DOWN] Acc,Atk,Eva,Def,M. Def.,M. Acc.,M. Atk.,M. Eva. 
	perm_ignored_debuffs = S{137,138,139,140,141,142,540,557,558,559,560,561,562,563,564,565,566,567}, -- Stats down [not STR] / Geomancy effects
    action_buff_map = lor_settings.load('data/action_buff_map.lua'),
	auras = {},
	dispel_table = {}
}
local lc_res = _libs.lor.resources.lc_res
local ffxi = _libs.lor.ffxi

--==============================================================================
--          Local Player Buff Checking
--==============================================================================

function buffs.checkOwnBuffs()
    local player = windower.ffxi.get_player()
    if player ~= nil then
        buffs.review_active_buffs(player, player.buffs)
    end
end


function buffs.review_active_buffs(player, buff_list)
    if buff_list ~= nil then
        --Register everything that's actually active
        for _,bid in pairs(buff_list) do
            local buff = res.buffs[bid]
            if (enfeebling:contains(bid)) then
                buffs.register_debuff(player, buff, true)
            else
                buffs.register_buff(player, buff, true)
            end
        end
        
        --Double check the list of what should be active
        local checklist = buffs.buffList[player.name] or {}
        local active = S(buff_list)
        for bname,binfo in pairs(checklist) do
            if binfo.is_geo or binfo.is_indi then
                if binfo.is_geo and binfo.action then
                    local pet = windower.ffxi.get_mob_by_target('pet')
                    healer.geo.latest = healer.geo.latest or {}
                    if pet == nil then
                        buffs.register_buff(player, healer.geo.latest, false)
                    else
                        buffs.register_buff(player, healer.geo.latest, true)
                    end
                elseif binfo.is_indi and binfo.action then
                    healer.indi.info = healer.indi.info or {}
                    healer.indi.latest = healer.indi.latest or {}
                    buffs.register_buff(player, healer.indi.latest, healer.indi.info.active)
                end
            else
                if binfo.buff then                                              -- FIXME: Temporary fix for geo error
                    if not active:contains(binfo.buff.id) then
                        buffs.register_buff(player, res.buffs[binfo.buff.id], false)
                    end
                end
            end
        end
		checklist = buffs.debuffList[player.name] or {}
        for bname,binfo in pairs(checklist) do
            if not active:contains(bname) then
                buffs.register_debuff(player, res.buffs[bname], false)
            end
        end
		checklist = buffs.auras[player.name] or {}
        for bname,binfo in pairs(checklist) do
            if not active:contains(bname) then
				buffs.remove_debuff_aura(player.name,bname)
            end
        end
    end
end


--==============================================================================
--          Monitored Player Buff Checking
--==============================================================================


function buffs.getBuffQueue()
    local player = windower.ffxi.get_player()
    local activeBuffIds = S(player.buffs)
    local bq = ActionQueue.new()
    local now = os.clock()
    for targ, buffset in pairs(buffs.buffList) do
        for spell_name, info in pairs(buffset) do
            if (targ == healer.name) and (info.buff) then       -- FIXME: and info.buff = temp fix for geo issue
                if activeBuffIds:contains(info.buff.id) then
                    buffs.register_buff(player, res.buffs[info.buff.id], true)
                end
            end
            if (info.landed == nil) then
                if (info.attempted == nil) or ((now - info.attempted) >= 3) then
                    bq:enqueue('buff', info.action, targ, spell_name, info.status)
                end
            end
        end
    end
    return bq:getQueue()
end


function buffs.getDebuffQueue()
    local dbq = ActionQueue.new()
    local now = os.clock()
    for targ, debuffs in pairs(buffs.debuffList) do
		for id, info in pairs(debuffs) do
			if info.aura == 'no' then
				local debuff = res.buffs[id]
				local removalSpellName = buffs.handle_removalSpellName(healer, id, targ)
				atcd(123,'Removal debuff enqueue -  ID: ' .. id .. ' Target: ' .. targ)
				if (removalSpellName ~= nil) then
					if (info.attempted == nil) or ((now - info.attempted) >= 3) then
						local spell = removalSpellName
						if healer:can_use(spell) and ffxi.target_is_valid(spell, targ) then
							 -- handle AoE
							spell.accession = false
							if settings.aoe_na then
								local numAccessionRange = buffs.getRemovableDebuffCountAroundTarget(targ, 10, id)
								if numAccessionRange >= 3 and accessionable:contains(spell.en) then
									spell.accession = true
								end
							end
							-- handle ignores
							-- local ign = buffs.ignored_debuffs[debuff.en]
							-- if not buffs.perm_ignored_debuffs:contains(tonumber(id)) and not ((ign ~= nil) and ((ign.all == true) or ((ign[targ] ~= nil) and (ign[targ] == true)))) then
								-- dbq:enqueue('debuff', spell, targ, debuff, ' ('..debuff.en..')')
							-- end
							
							-- handle ignores
							local ign = buffs.ignored_debuffs[debuff.en]
							if not buffs.perm_ignored_debuffs:contains(tonumber(id)) and (ign == nil or not (ign.all == true or (ign[targ] ~= nil and ign[targ] == true))) then
								dbq:enqueue('debuff', spell, targ, debuff, ' ('..debuff.en..')')
							end

						end
					end
				else
					if not (S{2,19,193,14,17}:contains(id)) then
						buffs.debuffList[targ][id] = nil
					end
				end
			end -- if aura
		end -- for
    end -- for
    return dbq:getQueue()
end -- function

--Handle removal spells for jobs
function buffs.handle_removalSpellName(healer, id, targ)
	local aoe_action, single_action, debuff_map_type, removalActionName, ja_action, ma_action, sleep_spell

	if healer.main_job == 'DNC' or (healer.sub_job == 'DNC' and not (S{'WHM','SCH'}:contains(healer.main_job))) then
		aoe_action = res.job_abilities[195]
		single_action = res.job_abilities[190]
		debuff_map_type = dnc_debuff_map_id
		ja_action = true
	else
		aoe_action = res.spells[7]
		single_action = res.spells[1]
		debuff_map_type = debuff_map_id
		ma_action = true
	end
	
	if S{'BLM','RDM','DRK','GEO'}:contains(healer.main_job) then
		sleep_spell = res.spells[259]	-- Sleep II
	elseif healer.main_job == 'BRD' then
		sleep_spell = res.spells[471]	-- Foe Lullaby II
	elseif healer.main_job == 'WHM' then
		sleep_spell = res.spells[98]	-- Repose
	else -- Other subjobs
		if S{'BLM','RDM','DRK'}:contains(healer.sub_job) then
			sleep_spell = res.spells[259]	-- Sleep II
		elseif healer.sub_job == 'GEO' then
			sleep_spell = res.spells[253]	-- Sleep
		end
	end
	
	-- Check tables for debuff id
	for list, category in debuff_map_type:it() do
		if list:contains(tonumber(id)) then
			removalActionName = tostring(category)
		end
	end

	local debuff_table = buffs.debuffList[targ]
	if removalActionName == 'Charmed' and not (debuff_table[2] or debuff_table[19] or debuff_table[193]) then
		return (healer:can_use(sleep_spell) and sleep_spell) or nil
	elseif removalActionName == 'Asleep' and not (debuff_table[14] or debuff_table[17]) then
		return (healer:can_use(aoe_action) and aoe_action) or (healer:can_use(single_action) and single_action) or nil
	else
		return (ja_action and removalActionName and res.job_abilities:with('en', removalActionName)) or (ma_action and removalActionName and res.spells:with('en', removalActionName)) or nil
	end
end

--==============================================================================
--          Input Handling Functions
--==============================================================================


function buffs.registerNewBuff(args, use, job_name_flag, status)
    local targetName = args[1] and args[1] or ''
    table.remove(args, 1)
    local arg_string = table.concat(args,' ')
    local snames = arg_string:split(',')
	local status = status or "Always"
	
	if job_name_flag then
		if utils.getPlayerNameFromJob(targetName) then
			table.insert(args,1,utils.getPlayerNameFromJob(targetName))
			buffs.registerNewBuff(args, use)
		else
			atc('Unable to find buff JOB target: '..targetName:upper())
		end
		return
	end
	
    for index,sname in pairs(snames) do
        if (tostring(index) ~= 'n') then
            buffs.registerNewBuffName(targetName, sname:trim(), use, status)
        end
    end
end


function buffs.registerNewBuffName(targetName, bname, use, status)

    if bname:lower() ~= 'all' then
		spellName = utils.formatActionName(bname)
	end
    if (spellName == nil and targetName:lower() ~= 'everyone' and bname:lower() ~= 'all') then
        atc('Error: Unable to parse spell name')
        return
    end
	
    local me = windower.ffxi.get_player()
    local target = ffxi.get_target(targetName)
    if target == nil and targetName:lower() ~= 'everyone' then
        atc('Unable to find buff target: '..targetName)
        return
    end
    local action = buffs.getAction(spellName, target)
    if (action == nil and targetName:lower() ~= 'everyone' and bname:lower() ~= 'all') then
		atc('Unable to cast or invalid: '..spellName)
		return
    end
	
	-- Song override, no check targets.
    if target and action and not ffxi.target_is_valid(action, target) and targetName:lower() ~= 'everyone' and bname:lower() ~= 'all' then
		if not (spells_songBuffs:contains(res.spells:with('en', spellName).id)) then
			atc(target.name..' is an invalid target for '..action.en)
			return
		else
			atc(122, 'Bypassing check for invalid target on songs!')
		end
    end
    
    local monitoring = hb.getMonitoredPlayers()
    if (target and not (monitoring[target.name])) then
        monitorCommand('watch', target.name)
    end
   
	if target and action then
		buffs.buffList[target.name] = buffs.buffList[target.name] or {}
		buff = buffs.buff_for_action(action)
		buff.status = status
	end
    
    if (buff == nil and targetName:lower() ~= 'everyone' and bname:lower() ~= 'all') then
        atc('Unable to match the buff name to an actual buff: '..bname)
        return
    end
    
    if use then
		for spell_check,_ in pairs (buffs.buffList[target.name]) do
			if buffs_opposing:contains(spell_check) then
				for opposing_spell,_ in pairs (buffs.buffList[target.name]) do
					if spells_storms:contains(opposing_spell) and spells_storms:contains(action.en) and opposing_spell ~= action.en then
						atc('Removing opposing storm buff: '..opposing_spell)
						buffs.buffList[target.name][opposing_spell] = nil
					elseif spells_boost:contains(opposing_spell) and spells_boost:contains(action.en) and opposing_spell ~= action.en then
						atc('Removing opposing boost buff: '..opposing_spell)
						buffs.buffList[target.name][opposing_spell] = nil
					elseif spells_gain:contains(opposing_spell) and spells_gain:contains(action.en) and opposing_spell ~= action.en then
						atc('Removing opposing gain buff: '..opposing_spell)
						buffs.buffList[target.name][opposing_spell] = nil
					elseif (spells_bar_element_self:contains(opposing_spell) or spells_bar_element_aoe:contains(opposing_spell)) and (spells_bar_element_self:contains(action.en) or spells_bar_element_aoe:contains(action.en)) and opposing_spell ~= action.en  then
						atc('Removing opposing bar element buff: '..opposing_spell)
						buffs.buffList[target.name][opposing_spell] = nil
					elseif (spells_bar_status_self:contains(opposing_spell) or spells_bar_status_aoe:contains(opposing_spell)) and (spells_bar_status_self:contains(action.en) or spells_bar_status_aoe:contains(action.en)) and opposing_spell ~= action.en then
						atc('Removing opposing bar status buff: '..opposing_spell)
						buffs.buffList[target.name][opposing_spell] = nil
					elseif spells_haste_flurry:contains(opposing_spell) and spells_haste_flurry:contains(action.en) and opposing_spell ~= action.en then
						atc('Removing opposing spell buff: '..opposing_spell)
						buffs.buffList[target.name][opposing_spell] = nil
					end
				end
			end
		end

        buffs.buffList[target.name][action.en] = {['action']=action, ['maintain']=true, ['buff']=buff, ['status']=status,}
        if action.type == 'Geomancy' then
            if indi_spell_ids:contains(action.id) then
                buffs.buffList[target.name][action.en].is_indi = true
            elseif geo_spell_ids:contains(action.id) then
                buffs.buffList[target.name][action.en].is_geo = true
            end
        end
        atc('Will maintain buff: '..action.en..' '..rarr..' '..target.name)
    else
		if targetName:lower() == 'everyone' then
			atc('Will no longer maintain any buffs on all players except self.')
			for k, v in pairs(buffs.buffList) do
				if k ~= me.name then
					buffs.buffList[k]= nil
				end
			end
		else
			if bname:lower() == 'all' then
				buffs.buffList[target.name] = nil
				atc('Will no longer maintain ALL buffs on: '..target.name)
			else
				buffs.buffList[target.name][action.en] = nil
				atc('Will no longer maintain buff: '..action.en..' '..rarr..' '..target.name)
			end
		end
    end
end

function buffs.registerIgnoreDebuff(args, ignore)
	local targetName = args[1] and args[1] or ''
    table.remove(args, 1)
    local arg_string = table.concat(args,' ')
	local snames = arg_string:split(',')
	
	for index,sname in pairs(snames) do
        if (tostring(index) ~= 'n') then
            buffs.registerIgnoreDebuffName(targetName, sname:trim(), ignore)
        end
    end
end

function buffs.registerIgnoreDebuffName(targetName, bname, ignore)
     
    local msg = ignore and 'ignore' or 'stop ignoring'
    
    local dbname = debuff_casemap[bname:lower()]
    if (dbname ~= nil) then
        if S{'always','everyone','all'}:contains(targetName) then
            buffs.ignored_debuffs[dbname] = {['all']=ignore}
            atc('Will now '..msg..' '..dbname..' on everyone.')
        else
            local trgname = utils.getPlayerName(targetName)
            if (trgname ~= nil) then
                buffs.ignored_debuffs[dbname] = buffs.ignored_debuffs[dbname] or {['all']=false}
                if (buffs.ignored_debuffs[dbname].all == ignore) then
                    local msg2 = ignore and 'ignoring' or 'stopped ignoring'
                    atc('Ignore debuff settings unchanged. Already '..msg2..' '..dbname..' on everyone.')
                else
                    buffs.ignored_debuffs[dbname][trgname] = ignore
                    atc('Will now '..msg..' '..dbname..' on '..trgname)
                end
            else
                atc(123,'Error: Invalid target for ignore debuff: '..targetName)
            end
        end
    else
        atc(123,'Error: Invalid debuff name to '..msg..': '..bname)
    end
end

function buffs.getAction(actionName, target)
    local me = windower.ffxi.get_player()
    local action = nil
    local spell = res.spells:with('en', actionName)
    if (spell ~= nil) and healer:can_use(spell) then
        action = spell
    elseif (target ~= nil) and (target.id == me.id) then
        local abil = res.job_abilities:with('en', actionName)
        if (abil ~= nil) and healer:can_use(abil) then
            action = abil
        end
    end
    return action
end


function buffs.buff_for_action(action)
    local action_str = action
    if type(action) == 'string' then
        if action:startswith('Geo-') or action:startswith('Indi-') then
            action = lc_res.spells[action:lower()]
        end
    end
    if type(action) == 'table' then
        if action.type == 'Geomancy' then
            --This is a hack since there isn't a 1:1 relationship between geo spells and buffs
            return {id=-action.id, en=action.en, enl=action.en}
        end
    
        if buffs.action_buff_map[action.type] ~= nil then
            local mapped_id = buffs.action_buff_map[action.type][action.id]
            if mapped_id ~= nil then
                return res.buffs[mapped_id]
            end
        end
        if (action.type == 'JobAbility') then
            return res.buffs:with('en', action.en)
        end
        action_str = action.en
    end
    if (buff_map[action_str] ~= nil) then
		
        if isnum(buff_map[action_str]) then
            return res.buffs[buff_map[action_str]]
        else
            return res.buffs:with('en', buff_map[action_str])
        end
    elseif action_str:match('^Protectr?a?%s?I*V?$') then
        return res.buffs[40]
    elseif action_str:match('^Shellr?a?%s?I*V?$') then
        return res.buffs[41]
    else
        local buff = res.buffs:with('en', action_str)
        if buff ~= nil then
            return buff
        end
        buff = utils.normalize_action(action_str, 'buffs')
        if buff ~= nil then
            return buff
        end
        local buffName = action_str
        local spLoc = action_str:find(' ')
        if (spLoc ~= nil) then
            buffName = action_str:sub(1, spLoc-1)
        end
        return res.buffs:with('en', buffName)
    end
end


--==============================================================================
--          Buff Tracking Functions
--==============================================================================

--Aura
function buffs.register_debuff_aura_status(target, debuff, aura_flag)
	buffs.auras[target] = buffs.auras[target] or {}
	local auras_tbl = buffs.auras[target]
	auras_tbl[debuff] = {aura_status = aura_flag}
end


function buffs.remove_debuff_aura(target, debuff)
	if buffs.auras[target] and buffs.auras[target][debuff] then
		buffs.auras[target][debuff] = nil
	end
end

--Dispel tracking
function buffs.register_dispelable_buffs(target, debuff, gain, tname, tindex, tspell)
	if gain then
		if not tspell then
			tspell = res.buffs[debuff].en
		end
		if offense.dispel.mobs and offense.dispel.mobs[target] then
			offense.dispel.mobs[target][debuff]= {landed = os.time(), debuff_name = tspell, mob_name = tname, mob_index = tindex}
		else
			offense.dispel.mobs[target] = {}
			offense.dispel.mobs[target][debuff]= {landed = os.time(), debuff_name = tspell, mob_name = tname, mob_index = tindex}
		end
	else -- removal
		if offense.dispel.mobs[target] and offense.dispel.mobs[target][debuff] then
			offense.dispel.mobs[target][debuff] = nil
		end
		local mob_ids = table.keys(offense.dispel.mobs)
		if mob_ids and offense.dispel.mobs[target] and next(offense.dispel.mobs[target]) == nil then
			offense.dispel.mobs[target] = nil
		end
	end
end

function buffs.register_ipc_debuff_loss(target, debuff)
	local tid = target.id
	local is_enemy = (target.spawn_type == 16)

	if is_enemy then
		local temp_debuff_tbl = {targ=target, db=debuff}
		if offense.mobs[tid] then
			local response = { method='POST', pk='mob_debuff_loss_ids', mob_loss_debuff_table=temp_debuff_tbl}
			local ipc_req = serialua.encode(response)
			windower.send_ipc_message(ipc_req)
		end
	end
end

--[[
    Register a debuff gain/loss on the given target, optionally with the action
    that caused the debuff
--]]
function buffs.register_debuff(target, debuff, gain, action)

    debuff = utils.normalize_action(debuff, 'buffs')
	
    if debuff == nil then
        return
    end

    -- log("DEBUG: Gain: " .. tostring(gain))	
    -- if debuff and type(debuff) == "table" then
        -- log("DEBUG: Debuff Table:")
        -- table.vprint(debuff)
    -- else
        -- log("DEBUG: Debuff is not a valid table or is nil")
    -- end

    -- if action and type(action) == "table" then
        -- log("DEBUG: Action Table:")
        -- table.vprint(action)
    -- else
        -- log("DEBUG: Action is not a valid table or is nil")
    -- end
	
	light_shot_tracker[target.id] = light_shot_tracker[target.id] or false
	
	if debuff and debuff.id and debuff.id == 134 then
		light_shot_tracker[target.id] = true  -- Allow Light Shot to apply once any form of Dia is detected
	end
	
	-- Check if the action is Light Shot and the debuff is Dia
    if action and action.name and string.find(action.name, "Light Shot")then
        -- Prevent reapplication of Light Shot if it has already been applied
        if not light_shot_tracker[target.id] then
            return  -- Skip reapplication
        else
            -- Mark Light Shot as applied for this target under Dia
            light_shot_tracker[target.id] = false
        end
    end
	
	ice_shot_tracker[target.id] = ice_shot_tracker[target.id] or false
	
	if debuff and debuff.id and debuff.id == 4 then
		ice_shot_tracker[target.id] = true  -- Allow Light Shot to apply once any form of Dia is detected
	end
	
	
	if action and action.name and string.find(action.name, "Ice Shot")then
        -- Prevent reapplication of Ice Shot if it has already been applied
        if not ice_shot_tracker[target.id] then
            return  -- Skip reapplication
        else
            -- Mark Light Shot as applied for this target under Dia
            ice_shot_tracker[target.id] = false
        end
    end

	if action and action.id and res.spells[action.id] then
		local overwrites = res.spells[action.id].overwrites or {}
		if not buffs.handle_overwrites(target.id, action.id, overwrites) then
			return
		end
	end
    
    local tid, tname, tindex = target.id, target.name, target.index
    local is_enemy = (target.spawn_type == 16)
    if is_enemy then
        offense.mobs[tid] = offense.mobs[tid] or {}
    else
        buffs.debuffList[tname] = buffs.debuffList[tname] or {}
    end
    local debuff_tbl = is_enemy and offense.mobs[tid] or buffs.debuffList[tname]
    local msg = is_enemy and 'mob 'or ''
    
    if gain then
        if is_enemy then
            if offense.ignored[debuff.enn] ~= nil then return end
        else
            local ignoreList = ignoreDebuffs[debuff.en]
            local pmInfo = hb.partyMemberInfo[tname]
            if (ignoreList ~= nil) and (pmInfo ~= nil) then
                if ignoreList:contains(pmInfo.job) and ignoreList:contains(pmInfo.subjob) then
                    atcd(('Ignoring %s on %s because of their job'):format(debuff.en, tname))
                    return
                end
            end
        end

		local aura_flag = buffs.auras[tname] and buffs.auras[tname][debuff.id] and buffs.auras[tname][debuff.id].aura_status or 'no'
		if buffs.gaol_auras:contains(debuff.id) then
			aura_flag = buffs.auras[tname] and buffs.auras[tname][debuff.id] and buffs.auras[tname][debuff.id].aura_status or 'yes'
		end
		
		if action then
			if not(debuff.id == 0 and debuff_tbl[0]) then
				debuff_tbl[debuff.id] = {landed = os.time(), aura = aura_flag, spell_name = action.name, spell_id = action.id, mob_name = tname, mob_index = tindex}
				--Do check here for dia to do lightshot.
				
				if not debuff_tbl[0] and is_enemy then
					debuff_tbl[0] = {landed = os.time(), aura = 'no', spell_name = "KO", spell_id = 50000, mob_name = tname, mob_index = tindex}
				end
			end
		else
			debuff_tbl[debuff.id] = {landed = os.time(), aura = aura_flag, spell_name = 'Unknown Spell', spell_id = 10000, mob_name = tname, mob_index = tindex}
		end
		
        if is_enemy and hb.modes.mob_debug then
            atcd(('Detected %sdebuff: %s %s %s [%s]'):format(msg, debuff.en, rarr, tname, tid))
        end
        atcd(('Detected %sdebuff: %s %s %s [%s]'):format(msg, debuff.en, rarr, tname, tid))
    else
		-- Clear the tracker when Dia wears off
        if debuff and debuff.id and debuff.id == 134 then
            light_shot_tracker[tid] = false  -- Reset tracking for Light Shot
        end
		if debuff and debuff.id and debuff.id == 4 then
            ice_shot_tracker[tid] = false  -- Reset tracking for Ice Shot
        end
        debuff_tbl[debuff.id] = nil
		local mob_ids = table.keys(offense.mobs)
		if mob_ids and offense.mobs[tid] and next(offense.mobs[tid]) == nil then
			offense.mobs[tid] = nil
--			offense.weaponskilltracker[tid] = nil   -- NOT SURE IF NEEDED HERE
		end
        if is_enemy and hb.modes.mob_debug then
            atcd(('Detected %sdebuff: %s wore off %s [%s]'):format(msg, debuff.en, tname, tid))
        end
        atcd(('Detected %sdebuff: %s wore off %s [%s]'):format(msg, debuff.en, tname, tid))
    end
end

function buffs.handle_overwrites(target_id, new_spell_id, overwrites_table)
    if not offense.mobs[target_id] then
        return true
    end
    
    for debuff_id, dbuff_table in pairs(offense.mobs[target_id]) do
        local old = res.spells[dbuff_table.spell_id] and res.spells[dbuff_table.spell_id].overwrites or {}
        
        -- Check if there isn't a higher priority debuff active
        if table.length(old) > 0 then
            for _,v in ipairs(old) do
                if new_spell_id == v then
                    return false
                end
            end
        end
        
        -- Check if a lower priority debuff is being overwritten
        if table.length(overwrites_table) > 0 then
            for _,v in ipairs(overwrites_table) do
                if dbuff_table.spell_id == v then
                    offense.mobs[target_id][debuff_id] = nil
                end
            end
        end
    end
    return true
end

function buffs.process_buff_packet(target_id, status)
    if not target_id then return end
    local target = windower.ffxi.get_mob_by_id(target_id)
    if not target then return end

    buffs.review_active_buffs(target, status)
end

function buffs.register_buff(target, buff, gain, action)
    if not target then return end
    if not isstr(buff) then
        if buff.is_indi or buff.is_geo then
            buffs.buffList[target.name] = buffs.buffList[target.name] or {}
            buffs.buffList[target.name][buff.spell.en] = buffs.buffList[target.name][buff.spell.en] or {}
            buffs.buffList[target.name][buff.spell.en] = buffs.buffList[target.name][buff.spell.en] or {}
            if gain then
                buffs.buffList[target.name][buff.spell.en].landed = os.time()
            else
                buffs.buffList[target.name][buff.spell.en].landed = nil
            end
            return
        end
    end
    
    local nbuff = utils.normalize_action(buff, 'buffs')
    if nbuff == nil then
        atcfs(123,'Error normalizing buff: %s', buff)
    end
    
    if action ~= nil then
        buffs.action_buff_map[action.type] = buffs.action_buff_map[action.type] or {}
        if buffs.action_buff_map[action.type][action.id] == nil then
            buffs.action_buff_map[action.type][action.id] = nbuff.id
            buffs.action_buff_map:save(true)
        end
    end
    
    local tid, tname = target.id, target.name
    local is_enemy = (target.spawn_type == 16)
    local bkey, msg = nbuff.id, ''
    if is_enemy then
        offense.mobs[tid] = offense.mobs[tid] or {}
        msg = 'mob '
    else
        buffs.buffList[tname] = buffs.buffList[tname] or {}
        for spell_name, info in pairs(buffs.buffList[tname]) do
            if info.buff then                                       -- FIXME: Temporary fix for geo error
                if info.buff.id == nbuff.id then
                    bkey = spell_name
                    break
                end
            end
        end
    end

    local buff_tbl = is_enemy and offense.mobs[tid] or buffs.buffList[tname]
    --if is_enemy and offense.dispel[bkey] or buff_tbl[bkey] then
	if buff_tbl[bkey] then
        buff_tbl[bkey] = buff_tbl[bkey] or {}
        if gain then
            buff_tbl[bkey].landed = os.time()
            if is_enemy and hb.modes.mob_debug then
                atc(('Detected %sbuff: %s %s %s [%s]'):format(msg, nbuff.en, rarr, tname, tid))
            end
            atcd(('Detected %sbuff: %s %s %s [%s]'):format(msg, nbuff.en, rarr, tname, tid))
        else
            buff_tbl[bkey].landed = nil
            if is_enemy and hb.modes.mob_debug then
                atc(('Detected %sbuff: %s wore off %s [%s]'):format(msg, nbuff.en, tname, tid))
            end
            atcd(('Detected %sbuff: %s wore off %s [%s]'):format(msg, nbuff.en, tname, tid))
        end
    end 
end

function buffs.resetDebuffTimers(player)
    if (player == nil) then
        atc(123,'Error: Invalid player name passed to buffs.resetDebuffTimers.')
    elseif (player == 'ALL') then
        buffs.debuffList = {}
    else
        buffs.debuffList[player] = {}
    end
end

function buffs.resetBuffTimers(player, exclude)
    if (player == nil) then
        atc(123,'Error: Invalid player name passed to buffs.resetBuffTimers.')
        return
    elseif (player == 'ALL') then
        for p,l in pairs(buffs.buffList) do
            buffs.resetBuffTimers(p)
        end
        return
    end
    buffs.buffList[player] = buffs.buffList[player] or {}
    for buffName,_ in pairs(buffs.buffList[player]) do
        if exclude ~= nil then
            if not (exclude:contains(buffName)) then
                buffs.buffList[player][buffName]['landed'] = nil
            end
        else
            buffs.buffList[player][buffName]['landed'] = nil
        end
    end
end

function buffs.getRemovableDebuffCountAroundTarget(target, dist, debuff)
    local c = 0
    local party = ffxi.party_member_names()
    local targetMob = windower.ffxi.get_mob_by_name(target)
    for watchPerson,_ in pairs(hb.getMonitoredPlayers()) do
        local mob = windower.ffxi.get_mob_by_name(watchPerson)
        local dx = targetMob.x - mob.x
        local dy = targetMob.y - mob.y
        if buffs.debuffList[watchPerson] and buffs.debuffList[watchPerson][debuff] and dx^2+dy^2 < dist^2 then
            -- watched person has debuff and is within distance.
            c = c + 1
        end
    end
    return c
end

function buffs.has_buffs(target, buff_list)
    for id, info in pairs(buffs.debuffList[target]) do
        if buff_list:contains(id) then
            return true
        end
    end
    return false
end

return buffs

--======================================================================================================================
--[[
Copyright © 2016, Lorand
All rights reserved.
Redistribution and use in source and binary forms, with or without modification, are permitted provided that the
following conditions are met:
    * Redistributions of source code must retain the above copyright notice, this list of conditions and the
      following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the
      following disclaimer in the documentation and/or other materials provided with the distribution.
    * Neither the name of ffxiHealer nor the names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL Lorand BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
--]]
--======================================================================================================================
