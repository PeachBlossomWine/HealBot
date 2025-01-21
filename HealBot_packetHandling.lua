--==============================================================================
--[[
    Author: Ragnarok.Lorand
    HealBot packet handling functions
--]]
--==============================================================================
require('logger')
local messages_blacklist = _libs.lor.packets.messages_blacklist
local messages_initiating = _libs.lor.packets.messages_initiating
local messages_completing = _libs.lor.packets.messages_completing

local get_action_info = _libs.lor.packets.get_action_info
local parse_char_update = _libs.lor.packets.parse_char_update
local packet_player = windower.ffxi.get_player()

function send_job_registry_update()
    local player = windower.ffxi.get_player()
    if not player then return end
	
	-- Update your own registry locally
    hb.job_registry = hb.job_registry or {}
    hb.job_registry[player.id] = res.jobs[player.main_job_id].ens

    local message = {
        method = 'POST',
        pk = 'job_registry',
        id = player.id,
        job_id = player.main_job_id,
        job_name = player.main_job,
    }
    windower.send_ipc_message(serialua.encode(message))
end

function request_job_registry()
	local player = windower.ffxi.get_player()
	-- Update your own registry locally
    hb.job_registry = hb.job_registry or {}
    hb.job_registry[player.id] = res.jobs[player.main_job_id].ens
	
    local message = {
        method = 'GET',
        pk = 'job_registry',
		registry = hb.job_registry,
    }
    windower.send_ipc_message(serialua.encode(message))
end


-- Credit to partyhints
function set_registry(id, job_id)
    if not id then return false end

    -- Ensure the registry table exists
    hb.job_registry = hb.job_registry or {}

    -- Only update if the job is not already set
    if not hb.job_registry[id] or hb.job_registry[id] == 'NON' or hb.job_registry[id] == 'UNK' then
        job_id = job_id or 0
        hb.job_registry[id] = res.jobs[job_id] and res.jobs[job_id].ens or 'UNK'
        return true
    end

    return false -- No update needed
end


-- Credit to partyhints
function get_registry(id)
    if hb.job_registry[id] then
		return hb.job_registry[id]
    else
        return 'UNK'
    end
end

-- Track mob buffs for dispel action
function handle_dispel_action(act)
	for _,targ in pairs(act.targets) do
		local target = windower.ffxi.get_mob_by_id(targ.id) or nil
		local valid_target = act.valid_target
		local actor = windower.ffxi.get_mob_by_id(act.actor_id)	or nil	
		local category = act.category  
		local param = act.param
		local targets = act.targets
		local action_buff = targets[1].actions[1].param
	
		if target and actor and utils.isMonster(actor.index) and utils.isMonster(target.index) and S{4,11}:contains(category) then 
			if category == 11 then	-- Monster abilitiies
				if res.monster_abilities[param] and not (dispel_mob_ja_blacklist:contains(param)) then 
					if res.buffs[action_buff] and not special_mob_ja[param] and not (dispel_buffs_blacklist:contains(action_buff)) then
						buffs.register_dispelable_buffs(target.id, action_buff, true, target.name, target.index)
					elseif special_mob_ja[param] then	-- Special abilitiies that don't return buff value.
						for _,mob_buff in pairs(special_mob_ja[param]) do
							buffs.register_dispelable_buffs(target.id, mob_buff, true, target.name, target.index)
						end
					end
				end
			elseif category == 4 then	-- Monster spells
				if res.spells[param] then
					if res.buffs[action_buff] and not (dispel_buffs_blacklist:contains(action_buff)) then
						buffs.register_dispelable_buffs(target.id, action_buff, true, target.name, target.index, res.spells[param].en)
					end
				end
			end
		end
	end
end

function handle_outgoing_chunk(id, data)
	if id == 0x05E and not settings.follow.target then
		hb.zone_begin = true
	end
end

function handleActionOther(act)
	if S{185}:contains(act.targets[1].actions[1].message) then -- WS
		local tid = act.targets[1].id 	--WS target
        local ws_dmg = act.targets[1].actions[1].param -- WS DMG
        local actor = act.actor_id 	-- WS initiator

		if packet_player.id == actor then
			if offense.mobs and offense.mobs[tid] then
				offense.weaponskilltracker[tid] = offense.weaponskilltracker[tid] or {}
				offense.weaponskilltracker[tid].count = (offense.weaponskilltracker[tid].count or 0) + 1
				if ws_dmg > (offense.weaponskilltracker[tid].dmg or 0) then
					offense.weaponskilltracker[tid].dmg = ws_dmg
				end
			end
		end
    end
end

--[[
    Analyze the data contained in incoming packets for useful info.
    :param int id: packet ID
    :param data: raw packet contents
--]]
function handle_incoming_chunk(id, data)
    if S{0x28,0x29}:contains(id) then   --Action / Action Message
        local monitored_ids = hb.getMonitoredIds()
        local ai = get_action_info(id, data)
        healer:update_status(id, ai)
        if ai.actor_id == healer.id and hb.aoe_action then
            if ai.param == hb.aoe_action.action.id or (ai.targets and ai.targets[1].actions[1].param == hb.aoe_action.action.id) then
                hb.aoe_action = nil
                atcd("Cleared aoe_action")
            end
        end
        if id == 0x28 then
            processAction(ai, monitored_ids)
			handleActionOther(windower.packets.parse_action(data))
        elseif id == 0x29 then
            processMessage(ai, monitored_ids)
        end
    elseif (id == 0x037) then
        healer.indi.info = parse_char_update(data)
    elseif (id == 0x0DD or id == 0x0DF or id == 0x0C8) then	--Party member update
        local parsed = packets.parse('incoming', data)
		if parsed then
			local playerId = parsed['ID']
			local indexx = parsed['Index']
			local job = parsed['Main job']
			
			if playerId and playerId > 0 then
				set_registry(parsed['ID'], parsed['Main job'])
			end
		end
	elseif id == 0x063 then -- Player buffs for Aura detection : Credit: elii, bp4
		local parsed = packets.parse('incoming', data)
		for i=1, 32 do
			local buff = tonumber(parsed[string.format('Buffs %s', i)]) or 0
			local time = tonumber(parsed[string.format('Time %s', i)]) or 0
			
			if buff > 0 and buff ~= 255 and buff ~= 15 and enfeebling:contains(buff) then
				if math.ceil(1009810800 + (time / 60) + 0x100000000 / 60 * 10) - os.time() <= 5 then
					buffs.register_debuff_aura_status(packet_player.name, buff, 'yes')
				else
					buffs.register_debuff_aura_status(packet_player.name, buff, 'no')
				end
			end
		end
	elseif id == 0x076 then -- partybuffs
        for  k = 0, 4 do
            local id = data:unpack('I', k*48+5)
            local new_buffs_list = {}

            local new_i = 0
            if id ~= 0 then
                for i = 1, 32 do
                    local buff = data:byte(k*48+5+16+i-1) + 256*( math.floor( data:byte(k*48+5+8+ math.floor((i-1)/4)) / 4^((i-1)%4) )%4) -- Credit: Byrth, GearSwap
                    if buff == 255 then
                        break
                    end
                    new_buffs_list[i] = buff
                end
            end
            buffs.process_buff_packet(id, new_buffs_list)
        end
	elseif id == 0x00E then
		local packet = packets.parse('incoming', data)
		local hp_status_flag = bit.band(packet['Mask'], 4) > 0
		local name_flag = bit.band(packet['Mask'], 8) > 0
		local depop_flag = bit.band(packet['Mask'], 32) > 0
		local hidden_model = bit.band(packet['_unknown2'],2) > 0
		local untargetable = bit.band(packet['_unknown2'],0x80000) > 0
		
		if (depop_flag or (hp_status_flag and (packet['HP %'] == 0 or packet['Status'] == 2 or packet['Status'] == 3))) and not hidden_model and not untargetable then
			processDebuffMobs(packet['NPC'])
		end
	elseif id == 0x00B then 
		if hb.zone_begin and not settings.follow.target then
			--log('0x00B: packet for zone NOW.')
			local response = { method='POST', pk='follow_ids', follow_name = packet_player.name, orig_zone = windower.ffxi.get_info().zone }
			local ipc_req = serialua.encode(response)
			windower.send_ipc_message(ipc_req)
		else
			--log('0x00B: Unset zone run.')
			hb.should_attempt_to_cross_zone_line = false
		end
    end
end

function processDebuffMobs(mob_id)
	
    local mob_ids = table.keys(offense.mobs)
    if mob_ids and offense.mobs[mob_id] then -- this clears when mob dies
		offense.mobs[mob_id] = nil
		if offense.weaponskilltracker and offense.weaponskilltracker[mob_id] then
			offense.weaponskilltracker[mob_id] = nil
		end
    end
	if light_shot_tracker[mob_id] ~= nil then
		light_shot_tracker[mob_id] = nil
	end
	if ice_shot_tracker[mob_id] ~= nil then
		ice_shot_tracker[mob_id] = nil
	end
	if earth_shot_tracker[mob_id] ~= nil then
		earth_shot_tracker[mob_id] = nil
	end
	if offense.dispel.mobs and offense.dispel.mobs[mob_id] then
		offense.dispel.mobs[mob_id] = nil
	end
end

function handle_lose_buff(buff_id)
	if buff_id and enfeebling:contains(buff_id) then
		buffs.remove_debuff_aura(packet_player.name,buff_id)
	end
end


--[[
    Process the information that was parsed from an action message packet
    :param ai: parsed action info
    :param set monitored_ids: the IDs of PCs that are being monitored
--]]
--0x029
function processMessage(ai, monitored_ids)
    if monitored_ids[ai.actor_id] or monitored_ids[ai.target_id] then
        if not (messages_blacklist:contains(ai.message_id)) then
            local target = windower.ffxi.get_mob_by_id(ai.target_id)
            
            if hb.modes.showPacketInfo then
                local actor = windower.ffxi.get_mob_by_id(ai.actor_id)
                local msg = res.action_messages[ai.message_id] or {en='???'}
                local params = (', '):join(tostring(ai.param_1), tostring(ai.param_2), tostring(ai.param_3))
                atcfs('[0x29]Message(%s): %s { %s } %s %s | %s', ai.message_id, actor.name, params, rarr, target.name, msg.en)
            end
            
            if messages_wearOff:contains(ai.message_id) then
                if ai.param_1 == 143 then
                    buffs.resetDebuffTimers('ALL')
                elseif enfeebling:contains(ai.param_1) then
                    buffs.register_debuff(target, res.buffs[ai.param_1], false)
					buffs.register_ipc_debuff_loss(target, res.buffs[ai.param_1])
                else
                    buffs.register_buff(target, res.buffs[ai.param_1], false)
                end
            end
        end--/message ID not on blacklist
    end--/monitoring actor or target
end


--[[
    Process the information that was parsed from an action packet
    :param ai: parsed action info
    :param set monitored_ids: the IDs of PCs that are being monitored
--]]
function processAction(ai, monitored_ids)
    for _,targ in pairs(ai.targets) do
        if monitored_ids[ai.actor_id] or monitored_ids[targ.id] then
            local actor = windower.ffxi.get_mob_by_id(ai.actor_id)
            local target = windower.ffxi.get_mob_by_id(targ.id)
            
            for _,tact in pairs(targ.actions) do
                if not messages_blacklist:contains(tact.message_id) then
                    if (tact.message_id == 0) and (ai.actor_id == healer.id) then
                        -- if indi_spell_ids:contains(ai.param) then
                            -- healer.indi.latest = {spell = res.spells[ai.param], landed = os.time(), is_indi = true}
                            -- buffs.register_buff(target, healer.indi.latest, true)
                        -- elseif geo_spell_ids:contains(ai.param) then
                            -- healer.geo.latest = {spell = res.spells[ai.param], landed = os.time(), is_geo = true}
                            -- buffs.register_buff(target, healer.geo.latest, true)
                        -- end
                    end
					-- if (tact.message_id == 0) and (actor.name == healer.name) then
                        -- local spell = res.spells[ai.param]
                        -- if spell ~= nil then
                            -- if spell.type == 'Geomancy' then
                                -- register_action(spell.type, ai.param)
                            -- end
                        -- end
                    -- end
                
                    if hb.modes.showPacketInfo then
                        local msg = res.action_messages[tact.message_id] or {en='???'}
                        atcfs('[0x28]Action(%s): %s { %s } %s %s { %s } | %s', tact.message_id, actor.name, ai.param, rarr, target.name, tact.param, msg.en)
                    end
                    
                    registerEffect(ai, tact, actor, target, monitored_ids)
                end--/message ID not on blacklist
            end--/loop through targ's actions
        end--/monitoring actor or target
    end--/loop through action's targets
end


function handle_shot(target, shot_id)
    if not offense.mobs[target.id] then return false end
    local cause = nil
	local cor_upgrade_cause = nil
	local buff_id = nil
	
    if shot_id == 125 and offense.mobs[target.id][128] then	 -- Fire
		cause = res.spells[235] -- Burn
		buff_id = 128
		if not offense.mobs[target.id][buff_id].shot then
			cor_upgrade_cause = {name=string.format("%s %s", cause.name, ' (Fire Shot)')}
			offense.mobs[target.id][buff_id].shot = 1
			buffs.register_debuff(target, res.buffs[buff_id], true, cor_upgrade_cause)
		else
			cor_upgrade_cause = {name=string.format("%s %s", cause.name, ' (Fire Shot) x2')}
			offense.mobs[target.id][buff_id].shot = 2
			buffs.register_debuff(target, res.buffs[buff_id], true, cor_upgrade_cause)
		end
	elseif shot_id == 126 then -- Ice
		if offense.mobs[target.id][4] and S{58,80}:contains(offense.mobs[target.id][4].spell_id) and not offense.mobs[target.id][4].shot then -- Paralysis
			buff_id = 4 -- Paralysis
			cause = res.spells[offense.mobs[target.id][buff_id].spell_id]
			cor_upgrade_cause = {name=string.format("%s %s", cause.name, ' (Ice Shot)')}
			offense.mobs[target.id][buff_id].shot = 1
			buffs.register_debuff(target, res.buffs[buff_id], true, cor_upgrade_cause)
		end
		if offense.mobs[target.id][129] then -- Burn
            cause = res.spells[236]
			buff_id = 129
            if not offense.mobs[target.id][buff_id].shot then
				cor_upgrade_cause = {name=string.format("%s %s", cause.name, ' (Ice Shot)')}
                offense.mobs[target.id][buff_id].shot = 1
                buffs.register_debuff(target, res.buffs[buff_id], true, cor_upgrade_cause)
            else
				cor_upgrade_cause = {name=string.format("%s %s", cause.name, ' (Ice Shot) x2')}
                offense.mobs[target.id][buff_id].shot = 2
                buffs.register_debuff(target, res.buffs[buff_id], true, cor_upgrade_cause)
            end
        end
	elseif shot_id == 127 and offense.mobs[target.id][130] then -- Wind
		cause = res.spells[237] -- Choke
		buff_id = 130
		if not offense.mobs[target.id][buff_id].shot then
			cor_upgrade_cause = {name=string.format("%s %s", cause.name, ' (Wind Shot)')}
			offense.mobs[target.id][buff_id].shot = 1
			buffs.register_debuff(target, res.buffs[buff_id], true, cor_upgrade_cause)
		else
			cor_upgrade_cause = {name=string.format("%s %s", cause.name, ' (Wind Shot) x2')}
			offense.mobs[target.id][buff_id].shot = 2
			buffs.register_debuff(target, res.buffs[buff_id], true, cor_upgrade_cause)
		end
	elseif shot_id == 128 then -- Earth
		if offense.mobs[target.id][13] and S{56,79,344,345}:contains(offense.mobs[target.id][13].spell_id) and not offense.mobs[target.id][13].shot then -- Slow
			buff_id = 13
			cause = res.spells[offense.mobs[target.id][buff_id].spell_id]
			cor_upgrade_cause = {name=string.format("%s %s", cause.name, ' (Earth Shot)')}
			offense.mobs[target.id][buff_id].shot = 1
			buffs.register_debuff(target, res.buffs[buff_id], true, cor_upgrade_cause)
		end
		if offense.mobs[target.id][131] then -- Rasp
            cause = res.spells[238]
			buff_id = 131
            if not offense.mobs[target.id][buff_id].shot then
				cor_upgrade_cause = {name=string.format("%s %s", cause.name, ' (Earth Shot)')}
                offense.mobs[target.id][buff_id].shot = 1
                buffs.register_debuff(target, res.buffs[buff_id], true, cor_upgrade_cause)
            else
				cor_upgrade_cause = {name=string.format("%s %s", cause.name, ' (Earth Shot) x2')}
                offense.mobs[target.id][buff_id].shot = 2
                buffs.register_debuff(target, res.buffs[buff_id], true, cor_upgrade_cause)
            end
        end
	elseif shot_id == 129 and offense.mobs[target.id][132] then -- Thunder
		cause = res.spells[239] -- Shock
		buff_id = 132
		if not offense.mobs[target.id][buff_id].shot then
			cor_upgrade_cause = {name=string.format("%s %s", cause.name, ' (Thunder Shot)')}
			offense.mobs[target.id][buff_id].shot = 1
			buffs.register_debuff(target, res.buffs[buff_id], true, cor_upgrade_cause)
		else
			cor_upgrade_cause = {name=string.format("%s %s", cause.name, ' (Thunder Shot) x2')}
			offense.mobs[target.id][buff_id].shot = 2
			buffs.register_debuff(target, res.buffs[buff_id], true, cor_upgrade_cause)
		end
	elseif shot_id == 130 then -- Water
		if offense.mobs[target.id][3] and S{220,221}:contains(offense.mobs[target.id][3].spell_id) and not offense.mobs[target.id][3].shot then -- Slow
			buff_id = 3
			cause = res.spells[offense.mobs[target.id][buff_id].spell_id]
			cor_upgrade_cause = {name=string.format("%s %s", cause.name, ' (Water Shot)')}
			offense.mobs[target.id][buff_id].shot = 1
			buffs.register_debuff(target, res.buffs[buff_id], true, cor_upgrade_cause)
		end
		if offense.mobs[target.id][133] then -- Drown
            cause = res.spells[240]
			buff_id = 133
            if not offense.mobs[target.id][buff_id].shot then
				cor_upgrade_cause = {name=string.format("%s %s", cause.name, ' (Water Shot)')}
                offense.mobs[target.id][buff_id].shot = 1
                buffs.register_debuff(target, res.buffs[buff_id], true, cor_upgrade_cause)
            else
				cor_upgrade_cause = {name=string.format("%s %s", cause.name, ' (Water Shot) x2')}
                offense.mobs[target.id][buff_id].shot = 2
                buffs.register_debuff(target, res.buffs[buff_id], true, cor_upgrade_cause)
            end
        end
	elseif shot_id == 131 then
		if offense.mobs[target.id][134] and not offense.mobs[target.id][134].shot then -- Light
			buff_id = 134 -- Dia
			cause = res.spells[offense.mobs[target.id][buff_id].spell_id]
			cor_upgrade_cause = {name=string.format("%s %s", cause.name, ' (Light Shot)')}
			offense.mobs[target.id][buff_id].shot = 1
			buffs.register_debuff(target, res.buffs[buff_id], true, cor_upgrade_cause)
		-- else  -- no Dia
			-- buff_id = 253
			-- cause = res.spells[253]
			-- cor_upgrade_cause = {name=string.format("%s %s", cause.name, ' (Light Shot)')}
			-- buffs.register_debuff(target, res.buffs[2], true, cor_upgrade_cause)
		end
	elseif shot_id == 132 then -- Dark
		if offense.mobs[target.id][5] and S{254,276,347,348}:contains(offense.mobs[target.id][5].spell_id) and not offense.mobs[target.id][5].shot then -- Slow
			buff_id = 5 -- Blind
			cause = res.spells[offense.mobs[target.id][buff_id].spell_id]
			cor_upgrade_cause = {name=string.format("%s %s", cause.name, ' (Dark Shot)')}
			offense.mobs[target.id][buff_id].shot = 1
			buffs.register_debuff(target, res.buffs[buff_id], true, cor_upgrade_cause)
		end
		if offense.mobs[target.id][135] and not offense.mobs[target.id][135].shot then 
			buff_id = 135 -- Bio
			cause = res.spells[offense.mobs[target.id][buff_id].spell_id]
			cor_upgrade_cause = {name=string.format("%s %s", cause.name, ' (Dark Shot)')}
			offense.mobs[target.id][buff_id].shot = 1
			buffs.register_debuff(target, res.buffs[buff_id], true, cor_upgrade_cause)
		end
	end
end

-- Tracking BLM -ja spells
function handle_ja_spells(target, spell)
	local buff_id = 3000

	if offense.mobs[target.id] and offense.mobs[target.id][buff_id] and spell.id == offense.mobs[target.id][buff_id].spell_id then -- 2nd to 5th
		local tier = offense.mobs[target.id][buff_id].tier
		if tier < 5 then
			tier = tier + 1
			res.buffs[buff_id] = {id=buff_id,en=messages_blm_ja_spells_names[spell.id][tier],spell_id=spell.id}
			local blm_ja_spell_cause = {id=spell.id, name=string.format("%s: %s", spell.name, messages_blm_ja_spells_names[spell.id][tier])}
			buffs.register_debuff(target, res.buffs[buff_id], true, blm_ja_spell_cause)
			if offense.mobs[target.id] then
				offense.mobs[target.id][buff_id].tier = tier
			end
		end
	else -- First landed debuff
		res.buffs[buff_id] = {id=buff_id,en=messages_blm_ja_spells_names[spell.id][1],spell_id=spell.id}
		local blm_ja_spell_cause = {id=spell.id, name=string.format("%s: %s", spell.name, messages_blm_ja_spells_names[spell.id][1])}
		buffs.register_debuff(target, res.buffs[buff_id], true, blm_ja_spell_cause)
		if offense.mobs[target.id] and offense.mobs[target.id][buff_id] then
			offense.mobs[target.id][buff_id].tier = 1
		end
	end
end

--[[
    Register the effects that were discovered in an action packet
    :param ai: parsed action info
    :param tact: the subaction on a target
    :param actor: the PC/NPC initiating the action
    :param target: the PC/NPC that is the target of the action
    :param set monitored_ids: the IDs of PCs that are being monitored
--]]
function registerEffect(ai, tact, actor, target, monitored_ids)

	local claim_spell_cause = {id=50000, name="KO"}
	if target then
		targ_is_enemy = (target.spawn_type == 16)
	end

	if (messages_resists:contains(tact.message_id) or messages_physDamage:contains(tact.message_id) or messages_shadows:contains(tact.message_id)) and targ_is_enemy then
		buffs.register_debuff(target, 'KO', true, claim_spell_cause)
    elseif messages_magicDamage:contains(tact.message_id) then
        local spell = res.spells[ai.param]
        if S{230,231,232,233,234}:contains(ai.param) then
            buffs.register_debuff(target, 'Bio', true, spell)
        elseif S{23,24,25,26,27,33,34,35,36,37}:contains(ai.param) then
            buffs.register_debuff(target, 'Dia', true, spell)
		elseif helix_spells:contains(ai.param) then
			local helix_dmg = ai.targets[1].actions[1].param <= 9999 and ai.targets[1].actions[1].param or 9999
			local helix_spell_cause = {id=ai.param, name=string.format("%s [%s]", spell.name, helix_dmg)}
		    buffs.register_debuff(target, 'Helix', true, helix_spell_cause)
		elseif ai.param == 502 then -- Kaustra
			local kaustra_spell_cause = {id=ai.param, name=string.format("%s [%s]", spell.name, ai.targets[1].actions[1].param)}
		elseif messages_blm_ja_spells:contains(ai.param) then	--BLM ja spells
			handle_ja_spells(target, spell)
		elseif ai.param == 503 then -- Impact
			buffs.register_debuff(target, 'CHR Down', true, spell)
		elseif messages_bluemage_spells[ai.param] then
			local blu_spell_cause = {id=ai.param, name=string.format("%s %s", spell.name, messages_bluemage_spells[ai.param].text)}
			buffs.register_debuff(target, messages_bluemage_spells[ai.param].buff, true, blu_spell_cause)
		else
			if target and targ_is_enemy then
				buffs.register_debuff(target, 'KO', true, claim_spell_cause)
			end
        end
    elseif messages_magicHealed:contains(tact.message_id) then
        local spell = res.spells[ai.param]
        if S{230,231,232,233,234}:contains(ai.param) then
            buffs.register_debuff(target, 'Bio', true, spell)
        elseif S{23,24,25,26,27,33,34,35,36,37}:contains(ai.param) then
            buffs.register_debuff(target, 'Dia', true, spell)
		elseif ai.param == 503 then
			buffs.register_debuff(target, 'CHR Down', true, spell)
		else
			if target and targ_is_enemy then
				buffs.register_debuff(target, 'KO', true, claim_spell_cause)
			end
        end
	elseif msg_gain_ws:contains(tact.message_id) then
		if messages_stat_down_ws[ai.param] then
			local ws_cause = {id=ai.param, name=string.format("%s %s", res.weapon_skills[ai.param].name, messages_stat_down_ws[ai.param].text)}
			buffs.register_debuff(target, messages_stat_down_ws[ai.param].buff, true, ws_cause)
		elseif targ_is_enemy then
			buffs.register_debuff(target, 'KO', true, claim_spell_cause)
		end
	elseif ai.category == 6 and messages_cor_shots:contains(ai.param) and ai.targets[1].actions[1].message_id ~= 323 then	--Corsair shots
		handle_shot(target, ai.param)
		if targ_is_enemy then
			buffs.register_debuff(target, 'KO', true, claim_spell_cause)
		end
	elseif S{1,67}:contains(tact.message_id) and S{1,3}:contains(ai.category) and targ_is_enemy then
		if ai.category == 1 and ai.targets[1].actions[1].has_add_efct and ai.targets[1].actions[1].add_efct_message_id == 603 then	--THF Treasure Hunter
			local TH_cause = {id=1000, name=string.format("TH: %s", ai.targets[1].actions[1].add_efct_param)}
			res.buffs[1000] = res.buffs[1000] or {}
			res.buffs[1000] = {id=1000,en="Treasure Hunter",ja="TH",enl="Treasure Hunter",jal="TH"}
			buffs.register_debuff(target, res.buffs[1000].en, true, TH_cause)
		elseif ai.category == 3 and ai.targets[1].actions[1].message == 608 then --RNG Treasure Hunter
			res.buffs[1000] = res.buffs[1000] or {}
			res.buffs[1000] = {id=1000,en="Treasure Hunter",ja="TH",enl="Treasure Hunter",jal="TH"}
			local TH_cause = {id=1000, name=string.format("TH: %s", ai.targets[1].actions[1].param)}
			buffs.register_debuff(target, res.buffs[1000].en, true, TH_cause)
		end
	elseif messages_gainEffect:contains(tact.message_id) then   --ai.param: spell; tact.param: buff/debuff
        --{target} gains the effect of {buff} / {target} is {debuff}ed
        local cause = nil
		local tier = nil
		local steps_cause = nil
        if msg_gain_abil:contains(tact.message_id) then
			if S{519,520,521,591}:contains(tact.message_id) then -- Steps
				cause = res.job_abilities[ai.param]
				tier = ai.targets[1].actions[1].param
				steps_cause = {id=ai.param, name=string.format("%s: Lv.%s", cause.name, tier)}
			else
				cause = res.job_abilities[ai.param]
			end
        elseif msg_gain_spell:contains(tact.message_id) then
            cause = res.spells[ai.param]
        end

        local buff = res.buffs[tact.param]
		if messages_dnc_steps[tact.message_id] then
			buffs.register_debuff(target, res.buffs[messages_dnc_steps[tact.message_id]], true, steps_cause)
		elseif enfeebling:contains(tact.param) then
			if messages_bluemage_spells[ai.param] then
				cause = res.spells[ai.param]
				local blu_spell_cause = {id=ai.param, name=string.format("%s %s", cause.name, messages_bluemage_spells[ai.param].text)}
				buffs.register_debuff(target, messages_bluemage_spells[ai.param].buff, true, blu_spell_cause)
			else
				buffs.register_debuff(target, buff, true, cause)
			end
        else
			buffs.register_buff(target, buff, true, cause)
        end
    elseif messages_loseEffect:contains(tact.message_id) then   --ai.param: spell; tact.param: buff/debuff
        --{target}'s {buff} wore off
        local buff = res.buffs[tact.param]
        if enfeebling:contains(tact.param) then
            buffs.register_debuff(target, buff, false)
			buffs.register_ipc_debuff_loss(target, buff)
        else
			if not targ_is_enemy then
				buffs.register_buff(target, buff, false)
			end
			buffs.register_dispelable_buffs(target.id, buff.id, false, target.name, target.index)	--Dispel removal
        end
    elseif messages_noEffect:contains(tact.message_id) then     --ai.param: spell; tact.param: buff/debuff
        --Spell had no effect on {target}
        local spell = res.spells[ai.param]
        if (spell ~= nil) then
            if spells_statusRemoval:contains(spell.id) then
                --The debuff must have worn off or have been removed already
                local debuffs = removal_map[spell.en]
                if (debuffs ~= nil) then
                    for _,debuff in pairs(debuffs) do
                        buffs.register_debuff(target, debuff, false)
                    end
                end
            elseif spells_buffs:contains(spell.id) then		--The buff must already be active, or there must be some debuff preventing the buff from landing
                local buff = buffs.buff_for_action(spell)
                if (buff == nil) then
                    atcd('ERROR: No buff found for spell: '..spell.en)
                else
                    buffs.register_buff(target, buff, false)
                end
            elseif spell_debuff_idmap[spell.id] ~= nil and targ_is_enemy then	--The debuff already landed from someone else
                local debuff_id = spell_debuff_idmap[spell.id]
				local cause = res.spells[spell.id]
				if not (offense.mobs[target.id] and offense.mobs[target.id][debuff_id]) then
					if not (offense.mobs[target.id] and offense.mobs[target.id][debuff_id] and not S{2,193}:contains(offense.mobs[target.id][debuff_id])) then		--Sleep vs Lullaby handling
						buffs.register_debuff(target, debuff_id, true, cause)
					end
				end
			elseif targ_is_enemy and S{260,360,462}:contains(spell.id) then		--Dispel no effect, assuming every buff is removed
				if offense.dispel.mobs and offense.dispel.mobs[target.id] then
					offense.dispel.mobs[target.id] = nil
				end
            end
			if targ_is_enemy then
				buffs.register_debuff(target, 'KO', true, claim_spell_cause)
			end
        end
    elseif messages_absorb_spells[tact.message_id] ~= nil then
        local abs_debuffs = messages_absorb_spells[tact.message_id]
		local cause = res.spells[abs_debuffs.spell_id]
		buffs.register_debuff(target, abs_debuffs.buff, true, cause)
    elseif messages_specific_debuff_lose[tact.message_id] ~= nil then
        local lost_debuffs = messages_specific_debuff_lose[tact.message_id]
        for _,lost_debuff in pairs(lost_debuffs) do
            buffs.register_debuff(target, lost_debuff, false)
        end
	elseif msg_gain_abil:contains(tact.message_id) then
		local cause = res.job_abilities[ai.param]
		local buff = res.buffs[tact.param]
		if messages_provokeTypes:contains(ai.param) and targ_is_enemy then
			buffs.register_debuff(target, 'KO', true, claim_spell_cause)
		else
			buffs.register_buff(target, buff, true, cause)
		end
    elseif S{655,656}:contains(tact.message_id) and targ_is_enemy then
        offense.register_immunity(target, res.buffs[tact.param])
		buffs.register_debuff(target, 'KO', true, claim_spell_cause)
    end--/message ID checks
end

windower.register_event('lose buff', handle_lose_buff)
-----------------------------------------------------------------------------------------------------------
--[[
Copyright © 2016, Lorand
All rights reserved.
Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
    * Neither the name of healBot nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL Lorand BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--]]
-----------------------------------------------------------------------------------------------------------
