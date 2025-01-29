--==============================================================================
--[[
    Author: Ragnarok.Lorand
    HealBot utility functions that don't belong anywhere else
--]]
--==============================================================================
--          Input Handling Functions
--==============================================================================

utils = {normalize={}}
local lor_res = _libs.lor.resources
local lc_res = lor_res.lc_res
local ffxi = _libs.lor.ffxi
local debuffs_lists = L()

function utils.normalize_str(str)
    return str:lower():gsub(' ', '_'):gsub('%.', '')
end
math.randomseed(os.time() + os.clock() * 1000)

function utils.normalize_action(action, action_type)
    if istable(action) then return action end
    if action_type == nil then return nil end
    if isstr(action) then
        if tonumber(action) == nil then
            local naction = res[action_type]:with('en', action)
            if naction ~= nil then
                return naction
            end
            return res[action_type]:with('enn', utils.normalize_str(action))
        end
        action = tonumber(action) 
    end
    if isnum(action) then
        return res[action_type][action]
    end
    --atcf("Unable to normalize: '%s'[%s] (%s)", tostring(action), type(action), tostring(action_type))
    return nil
end


function utils.strip_roman_numerals(str)
    --return str:sub(1, str:find('I*V?X?I*V?I*$')):trim()
    return str:match('^%s*(.-)%s*I*V?X?I*V?I*$')
end


--[[
    Add an 'enn' (english, normalized) entry to each relevant resource
--]]
local function normalize_action_names()
    local categories = {'spells', 'job_abilities', 'weapon_skills', 'buffs'}
    for _,cat in pairs(categories) do
        for id,entry in pairs(res[cat]) do
            res[cat][id].enn = utils.normalize_str(entry.en)
            res[cat][id].ja = nil
            res[cat][id].jal = nil
        end
    end
end
normalize_action_names()


local txtbox_cmd_map = {
    moveinfo = 'moveInfo',          actioninfo = 'actionInfo',
    showq = 'actionQueue',          showqueue = 'actionQueue',
    queue = 'actionQueue',          monitored = 'montoredBox',
    showmonitored = 'montoredBox',
}

function processCommand(command,...)
    command = command and command:lower() or 'help'
    local args = map(windower.convert_auto_trans, {...})
	local player = windower.ffxi.get_player()
	
	local fourth_param = nil
	local argswithforth = {unpack(args)}
    if #argswithforth > 0 then
		-- Remove and capture the last argument from the copied table
		fourth_param = table.remove(argswithforth)

		-- Validate the fourth_param
		if not S{'always', 'incombat'}:contains(fourth_param:lower()) then
			fourth_param = nil
		end
	end
    
    if S{'reload','unload'}:contains(command) then
		windower.send_command(('lua %s %s'):format(command, 'healbot'))
    elseif command == 'refresh' then
	    utils.load_configs()
	elseif S{'show','sh'}:contains(command) then
		if (args[1] and args[1]:lower() == 'party') or not args[1] then
			atc('Party Debuff Table:')
			table.vprint(buffs.debuffList)
		end
		if (args[1] and args[1]:lower() == 'aura') or not args[1] then
			atc('Aura Table:')
			table.vprint(buffs.auras)
		end
		if (args[1] and args[1]:lower() == 'ignore') or not args[1] then
			atc('Ignored Debuff Table:')
			table.vprint(buffs.ignored_debuffs)
		end
		if (args[1] and args[1]:lower() == 'offense') or not args[1] then
			atc('Offense Table:')
			table.vprint(offense.mobs)
		end
		if (args[1] and args[1]:lower() == 'debuff') or not args[1] then
			atc('Offense debuffs table:')
			table.vprint(offense.debuffs)
		end
		if (args[1] and args[1]:lower() == 'dispel') or not args[1] then
			atc('Dispel table:')
			table.vprint(offense.dispel.mobs)
		end
		if (args[1] and args[1]:lower() == 'follow') or not args[1] then
			local targ_value = settings.follow.target or 'NIL'
			atc('Follow target: '..targ_value)
		end
		if (args[1] and args[1]:lower() == 'buffs') or not args[1] then
			atc('Buffs table: ')
			table.vprint(buffs.buffList)
		end
		if (args[1] and args[1]:lower() == 'ws') or not args[1] then
			atc('WS tracker: ')
			table.vprint(offense.weaponskilltracker)
		end
		if (args[1] and args[1]:lower() == 'moblist') or not args[1] then
			atc('moblist: ')
			table.vprint(offense.moblist.mobs)
		end
		if (args[1] and args[1]:lower() == 'moblistdebuff') or not args[1] then
			atc('moblist debuffs: ')
			table.vprint(offense.moblist.debuffs)
		end
		if (args[1] and args[1]:lower() == 'shots') or not args[1] then
			atc('corsair shots: ')
			table.vprint(light_shot_tracker)
			table.vprint(ice_shot_tracker)
			table.vprint(earth_shot_tracker)						
		end
    elseif S{'start','on'}:contains(command) then
        hb.activate()
    elseif S{'stop','end','off'}:contains(command) then
        hb.active = false
        printStatus()
    elseif S{'aoe'}:contains(command) then
        local cmd = args[1] and args[1]:lower() or (settings.aoe_na and 'off' or 'resume')
        if S{'off','end','false','pause'}:contains(cmd) then
            settings.aoe_na = false
            atc('AOE is now off.')
        else
            settings.aoe_na = true
			atc('AOE is active.')
        end
	elseif S{'dispel'}:contains(command) then
		local cmd = args[1] and args[1]:lower() or (offense.dispel.active and 'off' or 'resume')
		if S{'off','end','false','pause'}:contains(cmd) then
			offense.dispel.active = false
			atc('Auto Dispel is now off.')
		elseif S{'resume','on'}:contains(cmd) then
			offense.dispel.active = true
			atc('Auto Dispel is now active.')
		elseif cmd == 'ignore' then
			local mob_string = args[2]:lower():capitalize()
			offense.dispel.ignored:add(mob_string)
			atc('Added mob to dispel ignore list: '..mob_string)
		elseif cmd == 'unignore' then
			local mob_string = args[2]:lower():capitalize()
			if offense.dispel.ignored:contains(mob_string) then
				offense.dispel.ignored:remove(mob_string)
				atc('Removed mob from dispel ignore list: '..mob_string)
				local show_dispel_ignore_names = ''
				for k,v in pairs(offense.dispel.ignored) do
					show_dispel_ignore_names = show_dispel_ignore_names..'['..k..']'
				end
				atc('Dispel Ignore List: '..show_dispel_ignore_names)
			else
				atc('Error: Mob not in current list')
			end
		end
    elseif S{'disable'}:contains(command) then
        if not validate(args, 1, 'Error: No argument specified for Disable') then return end
        disableCommand(args[1]:lower(), true)
    elseif S{'enable'}:contains(command) then
        if not validate(args, 1, 'Error: No argument specified for Enable') then return end 
        disableCommand(args[1]:lower(), false)
	 elseif S{'moblist'}:contains(command) then
		local cmd = args[1] and args[1]:lower() or (offense.moblist.active and 'off' or 'resume')
		if S{'off','end','false','pause'}:contains(cmd) then
			offense.moblist.active = false
			atc('Moblist debuffing is now off.')
		elseif S{'resume','on'}:contains(cmd) then
			offense.moblist.active = true
			atc('Moblist debuffing is now active.')
		elseif cmd == 'add' and args[2] then
			local mob_string = args[2]:lower():capitalize()
			offense.moblist.mobs:add(mob_string)
			atc('Added mob to debuff list: '..mob_string)
		elseif cmd == 'remove' and args[2] then
			local mob_string = args[2]:lower():capitalize()
			if offense.moblist.mobs:contains(mob_string) then
				offense.moblist.mobs:remove(mob_string)
				atc('Removed mob from debuff list: '..mob_string)
				local show_moblist_names = ''
				for k,v in pairs(offense.moblist.mobs) do
					show_moblist_names = show_moblist_names..'['..k..']'
				end
				atc('Debuff Mob List: '..show_moblist_names)
			else
				atc('Error: Mob not in current list')
			end
		elseif (cmd == 'show' or cmd == 'list') and offense.moblist.mobs then
			local show_moblist_names = ''
			for k,v in pairs(offense.moblist.mobs) do
				show_moblist_names = show_moblist_names..'['..k..']'
			end
			atc('Debuff Mob List: '..show_moblist_names)
		elseif cmd == 'clear' then
			offense.moblist.mobs:clear()
			atc('Debuff Mob List cleared')
		else
			atc(123,'Error: No parameter - [add / remove / on / off / clear] specified.')
		end
    elseif S{'assist','as'}:contains(command) then
        local cmd = args[1] and args[1]:lower() or (offense.assist.active and 'off' or 'resume')
        if S{'off','end','false','pause'}:contains(cmd) then
            offense.assist.active = false
            atc('Assist is now off.')
        elseif S{'resume'}:contains(cmd) then
            if (offense.assist.name ~= nil) then
                offense.assist.active = true
                atc('Now assisting '..offense.assist.name..'.')
            else
                atc(123,'Error: Unable to resume assist - no target set')
            end
        elseif S{'attack','engage'}:contains(cmd) then
            local cmd2 = args[2] and args[2]:lower() or (offense.assist.engage and 'off' or 'resume')
            if S{'off','end','false','pause'}:contains(cmd2) then
                offense.assist.engage = false
                atc('Will no longer enagage when assisting.')
            else
                if not (offense.assist.nolock) then
                    offense.assist.engage = true
                    atc('Will now enagage when assisting.')
                else
                    offense.assist.engage = false
					atc('ERROR: Cannot engage/attack to assist if using nolock.')
                end
            end
		elseif S{'nolock'}:contains(cmd) then
            local cmd2 = args[2] and args[2]:lower() or (offense.assist.nolock and 'off' or 'resume')
            if S{'off','end','false','pause'}:contains(cmd2) then
                offense.assist.nolock = false
                atc('Will now use target/lock on when assisting.')
            else
				if not (offense.assist.engage) then
					offense.assist.nolock = true
					atc('Will now use mob id to cast spells when assisting.')
				else
					offense.assist.nolock = false
					atc('ERROR: Cannot use nolock/mob id to assist if engaging to attack.')
				end
            end
        elseif S{'sametarget'}:contains(cmd) then
            local cmd2 = args[2] and args[2]:lower() or (offense.assist.sametarget and 'off' or 'resume')
            if S{'off','end','false','pause'}:contains(cmd2) then
                offense.assist.sametarget = false
                atc('Will now NOT switch to the SAME mob when engaged.')
            else
				if not (offense.assist.nolock) and offense.assist.engage then
					offense.assist.sametarget = true
					atc('Will now switch to the same mob when attack/engage to assist.')
				else
					offense.assist.sametarget = false
					atc('ERROR: Cannot use sametarget to attack/engage if using [nolock] or not [attack/engage].')
				end
            end
		elseif S{'job','j'}:contains(cmd) then
			if args[2] then
				offense.register_assistee(args[2],true)
			else
				atc('ERROR: No JOB specified.')
			end
        else    --args[1] is guaranteed to have a value if this is reached
            offense.register_assistee(args[1])
        end
    elseif S{'ws','weaponskill'}:contains(command) then
        local lte,gte = string.char(0x81, 0x85),string.char(0x81, 0x86)
        local cmd = args[1] and args[1] or ''
        settings.ws = settings.ws or {}
        if (cmd == 'waitfor') then      --another player's TP
            local partner = utils.getPlayerName(args[2])
            if (partner ~= nil) then
                local partnertp = tonumber(args[3]) or 1000
                settings.ws.partner = {name=partner,tp=partnertp}
                atc("Will weaponskill when "..partner.."'s TP is "..gte.." "..partnertp)
            else
                atc(123,'Error: Invalid argument for ws waitfor: '..tostring(args[2]))
            end
        elseif (cmd == 'nopartner') then
            settings.ws.partner = nil
            atc('Weaponskill partner removed.')
        elseif (cmd == 'hp') then       --Target's HP
            local sign = S{'<','>'}:contains(args[2]) and args[2] or nil
            local hp = tonumber(args[3])
            if (sign ~= nil) and (hp ~= nil) then
                settings.ws.sign = sign
                settings.ws.hp = hp
                atc("Will weaponskill when the target's HP is "..sign.." "..hp.."%")
            else
                atc(123,'Error: Invalid arguments for ws hp: '..tostring(args[2])..', '..tostring(args[3]))
            end
        else
            if S{'use','set'}:contains(cmd) then    -- ws name
                table.remove(args, 1)
            end
            utils.register_ws(args)
        end
    elseif S{'spam','nuke'}:contains(command) then
        local cmd = args[1] and args[1]:lower() or (settings.spam.active and 'off' or 'on')
        if S{'on','true'}:contains(cmd) then
            settings.spam.active = true
            if (settings.spam.name ~= nil) then
                atc('Action spamming is now on. Action: '..settings.spam.name)
            else
                atc('Action spamming is now on. To set a spell to use: //hb spam use <action>')
            end
        elseif S{'off','false'}:contains(cmd) then
            settings.spam.active = false
            atc('Action spamming is now off.')
        else
            if S{'use','set'}:contains(cmd) then
                table.remove(args, 1)
            end
            utils.register_spam_action(args)
        end
	elseif S{'autojamode'}:contains(command) then
		local cmd = args[1] and args[1]:lower() or (offense.job_ability_active and 'off' or 'on')
		if S{'on','true'}:contains(cmd) then
			offense.job_ability_active = true
			atc('Auto JA Mode is now on.')
		elseif S{'off','false'}:contains(cmd) then
			offense.job_ability_active = false
			atc('Auto JA Mode is now off.')
		end
	elseif S{'stymie'}:contains(command) then
		utils.handle_ja_command(command, 'stymie', 'RDM', function(args) utils.register_ja(args, 'stymie') end, args)

	elseif S{'sabo'}:contains(command) then
		utils.handle_ja_command(command, 'sabo', 'RDM', function(args) utils.register_ja(args, 'sabo') end, args)

	elseif S{'marcato'}:contains(command) then
		utils.handle_ja_command(command, 'marcato', 'BRD', function(args) utils.register_ja(args, 'marcato') end, args)

    elseif S{'debuff', 'db'}:contains(command) then
        local cmd = args[1] and args[1]:lower() or (offense.debuffing_active and 'off' or 'on')
        if S{'on','true'}:contains(cmd) then
            offense.debuffing_active = true
            atc('Debuffing is now on.')
        elseif S{'off','false'}:contains(cmd) then
            offense.debuffing_active = false
            atc('Debuffing is now off.')
		elseif S{'bt'}:contains(cmd) then
			local battle_cmd = args[2] and args[2]:lower() or (offense.debuffing_battle_target and 'off' or 'on')
			if S{'on','true'}:contains(battle_cmd) then
				offense.debuffing_active = true
				offense.debuffing_battle_target = true
				atc('WARNING! Debuffing is now set to battle targets.')
			elseif S{'off','false'}:contains(battle_cmd) then
				offense.debuffing_battle_target = false
				atc('DISABLED debuffing on battle targets.')
			end
        elseif S{'rm','remove'}:contains(cmd) then
            utils.register_offensive_debuff(table.slice(args, 2), true)
        elseif S{'ls','list'}:contains(cmd) then
			local debuff_print = ''
			for k,v in pairs(offense.debuffs) do
				debuff_print = debuff_print..offense.debuffs[k].spell.en..','
			end
			atc('Debuffs: '..debuff_print)
        else
            if S{'use','set'}:contains(cmd) then
                table.remove(args, 1)
            end
            utils.register_offensive_debuff(args, false)
        end
	elseif S{'jadebuff', 'jadb'}:contains(command) then
        local cmd = args[1] and args[1]:lower() 
        if S{'rm','remove'}:contains(cmd) then
            utils.register_offensive_debuff(table.slice(args, 2), true)
        elseif S{'ls','list'}:contains(cmd) then
			local debuff_print = ''
			for k,v in pairs(offense.debuffs) do
				debuff_print = debuff_print..offense.debuffs[k].ja.en..','
			end
			atc('Debuffs: '..debuff_print)
        else
            if S{'use','set'}:contains(cmd) then
                table.remove(args, 1)
            end
            utils.register_offensive_debuff(args, false, false ,true)
        end
	elseif S{'mldebuff', 'mldb'}:contains(command) then
		local cmd = args[1] and args[1]:lower() 
        if S{'rm','remove'}:contains(cmd) then
            utils.register_offensive_debuff(table.slice(args, 2), true, true)
        elseif S{'ls','list'}:contains(cmd) then
            local debuff_print = ''
			for k,v in pairs(offense.moblist.debuffs) do
				debuff_print = debuff_print..offense.moblist.debuffs[k].spell.en..','
			end
			atc('Debuffs for Moblist: '..debuff_print)
        else
            if S{'use','set'}:contains(cmd) then
                table.remove(args, 1)
            end
            utils.register_offensive_debuff(args, false, true)
        end
	elseif S{'mljadebuff', 'mljadb'}:contains(command) then
		local cmd = args[1] and args[1]:lower() 
        if S{'rm','remove'}:contains(cmd) then
            utils.register_offensive_debuff(table.slice(args, 2), true, true, true)
        elseif S{'ls','list'}:contains(cmd) then
            local debuff_print = ''
			for k,v in pairs(offense.moblist.debuffs) do
				debuff_print = debuff_print..offense.moblist.debuffs[k].spell.en..','
			end
			atc('Debuffs for Moblist: '..debuff_print)
        else
            if S{'use','set'}:contains(cmd) then
                table.remove(args, 1)
            end
            utils.register_offensive_debuff(args, false, true, true)
        end
	elseif command == 'backup' then
        local cmd = args[1] and args[1]:lower() or (settings.healing.backup and 'off' or 'on')
		if S{'on','true'}:contains(cmd) then
			settings.healing.backup = true
			atc('Backup Healer Mode is now on.')
		elseif S{'off','false'}:contains(cmd) then
			settings.healing.backup = false
			atc('Backup Healer Mode is now off.')
		end
		
    elseif command == 'mincure' then
        if not validate(args, 1, 'Error: No argument specified for minCure') then return end
        local val = tonumber(args[1])
        if (val ~= nil) and (1 <= val) and (val <= 6) then
            settings.healing.min.cure = val
            atc('Minimum cure tier set to '..val)
        else
            atc('Error: Invalid argument specified for minCure')
        end
    elseif command == 'mincuraga' then
        if not validate(args, 1, 'Error: No argument specified for minCuraga') then return end
        local val = tonumber(args[1])
        if (val ~= nil) and (1 <= val) and (val <= 6) then
            settings.healing.min.curaga = val
            atc('Minimum curaga tier set to '..val)
        else
            atc('Error: Invalid argument specified for minCuraga')
        end
    elseif command == 'minwaltz' then
        if not validate(args, 1, 'Error: No argument specified for minWaltz') then return end
        local val = tonumber(args[1])
        if (val ~= nil) and (1 <= val) and (val <= 5) then
            settings.healing.min.waltz = val
            atc('Minimum waltz tier set to '..val)
        else
            atc('Error: Invalid argument specified for minWaltz')
        end
    elseif command == 'minwaltzga' then
        if not validate(args, 1, 'Error: No argument specified for minWaltzga') then return end
        local val = tonumber(args[1])
        if (val ~= nil) and (1 <= val) and (val <= 2) then
            settings.healing.min.waltzga = val
            atc('Minimum waltzga tier set to '..val)
        else
            atc('Error: Invalid argument specified for minWaltzga')
        end
    elseif command == 'minblue' then
        if not validate(args, 1, 'Error: No argument specified for minBlue') then return end
        local val = tonumber(args[1])
        if (val ~= nil) and (1 <= val) and (val <= 4) then
            settings.healing.min.blue = val
            atc('Minimum blue tier set to '..val)
        else
            atc('Error: Invalid argument specified for minBlue')
        end
    elseif command == 'minbluega' then
        if not validate(args, 1, 'Error: No argument specified for minBluega') then return end
        local val = tonumber(args[1])
        if (val ~= nil) and (1 <= val) and (val <= 2) then
            settings.healing.min.bluega = val
            atc('Minimum bluega tier set to '..val)
        else
            atc('Error: Invalid argument specified for minBluega')
        end
    elseif command == 'reset' then
		utils.reset_to_defaults()
    elseif command == 'buff' then
		if fourth_param then
			buffs.registerNewBuff(argswithforth, true, false, fourth_param)
		else
			buffs.registerNewBuff(args, true)
		end
	elseif command == 'buffjob' then
		if fourth_param then
			buffs.registerNewBuff(argswithforth, true, true, fourth_param)
		else
			buffs.registerNewBuff(args, true, true)
		end
    elseif S{'cancelbuff','nobuff'}:contains(command) then
        buffs.registerNewBuff(args, false)
	elseif S{'cancelbuffjob','nobuffjob'}:contains(command) then
        buffs.registerNewBuff(args, false, true)
    elseif S{'bufflist','bl'}:contains(command) then
        if not validate(args, 1, 'Error: No argument specified for BuffList') then return end
        utils.apply_bufflist(args)
    elseif command == 'bufflists' then
        pprint(hb.config.buff_lists)
    elseif command == 'ignore_debuff' then
        buffs.registerIgnoreDebuff(args, true)
    elseif command == 'unignore_debuff' then
        buffs.registerIgnoreDebuff(args, false)
    elseif S{'follow','f'}:contains(command) then
        local cmd = args[1] and args[1]:lower() or (settings.follow.active and 'off' or 'resume')
        if S{'off','end','false','pause','stop','exit'}:contains(cmd) then
			atc('Follow is now off.')
            settings.follow.active = false
			settings.follow.target = nil
        elseif S{'distance', 'dist', 'd'}:contains(cmd) then
            local dist = tonumber(args[2])
            if (dist ~= nil) and (0 < dist) and (dist < 45) then
                settings.follow.distance = dist
                atc('Follow distance set to '..settings.follow.distance)
            else
                atc('Error: Invalid argument specified for follow distance')
            end
        elseif S{'resume'}:contains(cmd) then
            if (settings.follow.target ~= nil) then
                settings.follow.active = true
                atc('Now following '..settings.follow.target..'.')
            else
                atc(123,'Error: Unable to resume follow - no target set')
            end
		elseif S{'job', 'j'}:contains(cmd) then
		    local pname = utils.getPlayerNameFromJob(args[2])
			if (pname ~= nil) then
                settings.follow.target = pname
                settings.follow.active = true
                atc('Now following '..settings.follow.target..'.')
            else
                atc(123,'Error: Invalid JOB provided as a follow target: '..tostring(args[2]))
            end
        else    --args[1] is guaranteed to have a value if this is reached
            local pname = utils.getPlayerName(args[1])
            if (pname ~= nil) then
                settings.follow.target = pname
                settings.follow.active = true
                atc('Now following '..settings.follow.target..'.')
            else
                atc(123,'Error: Invalid name provided as a follow target: '..tostring(args[1]))
            end
        end
    elseif S{'ignore', 'unignore', 'watch', 'unwatch'}:contains(command) then
        monitorCommand(command, args[1])
	elseif command == 'watchall' then
        if watchall == false then
            watchall = true
            atc(123,'Watch all parties set to true.')
        elseif watchall == true then
            watchall = false
            atc(123,'Watch all parties set to false.')
        end
	elseif S{'gaze'}:contains(command) then
		local cmd = args[1] and args[1]:lower() or (hb.gaze and 'off' or 'on')
        if S{'on','true'}:contains(cmd) then
            hb.gaze = true
            atc('Auto point at mob is ON.')
        elseif S{'off','false'}:contains(cmd) then
            hb.gaze = false
            atc('Auto point at mob is OFF.')
		end
	elseif S{'showdebuff'}:contains(command) then
		local cmd = args[1] and args[1]:lower() or (hb.showdebuff and 'off' or 'on')
        if S{'on','true'}:contains(cmd) then
            hb.showdebuff = true
            atc('Debuff List is displayed.')
			hb.txts.debuffList:visible(true)
        elseif S{'off','false'}:contains(cmd) then
            hb.showdebuff = false
			hb.txts.debuffList:visible(false)
            atc('Debuff List is hidden.')
		end
	elseif S{'automp'}:contains(command) then
		local cmd = args[1] and args[1]:lower() or (hb.autoRecoverMPMode and 'off' or 'on')
        if S{'on','true'}:contains(cmd) then
            hb.autoRecoverMPMode = true
            atc('Auto Recover MP [Coalition Ether] is ON.')
        elseif S{'off','false'}:contains(cmd) then
			hb.autoRecoverMPMode = false
            atc('Auto Recover MP [Coalition Ether] is OFF.')
		end
	elseif S{'autohp'}:contains(command) then
		local cmd = args[1] and args[1]:lower() or (hb.autoRecoverHPMode and 'off' or 'on')
        if S{'on','true'}:contains(cmd) then
            hb.autoRecoverHPMode = true
            atc('Auto Recover HP [Vile Elixir] is ON.')
        elseif S{'off','false'}:contains(cmd) then
			hb.autoRecoverHPMode = false
            atc('Auto Recover HP [Vile Elixir] is OFF.')
		end
    elseif command == 'ignoretrusts' then
        utils.toggleX(settings, 'ignoreTrusts', args[1], 'Ignoring of Trust NPCs', 'IgnoreTrusts')
    elseif command == 'packetinfo' then
        toggleMode('showPacketInfo', args[1], 'Packet info display', 'PacketInfo')
    elseif command == 'debug' then
        toggleMode('debug', args[1], 'Debug mode', 'debug mode')
    elseif S{'ind', 'independent'}:contains(command) then
        toggleMode('independent', args[1], 'Independent mode', 'independent mode')
    elseif S{'deactivateindoors','deactivate_indoors'}:contains(command) then
        utils.toggleX(settings, 'deactivateIndoors', args[1], 'Deactivation in indoor zones', 'DeactivateIndoors')
    elseif S{'activateoutdoors','activate_outdoors'}:contains(command) then
        utils.toggleX(settings, 'activateOutdoors', args[1], 'Activation in outdoor zones', 'ActivateOutdoors')
    elseif txtbox_cmd_map[command] ~= nil then
        local boxName = txtbox_cmd_map[command]
        if utils.posCommand(boxName, args) then
            utils.refresh_textBoxes()
        else
            utils.toggleVisible(boxName, args[1])
        end
    elseif S{'help','--help'}:contains(command) then
        help_text()
    elseif command == 'settings' then
        for k,v in pairs(settings) do
            local kstr = tostring(k)
            local vstr = (type(v) == 'table') and tostring(T(v)) or tostring(v)
            atc(kstr:rpad(' ',15)..': '..vstr)
        end
    elseif command == 'status' then
        printStatus()
	elseif command == 'jobupdate' then
		request_job_registry()
    elseif command == 'info' then
        if not _libs.lor.exec then
            atc(3,'Unable to parse info.  Windower/addons/libs/lor/lor_exec.lua was unable to be loaded.')
            atc(3,'If you would like to use this function, please visit https://github.com/lorand-ffxi/lor_libs to download it.')
            return
        end
        local cmd = args[1]     --Take the first element as the command
        table.remove(args, 1)   --Remove the first from the list of args
        _libs.lor.exec.process_input(cmd, args)
    else
        atc('Error: Unknown command')
    end
end

function utils.reset_to_defaults()
	-- hb.reset()
	-- offense.reset()
	-- buffs.reset()
	-- buffs.resetBuffTimers('ALL')
    -- buffs.resetDebuffTimers('ALL')
	-- utils.load_configs()
	-- CureUtils.init_cure_potencies()
	-- log('reset')
end



local function _get_player_id(player_name)
    local player_mob = windower.ffxi.get_mob_by_name(player_name)
    if player_mob then
        return player_mob.id
    end
    return nil
end
utils.get_player_id = _libs.lor.advutils.scached(_get_player_id)


function utils.register_offensive_debuff(args, cancel, mob_debuff_list_flag, ja_flag)
    local argstr = table.concat(args,' ')
    local snames = argstr:split(',')
    for index,sname in pairs(snames) do
        if (tostring(index) ~= 'n') then
            if sname:lower() == 'all' and cancel then
				if mob_debuff_list_flag then
					atcf(123,'Removing all debuffs from moblist debuff list.')
					for k,v in pairs(offense.moblist.debuffs) do
						atcf('Removing debuff: ' ..offense.moblist.debuffs[k].spell.enn)
						offense.moblist.debuffs[k] = nil
					end
				else
					atcf(123,'Removing all debuffs on mobs.')
					for k,v in pairs(offense.debuffs) do
						atcf('Removing debuff: ' ..offense.debuffs[k].spell.enn)
						offense.debuffs[k] = nil
					end
				end
            else
				if ja_flag then
					local ja_name = utils.formatActionName(sname:trim())
					local ja = lor_res.action_for(ja_name)
					if (ja ~= nil) then
						if healer:can_use(ja) then
							if mob_debuff_list_flag then
								offense.maintain_debuff_ja(ja, cancel, true)
							else
								offense.maintain_debuff_ja(ja, cancel)
							end
						else
							atcfs(123,'Error: Unable to use %s', ja.en)
						end
					else
						atcfs(123,'Error: Invalid ja name: %s', ja)
					end
					
				else
					local spell_name = utils.formatActionName(sname:trim())
					local spell = lor_res.action_for(spell_name)
					if (spell ~= nil) then
						if healer:can_use(spell) then
							if mob_debuff_list_flag then
								offense.maintain_debuff(spell, cancel, true)
							else
								offense.maintain_debuff(spell, cancel)
							end
						else
							atcfs(123,'Error: Unable to cast %s', spell.en)
						end
					else
						atcfs(123,'Error: Invalid spell name: %s', spell_name)
					end
				end
            end
        end
    end
end

function utils.handle_ja_command(command, ja_name, job_required, register_function, args)
	local player = windower.ffxi.get_player()
    if player.main_job == job_required then
        local cmd = args[1] and args[1]:lower() or (offense.ja_prespell[ja_name].active and 'off' or 'on')
        
        if S{'on', 'true'}:contains(cmd) then
            offense.ja_prespell[ja_name].active = true
            if offense.ja_prespell[ja_name].spell ~= '' then
                atc(ja_name:capitalize() .. ' is now on. Action: ' .. offense.ja_prespell[ja_name].spell)
            else
                atc(ja_name:capitalize() .. ' is now on. To set a spell to use: //hb ' .. ja_name .. ' use <action>')
            end
        elseif S{'off', 'false'}:contains(cmd) then
            offense.ja_prespell[ja_name].active = false
            atc(ja_name:capitalize() .. ' is now off.')
        else
            if S{'use', 'set'}:contains(cmd) then
                table.remove(args, 1)
            end
            register_function(args)
        end
    else
        atc('Error: Not ' .. job_required .. ' main job')
    end
end

function utils.register_ja(args, ja_name)
    local argstr = table.concat(args, ' ')
    local action_name = utils.formatActionName(argstr)
    local action = lor_res.action_for(action_name)

    if action ~= nil then
        if healer:can_use(action) then
            offense.ja_prespell[ja_name].spell = action.en
            offense.maintain_debuff(action, false)
            atc('Will now use ' .. ja_name:capitalize() .. ' with spell: ' .. offense.ja_prespell[ja_name].spell)
        else
            atc(123, 'Error: Unable to cast: ' .. action.en)
        end
    else
        atc(123, 'Error: Invalid action name: ' .. action_name)
    end
end


function utils.register_spam_action(args)
    local argstr = table.concat(args,' ')
    local action_name = utils.formatActionName(argstr)
    local action = lor_res.action_for(action_name)
    if (action ~= nil) then
        if healer:can_use(action) then
            settings.spam.name = action.en
            atcfs('Will now spam %s', settings.spam.name)
        else
            atcfs(123,'Error: Unable to cast %s', action.en)
        end
    else
        atcfs(123,'Error: Invalid action name: %s', action_name)
    end
end


function utils.register_ws(args)
    local argstr = table.concat(args,' ')
    local wsname = utils.formatActionName(argstr)
    local ws = lor_res.action_for(wsname)
    if (ws ~= nil) then
        settings.ws.name = ws.en
        atcfs('Will now use %s', ws.en)
    else
        atcfs(123,'Error: Invalid weaponskill name: %s', wsname)
    end
end

function utils.apply_bufflist(args)
    local mj = windower.ffxi.get_player().main_job
    local sj = windower.ffxi.get_player().sub_job
    local job = ('%s/%s'):format(mj, sj)
    local bl_name = args[1]
    local bl_target = args[2] or 'me'

	local fakeargs = { "me", "all" }
	buffs.registerNewBuff(fakeargs, false)
    local buff_list = table.get_nested_value(hb.config.buff_lists, {job, job:lower(), mj, mj:lower()}, bl_name)
    buff_list = buff_list or hb.config.buff_lists[bl_name]
    
    if buff_list ~= nil then
        for _, buff_entry in pairs(buff_list) do
            if buff_entry.name then
				local status = buff_entry.status or "always"
                buffs.registerNewBuff({bl_target, buff_entry.name}, true, false, status)
            end
        end
    else
        atc('Error: Invalid argument specified for BuffList: ' .. bl_name)
    end
end

function utils.auto_apply_bufflist()
    local mj = windower.ffxi.get_player().main_job
    local sj = windower.ffxi.get_player().sub_job
    local job = ('%s/%s'):format(mj, sj):lower()
    local bl_target = 'me'

    local buff_list = hb.config.buff_lists[job] or hb.config.buff_lists[mj:lower()]
    
    if buff_list ~= nil then
        for _, buff_entry in pairs(buff_list) do
            if buff_entry.name then
				local status = buff_entry.status or "always"
                buffs.registerNewBuff({bl_target, buff_entry.name}, true, false, status)
            end
        end
    else
        atc('Job has no initial BuffList: ' .. job)
    end
end

function utils.auto_apply_autojalist()
    local mj = windower.ffxi.get_player().main_job
    local sj = windower.ffxi.get_player().sub_job
    local job = ('%s/%s'):format(mj, sj):lower()
    local bl_target = 'me'

    local ja_list = hb.config.auto_ja_lists[job] or hb.config.auto_ja_lists[mj:lower()] or hb.config.auto_ja_lists[sj:lower()]
    
    if ja_list ~= nil then
        for _, debuff_entry in pairs(ja_list) do
            if debuff_entry.name then
				local status = debuff_entry.status or "always"
				utils.register_offensive_debuff({debuff_entry.name}, false, false, true)
            end
        end
    else
        atc('Job has no initial JAList: ' .. job)
    end
end


function utils.posCommand(boxName, args)
    if (args[1] == nil) or (args[2] == nil) then return false end
    local cmd = args[1]:lower()
    if not S{'pos','posx','posy'}:contains(cmd) then
        return false
    end
    local x,y = tonumber(args[2]),tonumber(args[3])
    if (cmd == 'pos') then
        if (x == nil) or (y == nil) then return false end
        settings.textBoxes[boxName].x = x
        settings.textBoxes[boxName].y = y
    elseif (cmd == 'posx') then
        if (x == nil) then return false end
        settings.textBoxes[boxName].x = x
    elseif (cmd == 'posy') then
        if (y == nil) then return false end
        settings.textBoxes[boxName].y = y
    end
    return true
end

function utils.toggleVisible(boxName, cmd)
    cmd = cmd and cmd:lower() or (settings.textBoxes[boxName].visible and 'off' or 'on')
    if (cmd == 'on') then
        settings.textBoxes[boxName].visible = true
    elseif (cmd == 'off') then
        settings.textBoxes[boxName].visible = false
    else
        atc(123,'Invalid argument for changing text box settings: '..cmd)
    end
end

function utils.toggleX(tbl, field, cmd, msg, msgErr)
    if (tbl[field] == nil) then
        atcf(123, 'Error: Invalid mode to toggle: %s', field)
        return
    end
    cmd = cmd and cmd:lower() or (tbl[field] and 'off' or 'on')
    if (cmd == 'on') then
        tbl[field] = true
        atc(msg..' is now on.')
    elseif (cmd == 'off') then
        tbl[field] = false
        atc(msg..' is now off.')
    else
        atc(123,'Invalid argument for '..msgErr..': '..cmd)
    end
end

function toggleMode(mode, cmd, msg, msgErr)
    utils.toggleX(hb.modes, mode, cmd, msg, msgErr)
    _libs.lor.debug = hb.modes.debug
end

function disableCommand(cmd, disable)
    local msg = ' is now '..(disable and 'disabled.' or 're-enabled.')
    if S{'cure','cures','curing','allcure'}:contains(cmd) then
        if (not disable) then
            if (settings.maxCureTier == 0) then
                settings.disable.all_cure = true
                atc(123,'Error: Unable to enable curing because you have no Cure spells available.')
                return
            end
        end
        settings.disable.all_cure = disable
        atc('All Curing'..msg)
    elseif S{'curaga'}:contains(cmd) then
        settings.disable.curaga = disable
        atc('Curaga use'..msg)
    elseif S{'na','heal_debuff','cure_debuff'}:contains(cmd) then
        settings.disable.na = disable
        atc('Removal of status effects'..msg)
	elseif S{'erase'}:contains(cmd) then
		settings.disable.erase = disable
		atc('Erase status effects'..msg)
    elseif S{'buff','buffs','buffing'}:contains(cmd) then
        settings.disable.buff = disable
        atc('Buffing'..msg)
    elseif S{'debuff','debuffs','debuffing'}:contains(cmd) then
        settings.disable.debuff = disable
        atc('Debuffing'..msg)
    elseif S{'spam','nuke','nukes','nuking'}:contains(cmd) then
        settings.disable.spam = disable
        atc('Spamming'..msg)
    elseif S{'ws','weaponskill','weaponskills','weaponskilling'}:contains(cmd) then
        settings.disable.ws = disable
        atc('Weaponskilling'..msg)
    else
        atc(123,'Error: Invalid argument for disable/enable: '..cmd)
    end
end

function monitorCommand(cmd, pname)
    if (pname == nil) then
        atc('Error: No argument specified for '..cmd)
        return
    end
    local name = utils.getPlayerName(pname)
    if cmd == 'ignore' then
        if (not hb.ignoreList:contains(name)) then
            hb.ignoreList:add(name)
            atc('Will now ignore '..name)
            if hb.extraWatchList:contains(name) then
                hb.extraWatchList:remove(name)
            end
        else
            atc('Error: Already ignoring '..name)
        end
    elseif cmd == 'unignore' then
        if (hb.ignoreList:contains(name)) then
            hb.ignoreList:remove(name)
            atc('Will no longer ignore '..name)
        else
            atc('Error: Was not ignoring '..name)
        end
    elseif cmd == 'watch' then
        if (not hb.extraWatchList:contains(name)) then
            hb.extraWatchList:add(name)
            atc('Will now watch '..name)
            if hb.ignoreList:contains(name) then
                hb.ignoreList:remove(name)
            end
        else
            atc('Error: Already watching '..name)
        end
    elseif cmd == 'unwatch' then
        if (hb.extraWatchList:contains(name)) then
            hb.extraWatchList:remove(name)
            atc('Will no longer watch '..name)
        else
            atc('Error: Was not watching '..name)
        end
    end
end

function validate(args, numArgs, message)
    for i = 1, numArgs do
        if (args[i] == nil) then
            atc(message..' ('..i..')')
            return false
        end
    end
    return true
end

function utils.getPlayerName(name)
    local target = ffxi.get_target(name)
    if target ~= nil then
        return target.name
    end
    return nil
end

function utils.getPlayerNameFromJob(job)
	local target
	for k, v in pairs(windower.ffxi.get_party()) do
		if type(v) == 'table' and v.mob ~= nil and v.mob.in_party then
			if ((job:lower() == 'tank' and S{'PLD','RUN'}:contains(get_registry(v.mob.id))) or (job:lower() ~= 'tank' and get_registry(v.mob.id):lower() == job:lower())) then
				target = v.name
			end
		end
	end
    if target ~= nil then
        return target
    end
    return nil
end

function num_strats()
    local p = windower.ffxi.get_player()
    local sch_level = 0
    if p.main_job == "SCH" then
        sch_level = p.main_job_level
    elseif healer.sub_job == "SCH" then
        sch_level = p.sub_job_level
    end
    if sch_level == 0 then return 0 end

    if sch_level < 30 then return 1
    elseif sch_level < 50 then return 2
    elseif sch_level < 70 then return 3
    elseif sch_level < 90 then return 4
    elseif p.job_points.sch.jp_spent < 550 then return 5
    else return 6 end
end

function healer_has_buffs(buffs)
    local buff_list = windower.ffxi.get_player().buffs
    for _,bid in pairs(buff_list) do
        if buffs:contains(bid) then
            return true
        end
    end
    return false
end

function utils.NotDead()
    local player = windower.ffxi.get_player()
    if player.status ~= 2 and player.status ~= 3 then
       return true
    end
    return false
end

function utils.isMonsterByIndexNoHP(index)
	local mob_in_question = windower.ffxi.get_mob_by_index(index)
	if mob_in_question and mob_in_question.is_npc and mob_in_question.spawn_type == 16 and mob_in_question.valid_target then
		return true
    else
        return false
	end
end

function utils.isMonsterByTarget()
	local mob_in_question = windower.ffxi.get_mob_by_target('t')
	if mob_in_question and mob_in_question.is_npc and mob_in_question.spawn_type == 16 and mob_in_question.valid_target and mob_in_question.hpp > 0 then
		return true
    else
        return false
	end
end

function utils.isMonster(mob_index)
	local mob_in_question = windower.ffxi.get_mob_by_index(mob_index)
	if mob_in_question and mob_in_question.is_npc and mob_in_question.spawn_type == 16 and mob_in_question.valid_target then
		return true
	end
end

function utils.check_claim_id(id)
	for k, v in pairs(windower.ffxi.get_party()) do
		if type(v) == 'table' then
			if id and v.mob and v.mob.id == id then
				return true
			end
		end
	end
	return false
end

function utils.ready_to_use(action)
    if light_strategems:contains(action.en) then
        if not healer_has_buffs(light_arts) then return false end

        local strats = num_strats()
        if strats < 1 then return false end 

        local rc = windower.ffxi.get_ability_recasts()[action.recast_id]
        return rc <= (4 * 60) / strats * (strats - 1)
    elseif dark_strategems:contains(action.en) then
        if not healer_has_buffs(dark_arts) then return false end

        local strats = num_strats()
        if strats < 1 then return false end 

        local rc = windower.ffxi.get_ability_recasts()[action.recast_id]
        return rc <= (4 * 60) / strats * (strats - 1)
    else
        return healer:ready_to_use(action)
    end
end

function utils.debuffs_disp()
	debuffs_lists = L()
	if next(offense.mobs) ~= nil or next(offense.dispel.mobs) ~= nil then
		if next(offense.mobs) ~= nil then
			local t_target = windower.ffxi.get_mob_by_target('t') or nil
			local tindex = 0
			for mob_id,debuff_table in pairs(offense.mobs) do
				tindex = utils.get_mob_index(debuff_table)
				local claim_target = tindex and windower.ffxi.get_mob_by_index(tindex) and windower.ffxi.get_mob_by_index(tindex).claim_id or nil
				if (utils.check_claim_id(claim_target)) or (t_target and t_target.valid_target and t_target.is_npc and t_target.spawn_type == 16 and t_target.id == mob_id) then
					utils.debuff_display_builder(debuff_table,true,false,mob_id,tindex)
					if next(offense.dispel.mobs) ~= nil then
						if offense.dispel.mobs[mob_id] then
							utils.debuff_display_builder(offense.dispel.mobs[mob_id],false,true,mob_id)
						end
					end
				end
			end
		end
		-- If just dispel buffs
		if next(offense.dispel.mobs) ~= nil then
			local t_target = windower.ffxi.get_mob_by_target('t') or nil
			local tindex = 0
			for mob_id,dispel_table in pairs(offense.dispel.mobs) do
				tindex = utils.get_mob_index(dispel_table)
				local claim_target = tindex and windower.ffxi.get_mob_by_index(tindex) and windower.ffxi.get_mob_by_index(tindex).claim_id or nil
				if not offense.mobs[mob_id] and ((utils.check_claim_id(claim_target)) or (t_target and t_target.valid_target and t_target.is_npc and t_target.spawn_type == 16 and t_target.id == mob_id)) then
					utils.debuff_display_builder(dispel_table,true,true,mob_id,tindex)
				end
			end
		end
	end
    hb.txts.debuffList:text(getPrintable(debuffs_lists))
    hb.txts.debuffList:visible(settings.textBoxes.debuffList.visible)
end

function utils.debuff_display_builder(d_table, name, dispel, mob_id, mob_index)
	local count = 0
	local colorOrange = "\\cs(255,165,0)"
	local colorRed = "\\cs(255,50,0)"
	local formattedMessage = ""
	local mob_claim_name = ""

	for _,v in pairs(d_table) do
		if count == 0 and name then
			local claim_target = windower.ffxi.get_mob_by_index(mob_index) and windower.ffxi.get_mob_by_index(mob_index).claim_id or nil
			if utils.check_claim_id(claim_target) then
				mob_claim_name = string.format("%s%s\\cr", colorRed, v.mob_name)
				if d_table[0] then
					debuffs_lists:append('['..mob_claim_name..'] - '..mob_id..' - '..string.format(os.date('%M:%S',os.time()-d_table[0].landed)))
				else
					debuffs_lists:append('['..mob_claim_name..'] - '..mob_id)
				end
			else
				if d_table[0] then
					debuffs_lists:append('['..v.mob_name..'] - '..mob_id..' - '..string.format(os.date('%M:%S',os.time()-d_table[0].landed)))
				else
					debuffs_lists:append('['..v.mob_name..'] - '..mob_id)
				end
			end
		end
		if dispel then
			formattedMessage = string.format("%s%s\\cr", colorOrange, v.debuff_name)
			debuffs_lists:append(formattedMessage.." : "..string.format(os.date('%M:%S',os.time()-v.landed)))
		else
			if v.spell_name ~= "KO" then
				debuffs_lists:append(v.spell_name.." : "..string.format(os.date('%M:%S',os.time()-v.landed)))
			end
		end
		count = count +1
	end
end

function utils.get_mob_index(s_table)
	for _,v in pairs(s_table) do
		if v.mob_index then
			return v.mob_index
		end
	end
	return nil
end

function utils.check_debuffs_timer()
	if next(offense.mobs) == nil then return end
	for mob_id,debuff_table in pairs(offense.mobs) do
		for k,v in pairs(debuff_table) do
			if maximum_debuff_timers[v.spell_id] then
				local now = os.time()
				if now-debuff_table[k].landed >= maximum_debuff_timers[v.spell_id] then
					offense.mobs[mob_id][k] = nil
				end
			end
		end
	end
end

function utils.toggle_disp()
	local toggle_list = L()
	local hp_toggle = hb.autoRecoverHPMode and '\\cs(0,0,255)[ON]\\cr' or '\\cs(255,0,0)[OFF]\\cr'
	toggle_list:append(('[Auto HP]: %s'):format(hp_toggle))
	local mp_toggle = hb.autoRecoverMPMode and '\\cs(0,0,255)[ON]\\cr' or '\\cs(255,0,0)[OFF]\\cr'
	toggle_list:append(('[Auto MP]: %s'):format(mp_toggle))
    hb.txts.toggleList:text(getPrintable(toggle_list))
    hb.txts.toggleList:visible(settings.textBoxes.toggleList.visible)
end

function utils.haveItem(item_id)
	for bag in T(__bags.usable):it() do
		for item, index in T(windower.ffxi.get_items(bag.id)):it() do
			if type(item) == 'table' and item.id == item_id then
				return true
			end
		end
	end
	return false
end

function utils.check_recovery_item()
	if (not hb.autoRecoverMPMode) and (not hb.autoRecoverHPMode) then return false end

	if hb.autoRecoverHPMode and not moving and windower.ffxi.get_player().vitals.hpp < 30 then
		if utils.haveItem(4175) then
			atc(123,'HP LOW: Vile Elixir +1')
			windower.chat.input('/item "Vile Elixir +1" <me>')
			return true
		elseif utils.haveItem(4174) then
			atc(123,'HP LOW: Vile Elixir')
			windower.chat.input('/item "Vile Elixir" <me>')
			return true
		end
	end
	
	if hb.autoRecoverMPMode and not moving and windower.ffxi.get_player().vitals.mpp < 25 then
		if utils.haveItem(5987) then
			atc(123,'MP LOW: Coalition Ether')
			windower.chat.input('/item "Coalition Ether" <me>')
			return true
		end
	end
	return false
end

--==============================================================================
--          String Formatting Functions
--==============================================================================

function utils.formatActionName(text)
    if (type(text) ~= 'string') or (#text < 1) then return nil end
    
    local fromAlias = hb.config.aliases[text]
    if (fromAlias ~= nil) then
        return fromAlias
    end
    
    local spell_from_lc = lc_res.spells[text:lower()]
    if spell_from_lc ~= nil then
        return spell_from_lc.en
    end
    
    local parts = text:split(' ')
    if #parts >= 2 then
        local name = formatName(parts[1])
        for p = 2, #parts do
            local part = parts[p]
            local tier = toRomanNumeral(part) or part:upper()
            if (roman2dec[tier] == nil) then
                name = name..' '..formatName(part)
            else
                name = name..' '..tier
            end
        end
        return name
    else
        local name = formatName(text)
        local tier = text:sub(-1)
        local rnTier = toRomanNumeral(tier)
        if (rnTier ~= nil) then
            return name:sub(1, #name-1)..' '..rnTier
        else
            return name
        end
    end
end

function formatName(text)
    if (text ~= nil) and (type(text) == 'string') then
        return text:lower():ucfirst()
    end
    return text
end

function toRomanNumeral(val)
    if type(val) ~= 'number' then
        if type(val) == 'string' then
            val = tonumber(val)
        else
            return nil
        end
    end
    return dec2roman[val]
end

--==============================================================================
--          Output Handling Functions
--==============================================================================

function printStatus()
    windower.add_to_chat(1, 'HB is now '..(hb.active and 'active' or 'off')..'.')
end

--==============================================================================
--          Initialization Functions
--==============================================================================

function utils.load_configs()

	local player = windower.ffxi.get_player()
    local defaults = {
        textBoxes = {
            actionQueue={x=-125,y=300,font='Arial',size=10,visible=true},
            moveInfo={x=0,y=18,visible=false},
            actionInfo={x=0,y=0,visible=true},
            montoredBox={x=-150,y=600,font='Arial',size=10,visible=true}
        },
        spam = {name='Stone'},
        healing = {min={cure=3,curaga=1,waltz=2,waltzga=1,blue=1,bluega=1},curaga_min_targets=2},
        disable = {curaga=false},
        ignoreTrusts=true, deactivateIndoors=true, activateOutdoors=false
    }
    local loaded = lor_settings.load('data/settings.lua', defaults)
    utils.update_settings(loaded)
    utils.refresh_textBoxes()
    
    local cure_potency_defaults = {
        cure = {94,207,469,880,1110,1395},  curaga = {150,313,636,1125,1510},
        waltz = {157,325,581,887,1156},     waltzga = {160,521},
		blue = {288,762,1072},				bluega = {300,885},
    }
    local buff_lists_defaults = {       self = {'Haste II','Refresh II'},
        whm = {self={'Haste','Refresh'}}, rdm = {self={'Haste II','Refresh II'}}
    }
    
    hb.config = {
        aliases = config.load('../shortcuts/data/aliases.xml'),
        mabil_debuffs = lor_settings.load('data/mabil_debuffs.lua'),
        buff_lists = lor_settings.load('data/buffLists.lua', buff_lists_defaults),
		auto_ja_lists = lor_settings.load('data/autoJaLists.lua'),
        priorities = lor_settings.load('data/priorities.lua'),
        cure_potency = lor_settings.load('data/cure_potency.lua', cure_potency_defaults)
    }
    hb.config.priorities.players =        hb.config.priorities.players or {}
    hb.config.priorities.jobs =           hb.config.priorities.jobs or {}
    hb.config.priorities.status_removal = hb.config.priorities.status_removal or {}
    hb.config.priorities.buffs =          hb.config.priorities.buffs or {}
    hb.config.priorities.debuffs =        hb.config.priorities.debuffs or {}
    hb.config.priorities.dispel =         hb.config.priorities.dispel or {}     --not implemented yet
    hb.config.priorities.default =        hb.config.priorities.default or 5
    
	utils.addCustomBuffs() -- Call the function to add custom buffs on healbot startup or during initialization
	utils.preprocess_resources()
	--Set job defaults debuffs
	if player.main_job == 'COR' then
		utils.register_offensive_debuff({"Light Shot"}, false, false ,true)
		utils.register_offensive_debuff({"Ice Shot"}, false, false ,true)
		utils.register_offensive_debuff({"Earth Shot"}, false, false ,true)
		offense.debuffing_active = false
	elseif player.main_job == 'DNC' then
		settings.healing.min.waltz = 2
	end
	utils.auto_apply_bufflist()
	utils.auto_apply_autojalist()
    --process_mabil_debuffs()
	utils.schedule_request_job_registry()
	
    local msg = hb.configs_loaded and 'Rel' or 'L'
    hb.configs_loaded = true
    atcc(262, msg..'oaded config files.')
	hb.getMonitoredPlayersDirect()
end

function utils.schedule_request_job_registry()
    local delay = math.random(1, 3) -- Random delay between 1 and 3 seconds
    coroutine.schedule(function()
        request_job_registry()
    end, delay)
end

-- Adding custom buffs
local custom_buffs = {
    [700] = {id = 700, en = "CustomBuff700", jp = "カスタムバフ700"},
    [701] = {id = 701, en = "CustomBuff701", jp = "カスタムバフ701"},
    [702] = {id = 702, en = "CustomBuff702", jp = "カスタムバフ702"},
    [703] = {id = 703, en = "CustomBuff703", jp = "カスタムバフ703"},
    [704] = {id = 704, en = "CustomBuff704", jp = "カスタムバフ704"},
    [705] = {id = 705, en = "CustomBuff705", jp = "カスタムバフ705"},
    [706] = {id = 706, en = "CustomBuff706", jp = "カスタムバフ706"},
    [707] = {id = 707, en = "CustomBuff707", jp = "カスタムバフ707"},
    [708] = {id = 708, en = "CustomBuff708", jp = "カスタムバフ708"},
    [709] = {id = 709, en = "CustomBuff709", jp = "カスタムバフ709"},
    [710] = {id = 710, en = "CustomBuff710", jp = "カスタムバフ710"},
    [711] = {id = 711, en = "CustomBuff711", jp = "カスタムバフ711"},
    [712] = {id = 712, en = "CustomBuff712", jp = "カスタムバフ712"},
    [713] = {id = 713, en = "CustomBuff713", jp = "カスタムバフ713"},
    [714] = {id = 714, en = "CustomBuff714", jp = "カスタムバフ714"},
    [715] = {id = 715, en = "CustomBuff715", jp = "カスタムバフ715"},
    [716] = {id = 716, en = "CustomBuff716", jp = "カスタムバフ716"},
    [717] = {id = 717, en = "CustomBuff717", jp = "カスタムバフ717"},
    [718] = {id = 718, en = "CustomBuff718", jp = "カスタムバフ718"},
    [719] = {id = 719, en = "CustomBuff719", jp = "カスタムバフ719"},
    [720] = {id = 720, en = "CustomBuff720", jp = "カスタムバフ720"},
    [721] = {id = 721, en = "CustomBuff721", jp = "カスタムバフ721"},
    [722] = {id = 722, en = "CustomBuff722", jp = "カスタムバフ722"},
    [723] = {id = 723, en = "CustomBuff723", jp = "カスタムバフ723"},
    [724] = {id = 724, en = "CustomBuff724", jp = "カスタムバフ724"},
    [725] = {id = 725, en = "CustomBuff725", jp = "カスタムバフ725"},
    [726] = {id = 726, en = "CustomBuff726", jp = "カスタムバフ726"},
    [727] = {id = 727, en = "CustomBuff727", jp = "カスタムバフ727"},
    [728] = {id = 728, en = "CustomBuff728", jp = "カスタムバフ728"},
    [729] = {id = 729, en = "CustomBuff729", jp = "カスタムバフ729"},
    [730] = {id = 730, en = "CustomBuff730", jp = "カスタムバフ730"},
    [731] = {id = 731, en = "CustomBuff731", jp = "カスタムバフ731"},
    [732] = {id = 732, en = "CustomBuff732", jp = "カスタムバフ732"},
    [733] = {id = 733, en = "CustomBuff733", jp = "カスタムバフ733"},
    [734] = {id = 734, en = "CustomBuff734", jp = "カスタムバフ734"},
    [735] = {id = 735, en = "CustomBuff735", jp = "カスタムバフ735"},
    [736] = {id = 736, en = "CustomBuff736", jp = "カスタムバフ736"},
    [737] = {id = 737, en = "CustomBuff737", jp = "カスタムバフ737"},
    [738] = {id = 738, en = "CustomBuff738", jp = "カスタムバフ738"},
    [739] = {id = 739, en = "CustomBuff739", jp = "カスタムバフ739"},
    [740] = {id = 740, en = "CustomBuff740", jp = "カスタムバフ740"},
    [741] = {id = 741, en = "CustomBuff741", jp = "カスタムバフ741"},
    [742] = {id = 742, en = "CustomBuff742", jp = "カスタムバフ742"},
    [743] = {id = 743, en = "CustomBuff743", jp = "カスタムバフ743"},
    [744] = {id = 744, en = "CustomBuff744", jp = "カスタムバフ744"},
    [745] = {id = 745, en = "CustomBuff745", jp = "カスタムバフ745"},
    [746] = {id = 746, en = "CustomBuff746", jp = "カスタムバフ746"},
    [747] = {id = 747, en = "CustomBuff747", jp = "カスタムバフ747"},
    [748] = {id = 748, en = "CustomBuff748", jp = "カスタムバフ748"},
    [749] = {id = 749, en = "CustomBuff749", jp = "カスタムバフ749"},
    [750] = {id = 750, en = "CustomBuff750", jp = "カスタムバフ750"},
    [751] = {id = 751, en = "CustomBuff751", jp = "カスタムバフ751"},
    [752] = {id = 752, en = "CustomBuff752", jp = "カスタムバフ752"},
    [753] = {id = 753, en = "CustomBuff753", jp = "カスタムバフ753"},
    [754] = {id = 754, en = "CustomBuff754", jp = "カスタムバフ754"},
    [755] = {id = 755, en = "CustomBuff755", jp = "カスタムバフ755"},
    [756] = {id = 756, en = "CustomBuff756", jp = "カスタムバフ756"},
    [757] = {id = 757, en = "CustomBuff757", jp = "カスタムバフ757"},
    [758] = {id = 758, en = "CustomBuff758", jp = "カスタムバフ758"},
    [759] = {id = 759, en = "CustomBuff759", jp = "カスタムバフ759"},
    [760] = {id = 760, en = "CustomBuff760", jp = "カスタムバフ760"},
    [761] = {id = 761, en = "CustomBuff761", jp = "カスタムバフ761"},
    [762] = {id = 762, en = "CustomBuff762", jp = "カスタムバフ762"},
    [763] = {id = 763, en = "CustomBuff763", jp = "カスタムバフ763"},
    [764] = {id = 764, en = "CustomBuff764", jp = "カスタムバフ764"},
    [765] = {id = 765, en = "CustomBuff765", jp = "カスタムバフ765"},
    [766] = {id = 766, en = "CustomBuff766", jp = "カスタムバフ766"},
    [767] = {id = 767, en = "CustomBuff767", jp = "カスタムバフ767"},
    [768] = {id = 768, en = "CustomBuff768", jp = "カスタムバフ768"},
    [769] = {id = 769, en = "CustomBuff769", jp = "カスタムバフ769"},
    [770] = {id = 770, en = "CustomBuff770", jp = "カスタムバフ770"},
    [771] = {id = 771, en = "CustomBuff771", jp = "カスタムバフ771"},
    [772] = {id = 772, en = "CustomBuff772", jp = "カスタムバフ772"},
    [773] = {id = 773, en = "CustomBuff773", jp = "カスタムバフ773"},
    [774] = {id = 774, en = "CustomBuff774", jp = "カスタムバフ774"},
    [775] = {id = 775, en = "CustomBuff775", jp = "カスタムバフ775"},
    [776] = {id = 776, en = "CustomBuff776", jp = "カスタムバフ776"},
    [777] = {id = 777, en = "CustomBuff777", jp = "カスタムバフ777"},
    [778] = {id = 778, en = "CustomBuff778", jp = "カスタムバフ778"},
    [779] = {id = 779, en = "CustomBuff779", jp = "カスタムバフ779"},
    [780] = {id = 780, en = "CustomBuff780", jp = "カスタムバフ780"},
    [781] = {id = 781, en = "CustomBuff781", jp = "カスタムバフ781"},
    [782] = {id = 782, en = "CustomBuff782", jp = "カスタムバフ782"},
    [783] = {id = 783, en = "CustomBuff783", jp = "カスタムバフ783"},
    [784] = {id = 784, en = "CustomBuff784", jp = "カスタムバフ784"},
    [785] = {id = 785, en = "CustomBuff785", jp = "カスタムバフ785"},
    [786] = {id = 786, en = "CustomBuff786", jp = "カスタムバフ786"},
    [787] = {id = 787, en = "CustomBuff787", jp = "カスタムバフ787"},
    [788] = {id = 788, en = "CustomBuff788", jp = "カスタムバフ788"},
    [789] = {id = 789, en = "CustomBuff789", jp = "カスタムバフ789"},
    [790] = {id = 790, en = "CustomBuff790", jp = "カスタムバフ790"},
    [791] = {id = 791, en = "CustomBuff791", jp = "カスタムバフ791"},
    [792] = {id = 792, en = "CustomBuff792", jp = "カスタムバフ792"},
    [793] = {id = 793, en = "CustomBuff793", jp = "カスタムバフ793"},
    [794] = {id = 794, en = "CustomBuff794", jp = "カスタムバフ794"},
    [795] = {id = 795, en = "CustomBuff795", jp = "カスタムバフ795"},
    [796] = {id = 796, en = "CustomBuff796", jp = "カスタムバフ796"},
    [797] = {id = 797, en = "CustomBuff797", jp = "カスタムバフ797"},
    [798] = {id = 798, en = "CustomBuff798", jp = "カスタムバフ798"},
    [799] = {id = 799, en = "CustomBuff799", jp = "カスタムバフ799"},
    [800] = {id = 800, en = "Widened Compass", jp = "カスタムバフ800"},
	[801] = {id = 801, en = "Random Deal", jp = "カスタムバフ801"},
	[802] = {id = 802, en = "Wild Card", jp = "カスタムバフ802"},
	[803] = {id = 803, en = "Mantra", jp = "カスタムバフ803"},
	[804] = {id = 804, en = "Benediction", jp = "カスタムバフ804"},
	[900] = {id = 900, en = "Aspir", jp = "カスタムバフ900"},
	[901] = {id = 901, en = "Aspir II", jp = "カスタムバフ901"},
	[902] = {id = 902, en = "Aspir III", jp = "カスタムバフ902"},
	[903] = {id = 903, en = "Absorb-TP", jp = "カスタムバフ903"},
}

-- Function to add custom buffs to the existing buffs table
function utils.addCustomBuffs()
    for id, buff in pairs(custom_buffs) do
        res.buffs[id] = buff
    end
end

function utils.preprocess_resources()
    -- Add a `lower_en` field to each spell for case-insensitive matching
    for _, spell in pairs(res.spells) do
        if spell.en then
            spell.lower_en = spell.en:lower()
        end
    end

    -- Add a `lower_en` field to each job ability for case-insensitive matching
    for _, ability in pairs(res.job_abilities) do
        if ability.en then
            ability.lower_en = ability.en:lower()
        end
    end
end



function process_mabil_debuffs()
    local debuff_names = table.keys(hb.config.mabil_debuffs)
    for _,abil_raw in pairs(debuff_names) do
        local abil_fixed = abil_raw:gsub('_',' '):capitalize()
        hb.config.mabil_debuffs[abil_fixed] = S{}
        local debuffs = hb.config.mabil_debuffs[abil_raw]
        for _,debuff in pairs(debuffs) do
            hb.config.mabil_debuffs[abil_fixed]:add(debuff)
        end
        hb.config.mabil_debuffs[abil_raw] = nil
    end
    hb.config.mabil_debuffs:save()
end


function utils.update_settings(loaded)
    for key,val in pairs(loaded) do
        if istable(val) then
            settings[key] = settings[key] or {}
            for skey,sval in pairs(val) do
                settings[key][skey] = sval
            end
        else
            settings[key] = settings[key] or val
        end
    end
    table.update_if_not_set(settings, {
        disable = {},
        follow = {delay = 0.08, distance = 3},
        healing = {minCure = 3, minCuraga = 2, minWaltz = 2, minWaltzga = 2, minBlue = 2, minBluega = 2},
        spam = {}
    })
end


function utils.refresh_textBoxes()
	local OurReso = windower.get_windower_settings()
	local X_action_queue = OurReso.x_res - 765
	local X_mon_box = OurReso.x_res - 305

    local boxes = {'actionQueue','moveInfo','actionInfo','montoredBox','debuffList','toggleList'}
    for _,box in pairs(boxes) do
        local bs = settings.textBoxes[box]
		local bst
		if (box == 'actionInfo' or box == 'moveInfo') then
			bst = {pos={x=bs.x, y=bs.y}, bg={alpha=125, blue=0, green=0,red=0,visible=true}, stroke={alpha=255, blue=0, green=0, red=0, width=0}}
		elseif box == 'montoredBox' then
			bst = {pos={x=X_mon_box, y=bs.y}, bg=settings.textBoxes.bg, stroke={alpha=255, blue=0, green=0, red=0, width=0}}
		elseif box == 'actionQueue' then
			bst = {pos={x=X_action_queue, y=bs.y}, bg=settings.textBoxes.bg, stroke={alpha=255, blue=0, green=0, red=0, width=0}}
		elseif box == 'debuffList' then
			bst = {pos={x=bs.x, y=bs.y}, bg=settings.textBoxes.bg_other, stroke={alpha=255, blue=0, green=0, red=0, width=0}}
		elseif box == 'toggleList' then
			bst = {pos={x=X_mon_box, y=bs.y}, bg=settings.textBoxes.bg, stroke={alpha=255, blue=0, green=0, red=0, width=0}}
		end
	
        if (bs.font ~= nil) then
            bst.text = {font=bs.font}
        end
        if (bs.size ~= nil) then
            bst.text = bst.text or {}
            bst.text.size = bs.size
        end
		
        if (hb.txts[box] ~= nil) then
            hb.txts[box]:destroy()
        end
        hb.txts[box] = texts.new(bst)
    end
end


--==============================================================================
--          Table Functions
--==============================================================================

function getPrintable(list, inverse)
    local qstring = ''
    for index,line in pairs(list) do
        local check = index
        local add = line
        if (inverse) then
            check = line
            add = index
        end
        if (tostring(check) ~= 'n') then
            if (#qstring > 1) then
                qstring = qstring..'\n'
            end
            qstring = qstring..add
        end
    end
    return qstring
end

--======================================================================================================================
--                      Misc.
--======================================================================================================================

function help_text()
    local t = '    '
    local ac,cc,dc = 262,263,1
    atcc(262,'HealBot Commands:')
    local cmds = {
        {'on | off','Activate / deactivate HealBot (does not affect follow)'},
        {'reload','Reload HealBot, resetting everything'},
        {'refresh','Reloads settings XMLs in addons/HealBot/data/'},
        {'fcmd','Sets a player to follow, the distance to maintain, or toggles being active with no argument'},
        {'buff <player> <spell>[, <spell>[, ...]]','Sets spell(s) to be maintained on the given player'},
        {'cancelbuff <player> <spell>[, <spell>[, ...]]','Un-sets spell(s) to be maintained on the given player'},
        {'blcmd','Sets the given list of spells to be maintained on the given player'},
        {'bufflists','Lists the currently configured spells/abilities in each bufflist'},
        {'spam [use <spell> | <bool>]','Sets the spell to be spammed on assist target\s enemy, or toggles being active (default: Stone, off)'},
        {'dbcmd','Add/remove debuff spell to maintain on assist target\'s enemy, toggle on/off, or list current debuffs to maintain'},
        {'mincure <number>','Sets the minimum cure spell tier to cast (default: 3)'},
        {'disable <action type>','Disables actions of a given type (cure, buff, na)'},
        {'enable <action type>','Re-enables actions of a given type (cure, buff, na) if they were disabled'},
        {'reset [buffs | debuffs | both [on <player>]]','Resets the list of buffs/debuffs that have been detected, optionally for a single player'},
        {'ignore_debuff <player/always> <debuff>','Ignores when the given debuff is cast on the given player or everyone'},
        {'unignore_debuff <player/always> <debuff>','Stops ignoring the given debuff for the given player or everyone'},
        {'ignore <player>','Ignores the given player/npc so they will not be healed'},
        {'unignore <player>','Stops ignoring the given player/npc (=/= watch)'},
        {'watch <player>','Monitors the given player/npc so they will be healed'},
        {'unwatch <player>','Stops monitoring the given player/npc (=/= ignore)'},
        {'ignoretrusts <on/off>','Toggles whether or not Trust NPCs should be ignored (default: on)'},
        {'ascmd','Sets a player to assist, toggles whether or not to engage, or toggles being active with no argument'},
        {'wscmd1','Sets the weaponskill to use'},
        {'wscmd2','Sets when weaponskills should be used according to whether the mob HP is < or > the given amount'},
        {'wscmd3','Sets a weaponskill partner to open skillchains for, and the TP that they should have'},
        {'wscmd4','Removes a weaponskill partner so weaponskills will be performed independently'},
        {'queue [pos <x> <y> | on | off]','Moves action queue, or toggles display with no argument (default: on)'},
        {'actioninfo [pos <x> <y> | on | off]','Moves character status info, or toggles display with no argument (default: on)'},
        {'moveinfo [pos <x> <y> | on | off]','Moves movement status info, or toggles display with no argument (default: off)'},
        {'monitored [pos <x> <y> | on | off]','Moves monitored player list, or toggles display with no argument (default: on)'},
        {'help','Displays this help text'}
    }
    local acmds = {
        ['fcmd']=('f'):colorize(ac,cc)..'ollow [<player> | dist <distance> | off | resume]',
        ['ascmd']=('as'):colorize(ac,cc)..'sist [<player> | attack | off | resume]',
        ['wscmd1']=('w'):colorize(ac,cc)..'eapon'..('s'):colorize(ac,cc)..'kill use <ws name>',
        ['wscmd2']=('w'):colorize(ac,cc)..'eapon'..('s'):colorize(ac,cc)..'kill hp <sign> <mob hp%>',
        ['wscmd3']=('w'):colorize(ac,cc)..'eapon'..('s'):colorize(ac,cc)..'kill waitfor <player> <tp>',
        ['wscmd4']=('w'):colorize(ac,cc)..'eapon'..('s'):colorize(ac,cc)..'kill nopartner',
        ['dbcmd']=('d'):colorize(ac,cc)..'e'..('b'):colorize(ac,cc)..'uff [(use | rm) <spell> | on | off | ls]',
        ['blcmd']=('b'):colorize(ac,cc)..'uff'..('l'):colorize(ac,cc)..'ist <list name> (<player>)',
    }
    
    for _,tbl in pairs(cmds) do
        local cmd,desc = tbl[1],tbl[2]
        local txta = cmd
        if (acmds[cmd] ~= nil) then
            txta = acmds[cmd]
        else
            txta = txta:colorize(cc)
        end
        local txtb = desc:colorize(dc)
        atc(txta)
        atc(t..txtb)
    end
end

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
