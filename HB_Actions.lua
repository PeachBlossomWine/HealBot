--==============================================================================
--[[
	Author: Ragnarok.Lorand
	HealBot action handling functions
--]]
--==============================================================================

local actions = {queue=L()}
local lor_res = _libs.lor.resources
local ffxi = _libs.lor.ffxi


local function local_queue_reset()
    actions.queue = L()
end

local function local_queue_insert(action, target)
	if (tostring(action) ~= nil) and (tostring(target) ~= nil) then
		actions.queue:append(tostring(action)..' → '..tostring(target))
	end
end

local function local_queue_disp()
    hb.txts.actionQueue:text(getPrintable(actions.queue))
    hb.txts.actionQueue:visible(settings.textBoxes.actionQueue.visible)
end

--[[
	Builds an action queue for defensive actions.  Returns the action deemed most important at the time.
--]]
function actions.get_defensive_action()
	local action = {}
	local player = player or windower.ffxi.get_player()
	
	if (not settings.disable.cure) then
		local cureq = CureUtils.get_cure_queue()
		while (not cureq:empty()) do
			local cact = cureq:pop()
            local_queue_insert(cact.action.en, cact.name)
			
			--ST20 debuff, prevent curing.
			local ST20 = false
			if buffs.debuffList[cact.name] and buffs.debuffList[cact.name][20] then
				ST20 = true
			end
			
			if (action.cure == nil) and healer:in_casting_range(cact.name) and ST20 == false then
				action.cure = cact
			end
		end
	end
	--Na and ERASE
	if (not settings.disable.na) then
		local dbuffq = buffs.getDebuffQueue()
		while (not dbuffq:empty()) do
			local dbact = dbuffq:pop()
			atcd(123, 'Debuff popped to remove: ' .. dbact.debuff.en)
			local ign = buffs.ignored_debuffs[dbact.debuff.en]	
			
			if not ((ign ~= nil) and ((ign.all == true) or ((ign[dbact.name] ~= nil) and (ign[dbact.name] == true)))) then
				-- Erase disable toggle
				if (dbact.action.en == 'Erase') then
					if (not settings.disable.erase) then
						dbact_target = windower.ffxi.get_mob_by_name(dbact.name)
						local_queue_insert(dbact.action.en, dbact.name)
						if (action.debuff == nil) and healer:in_casting_range(dbact.name) and healer:ready_to_use(dbact.action) and not(dbact_target.hpp == 0) then
							action.debuff = dbact
						end
					end
				else
					dbact_target = windower.ffxi.get_mob_by_name(dbact.name)
					local is_trust = dbact_target and dbact_target.spawn_type == 14 or false
					if not(is_trust and dbact.debuff.en:lower() == 'sleep') then
						local_queue_insert(dbact.action.en, dbact.name)
						if (action.debuff == nil) and healer:in_casting_range(dbact.name) and healer:ready_to_use(dbact.action) and not(dbact_target.hpp == 0) then
							action.debuff = dbact
						end
					end
				end
			else
				atcd(123, '***[Failsafe ignore_debuff caught]*** ->  Name: ' .. dbact.name .. ' Debuff: ' .. dbact.debuff.en .. ' ID: ' .. dbact.debuff.id)
			end
			
		end
	end
	--Buffs
	if (not settings.disable.buff) then
		
		local buffq = buffs.getBuffQueue()
		while (not buffq:empty()) do
			local bact = buffq:pop()
			local bact_target = bact and windower.ffxi.get_mob_by_name(bact.name)
			
			if (bact and bact.action and bact.action.en) then
				if shouldBuff(bact, bact_target) then
					local_queue_insert(bact.action.en, bact.name)
				end
			end
            
			if (action.buff == nil) and healer:in_casting_range(bact.name) and healer:ready_to_use(bact.action) and bact_target and bact_target.hpp > 0 then
				if shouldBuff(bact, bact_target) then
					action.buff = bact
				end
			end
		end
	end
	
	local_queue_disp()
	
	if (action.cure ~= nil) then
		if (action.debuff ~= nil) and (action.debuff.action.en == 'Paralyna') and (action.debuff.name == healer.name) then
			return action.debuff
		elseif (action.debuff ~= nil) and ((action.debuff.prio + 2) < action.cure.prio) then
			return action.debuff
		elseif (action.buff ~= nil) and ((action.buff.prio + 2) < action.cure.prio) then
			return action.buff
		end
		return action.cure
	elseif (action.debuff ~= nil) then
		if (action.buff ~= nil) and (action.buff.prio < action.debuff.prio) then
			return action.buff
		end
		return action.debuff
	elseif (action.buff ~= nil) then
		return action.buff
	end
	utils.check_recovery_item()
	return nil
end

function shouldBuff(bact, bact_target)
    local player = player or windower.ffxi.get_player()
    local buff_status = bact.msg or "always" -- Default to "Always" if no status specified
	
    return not (
        -- Skip if buff is already applied and is Haste/Flurry-related
        (buffs.debuffList[bact.name] and buffs.debuffList[bact.name][13] and S{'Haste', 'Haste II', 'Flurry', 'Flurry II'}:contains(bact.action.en)) or
    
        -- Skip if RDM is in party and player is not an RDM for certain buffs
        (utils.getPlayerNameFromJob('RDM') and S{'Phalanx', 'Haste', 'Refresh', 'Flurry'}:contains(bact.action.en) and player.main_job ~= 'RDM') or
		
		-- Skip if SCH is in party and player is not an SCH for certain buffs
        (utils.getPlayerNameFromJob('SCH') and S{'Aurorastorm', 'Voidstorm', 'Firestorm', 'Hailstorm ','Windstorm','Sandstorm','Thunderstorm','Rainstorm'}:contains(bact.action.en) and player.main_job ~= 'SCH') or
        
        -- Skip if WHM is in party and buff is Protect/Shell targeting the player
        (utils.getPlayerNameFromJob('WHM') and (bact.action.en:match("^Protect") or bact.action.en:match("^Shell")) and bact_target.name == player.name and player.main_job ~= 'WHM') or

        -- Check the buff status requirement
        (buff_status:lower() == "incombat" and not player.in_combat)
    )
end


function actions.take_action(player, partner, targ)
    if hb.aoe_action then
        healer:take_action(hb.aoe_action)
        return
    end
    buffs.checkOwnBuffs()
    local_queue_reset()
    local action = actions.get_defensive_action()
    if (action ~= nil) then         --If there's a defensive action to perform
        --Record attempt time for buffs/debuffs
        buffs.buffList[action.name] = buffs.buffList[action.name] or {}
        if (action.type == 'buff') and (buffs.buffList[action.name][action.buff]) then
            buffs.buffList[action.name][action.buff].attempted = os.clock()
        elseif (action.type == 'debuff') then
            buffs.debuffList[action.name][action.debuff.id].attempted = os.clock()
        end
        if action.action.accession then
            local accession = lor_res.action_for("Accession")
            if healer:can_use(accession) and utils.ready_to_use(accession) then
                healer:take_action({action=accession}, healer.name)
                hb.aoe_action = action
                return true
            end
        end
        healer:take_action(action)
		--Debuffs with BATTLE TARGET <BT>, has same priority as healing or buffing - will alternate.
		if offense.debuffing_battle_target and (windower.ffxi.get_mob_by_target('bt') or false) and next(offense.debuffs) then
			healer:take_action(actions.get_offensive_action(player, nil, true), '<bt>')
		end
		--Debuffs with moblist specified, has same priority as healing or buffing - will alternate.
		if offense.moblist.active and offense.moblist.mobs then
			actions.build_mob_debuff_list(player, offense.moblist.mobs)
		end
		--Dispel, has same priority as healing or buffing - will alternate.
		if offense.dispel.active and offense.dispel.mobs then
			actions.build_dispel_list(player, offense.dispel.mobs)
		end
		return true
    --Otherwise, there may be an offensive action(Debuffing or engage to attack)
    else             
		--Targetting or Independant mode.
        if (targ ~= nil) or hb.modes.independent or offense.job_ability_active then
            local self_engaged = (player.status == 1)
            if (targ ~= nil) then
				local partner_engaged = (partner.status == 1)
				if (player.target_index == partner.target_index) then
					if offense.assist.engage and partner_engaged and (not self_engaged) then
						healer:send_cmd('input /attack on')
						return true
					elseif offense.assist.engage and partner_engaged and self_engaged and (not player.target_locked) then
						healer:send_cmd('input /lockon')
						return true
					--Debuff actions with lock on target
					else
						if not actions.check_moblist_mob(player.target_index) then
							healer:take_action(actions.get_offensive_action(player, partner), '<t>')
						end
						if offense.moblist.active and offense.moblist.mobs then 
							actions.build_mob_debuff_list(player, offense.moblist.mobs)
						end
						if offense.dispel.active and offense.dispel.mobs then
							actions.build_dispel_list(player, offense.dispel.mobs)
						end
						return true
					end
				else   --Different targets
					--Assist but not engage
					if partner_engaged and (not self_engaged) and not (offense.assist.nolock) then
						healer:send_cmd('input /as '..offense.assist.name)
						return true
					--Assist + Debuffs with mob id, requires gearswap
					elseif (partner_engaged and partner.target_index and offense.assist.nolock) then
						if not actions.check_moblist_mob(partner.target_index) then
							healer:take_action(actions.get_offensive_action(player, partner), windower.ffxi.get_mob_by_index(partner.target_index).id)
						end
						if (hb.modes.independent and (self_engaged or (player.target_locked and utils.isMonster(player.target_index)))) then
							if not actions.check_moblist_mob(player.target_index) then
								healer:take_action(actions.get_offensive_action(player, nil), '<t>')
							end
						end
						if offense.moblist.active and offense.moblist.mobs then 
							actions.build_mob_debuff_list(player, offense.moblist.mobs)
						end
						if offense.dispel.active and offense.dispel.mobs then
							actions.build_dispel_list(player, offense.dispel.mobs)
						end
						return true
					--Switches target to same as partner
					elseif partner_engaged and partner.target_index and self_engaged and not (offense.assist.nolock) and offense.assist.sametarget then
						healer:switch_target(windower.ffxi.get_mob_by_index(partner.target_index).id)
						return true
					end
				end
			-- Debuff without having assist, either engaged or target locked.
            elseif ((hb.modes.independent or offense.job_ability_active) and (self_engaged or (player.target_locked and utils.isMonster(player.target_index)))) then
				if not actions.check_moblist_mob(player.target_index) then
					healer:take_action(actions.get_offensive_action(player, nil), '<t>')
				end
				if offense.moblist.active and offense.moblist.mobs then 
					actions.build_mob_debuff_list(player, offense.moblist.mobs)
				end
				if offense.dispel.active and offense.dispel.mobs then
					actions.build_dispel_list(player, offense.dispel.mobs)
				end
				return true
            end
		end
		--Debuffs with mobslist specified within debuffing block
		if offense.moblist.active and offense.moblist.mobs then
			actions.build_mob_debuff_list(player, offense.moblist.mobs)
        end
		if offense.dispel.active and offense.dispel.mobs then
			actions.build_dispel_list(player, offense.dispel.mobs)
		end
		if offense.debuffing_battle_target and (windower.ffxi.get_mob_by_target('bt') or false) and next(offense.debuffs) then
			healer:take_action(actions.get_offensive_action(player, nil, true), '<bt>')
		end
		return true
    end
	return false
end

--Builder for multiple dispel targets
function actions.build_dispel_list(player, moblist)
	for mob_id,mob_debuffs in pairs(moblist) do
		local dispel_target = windower.ffxi.get_mob_by_id(mob_id) and windower.ffxi.get_mob_by_id(mob_id).claim_id or nil
		if utils.check_claim_id(dispel_target) then
			healer:take_action(actions.get_dispel_action(player, mob_id), mob_id)
		end
	end
end

--Builder for list of mobs to debuff, accounting for same name mobs.
function actions.build_mob_debuff_list(player, moblist)
	mob_names = T(windower.ffxi.get_mob_list()):filter(set.contains+{moblist})
	for mob_index,mob_name in pairs(mob_names) do
		if utils.isMonster(mob_index) then
			healer:take_action(actions.get_offensive_action_list(player, mob_index), windower.ffxi.get_mob_by_index(mob_index).id)
		end
	end
end

function actions.check_moblist_mob(target_index)
	if not offense.moblist.mobs then return false end
--	local target_name = windower.ffxi.get_mob_by_index(target_index).name
	local target_name = windower.ffxi.get_mob_by_index(target_index or 0) and windower.ffxi.get_mob_by_index(target_index).name or "Unknown"
	
	for mob_name,_ in pairs(offense.moblist.mobs) do
		if target_name == mob_name then
			return true
		end
	end
	return false
end

local stymie = lor_res.action_for("Stymie")
local marcato = lor_res.action_for("Marcato")

function actions.get_offensive_action(player, partner, battle_target)
	player = player or windower.ffxi.get_player()
	local target
	if battle_target then
		target = windower.ffxi.get_mob_by_target('bt')
	else
		target = (partner and partner.target_index and windower.ffxi.get_mob_by_index(partner.target_index)) or windower.ffxi.get_mob_by_target()
	end
    if target == nil or target.hpp == 0 then return nil end
    local action = {}
	
    --Prioritize debuffs over nukes/ws
    local dbuffq = offense.getDebuffQueue(player, target)
    while not dbuffq:empty() do
        local dbact = dbuffq:pop()
        local_queue_insert(dbact.action.en, target.name)

		if player.main_job == "BRD" and offense.ja_prespell.marcato.active and healer:can_use(marcato) 
		and (healer:ready_to_use(marcato) or haveBuff(marcato.name))
		then
			if dbact.action.en == offense.ja_prespell.marcato.spell then
				if not haveBuff(marcato.name) then
					healer:take_action({action=marcato}, healer.name)
				end
				if haveBuff(marcato.name) then
					action.db = dbact
					break
				end
				break
			end
		elseif player.main_job == "RDM" and offense.ja_prespell.stymie.active and healer:can_use(stymie)
		and (healer:ready_to_use(stymie) or haveBuff(stymie.name))
		then
			if dbact.action.en == offense.ja_prespell.stymie.spell then
				if not haveBuff(stymie.name) then
					healer:take_action({action = stymie}, healer.name)
				end
				if haveBuff(stymie.name) then
					action.db = dbact
					break
				end
				break
			end
        else -- Other non pre JA debuffs
            if (action.db == nil) and healer:in_casting_range(target) and healer:ready_to_use(dbact.action) 
			and not actions.jaSpell(dbact)
			then
                action.db = dbact
            end
        end
    end

	 
    local_queue_disp()
    if action.db ~= nil then
        return action.db
    end
    
    if (not settings.disable.ws) and (settings.ws ~= nil) and healer:ready_to_use(lor_res.action_for(settings.ws.name)) then
        local sign = settings.ws.sign or '>'
        local hp = settings.ws.hp or 0
        local hp_ok = ((sign == '<') and (target.hpp <= hp)) or ((sign == '>') and (target.hpp >= hp))
        
        local partner_ok = true
        if (settings.ws.partner ~= nil) then
            local pname = settings.ws.partner.name
            local partner = ffxi.get_party_member(pname)
            if partner ~= nil then
                partner_ok = partner.tp >= settings.ws.partner.tp
            else
                partner_ok = false
                atc(123,'Unable to locate weaponskill partner '..pname)
            end
        end
        
        if (hp_ok and partner_ok) then
            return {action=lor_res.action_for(settings.ws.name),name='<t>'}
        end
    elseif (not settings.disable.spam) and settings.spam.active and (settings.spam.name ~= nil) then
        local spam_action = lor_res.action_for(settings.spam.name)
        if (target.hpp > 0) and healer:ready_to_use(spam_action) and healer:in_casting_range('<t>') then
			return {action=spam_action,name='<t>'}
        else
			atcd('MP/TP not ok for '..settings.spam.name)
        end
    end
    
    atcd('get_offensive_action: no offensive actions to perform')
	return nil
end

function actions.jaSpell(spell)
    for _, ja in pairs(offense.ja_prespell) do
        if ja.active and ja.spell == spell.action.en then
            return true
        end
    end
    return false
end
	
--Moblist debuff - with separate list if defined.  Otherwise use default debuffs
function actions.get_offensive_action_list(player, mob_index)
	player = player or windower.ffxi.get_player()
	local target = (windower.ffxi.get_mob_by_index(mob_index))
    if target == nil or target.hpp == 0 then return nil end
    local action = {}
    
    --Prioritize debuffs over nukes/ws
    local dbuffq = offense.getDebuffQueue(player, target, true)
    while not dbuffq:empty() do
        local dbact = dbuffq:pop()
        local_queue_insert(dbact.action.en, target.name)
		
		
		if player.main_job == "BRD" and offense.ja_prespell.marcato.active and healer:can_use(marcato) 
		and (healer:ready_to_use(marcato) or haveBuff(marcato.name))
		then
			if dbact.action.en == offense.ja_prespell.marcato.spell then
				if not haveBuff(marcato.name) then
					healer:take_action({action=marcato}, healer.name)
				end
				if haveBuff(marcato.name) then
					action.db = dbact
					break
				end
				break
			end
		elseif player.main_job == "RDM" and offense.ja_prespell.stymie.active and healer:can_use(stymie)
		and (healer:ready_to_use(stymie) or haveBuff(stymie.name))
		then
			if dbact.action.en == offense.ja_prespell.stymie.spell then
				if not haveBuff(stymie.name) then
					healer:take_action({action = stymie}, healer.name)
				end
				if haveBuff(stymie.name) then
					action.db = dbact
					break
				end
				break
			end
		else -- Other non pre JA debuffs
			if (action.db == nil) and healer:in_casting_range(target) and healer:ready_to_use(dbact.action) 
			and not actions.jaSpell(dbact)
			then
                action.db = dbact
            end
		end
    end
    
    local_queue_disp()
    if action.db ~= nil then
        return action.db
    end
   
    atcd('get_offensive_action: no offensive actions to perform')
	return nil
end

function actions.get_dispel_action(player, mob_id)
	player = player or windower.ffxi.get_player()
	local target = (windower.ffxi.get_mob_by_id(mob_id))
    if target == nil or target.hpp == 0 then return nil end
    local action = {}
    
    --Prioritize debuffs over nukes/ws
    local dbuffq = offense.getDispelQueue(player, target)
    while not dbuffq:empty() do
        local dbact = dbuffq:pop()
        local_queue_insert(dbact.action.en, target.name)
        if (action.db == nil) and healer:in_casting_range(target) and healer:ready_to_use(dbact.action) then
            action.db = dbact
        end
    end
    
    local_queue_disp()
    if action.db ~= nil then
        return action.db
    end
	return nil
end

return actions

--==============================================================================
--[[
Copyright © 2016, Lorand
All rights reserved.
Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
    * Neither the name of ffxiHealer nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL Lorand BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--]]
--==============================================================================
