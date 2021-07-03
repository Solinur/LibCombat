local strings = {

	SI_LIBCOMBAT_LOG_CRITICAL = "critically ",  -- "critically"
	SI_LIBCOMBAT_LOG_YOU = "You", -- "you"
	SI_LIBCOMBAT_LOG_GAINED = "gained", -- "gained"
	SI_LIBCOMBAT_LOG_NOGAINED = "gained no", -- "gained no"
	SI_LIBCOMBAT_LOG_LOST = "lost", -- "lost"

	SI_LIBCOMBAT_LOG_DEBUFF = "Debuff",

	SI_LIBCOMBAT_LOG_UNITTYPE_PLAYER = "yourself", -- "You"
	SI_LIBCOMBAT_LOG_UNITTYPE_PET = "your pet", -- "Pet"
	SI_LIBCOMBAT_LOG_UNITTYPE_GROUP = "a group member", -- "Groupmember"
	SI_LIBCOMBAT_LOG_UNITTYPE_OTHER = "another player", -- "Another Player"

	SI_LIBCOMBAT_LOG_IS_AT = "is at", -- "is at"
	SI_LIBCOMBAT_LOG_INCREASED = "increased to", -- "increased to"
	SI_LIBCOMBAT_LOG_DECREASED = "decreased to", -- "decreased to"

	SI_LIBCOMBAT_LOG_ULTIMATE = "Ultimate", -- "Ultimate"
	SI_LIBCOMBAT_LOG_BASEREG = "Base Regeneration", -- "Base Regeneration"

	SI_LIBCOMBAT_LOG_STAT_SPELL_CRIT_DONE = "Spell Critical Damage",  -- "Spell Critical Damage"
	SI_LIBCOMBAT_LOG_STAT_WEAPON_CRIT_DONE = "Physical Critical Damage",  -- "Physical Critical Damage"

	SI_LIBCOMBAT_LOG_MESSAGE1 = "Entering Combat",  -- "Entering Combat"
	SI_LIBCOMBAT_LOG_MESSAGE2 = "Exiting Combat",  -- "Exiting Combat"
	SI_LIBCOMBAT_LOG_MESSAGE3 = "Weapon Swap",  -- "Weapon Swap"
	SI_LIBCOMBAT_LOG_MESSAGE_BAR = "Bar",  -- "Bar"

	SI_LIBCOMBAT_LOG_FORMAT_TARGET_NORMAL = "<<1>>|r with ",  -- i.e. "dwemer sphere with", %s = targetname. |r stops the colored text
	SI_LIBCOMBAT_LOG_FORMAT_TARGET_BLOCK = "<<1>>s block|r with",  -- i.e. "dwemer spheres block with", %s = targetname. |r stops the colored text

	SI_LIBCOMBAT_LOG_FORMAT_TARGETSELF_NORMAL = "you|r with ",  -- i.e. "you with", |r stops the colored text
	SI_LIBCOMBAT_LOG_FORMAT_TARGETSELF_SELF = "yourself|r with ",  -- i.e. "you with", |r stops the colored text
	SI_LIBCOMBAT_LOG_FORMAT_TARGETSELF_BLOCK = "your block|r with",  -- i.e. "your block", |r stops the colored text

	SI_LIBCOMBAT_LOG_FORMAT_ABSORBED = "<<1>> (Absorbed: <<2>>)",
	SI_LIBCOMBAT_LOG_FORMAT_HEALABSORB = "<<1>> |cffffffYour|r <<2>> absorbs |cffffff<<3>>|r damage.",  	-- absorb, i.e. "[0.0s] Your Harness Magicka absorbs 1234 damage. <<1>> = timestring, <<2>> = ability, <<3>> = hitValue

	SI_LIBCOMBAT_LOG_FORMATSTRING4 = "<<1>> |cffffffYou|r <<2>>hit |cffdddd<<3>> <<4>> for |cffffff<<5>>.",  	-- damage out, i.e. "[0.0s] You critically hit target with Light Attack for 1234.". <<1>> = timestring, <<2>> = crit,  <<3>> = targetstring,  <<4>> = ability, <<5>> = hitValue
	SI_LIBCOMBAT_LOG_FORMATSTRING5 = "<<1>> |cffdddd<<2>>|r <<3>>hits |cffffff<<4>> <<5>> for |cffffff<<6>>.",  -- damage in, i.e. "[0.0s] Someone critically hits you with Light Attack for 1234.". <<1>> = timestring, <<2>> = sourceName,  <<3>> = crit,  <<4>> = targetstring,  <<5>> = ability, <<6>> = hitValue
	SI_LIBCOMBAT_LOG_FORMATSTRING6 = "<<1>> |cffffffYou|r <<2>>hit |cffffff<<3>> <<4>> for |cffffff<<5>>.",  	-- damage self, i.e. "[0.0s] You critically hit yourself with Light Attack for 1234.". <<1>> = timestring, <<2>> = crit,  <<3>> = targetstring,  <<4>> = ability, <<5>> = hitValue

	SI_LIBCOMBAT_LOG_FORMATSTRING7 = "<<1>> |cffffffYou|r <<2>>heal |cddffdd<<3>>|r with <<4>> for |cffffff<<5>>.",  	-- healing out, i.e. "[0.0s] You critically heal target with Mutagen for 1234.". <<1>> = timestring, <<2>> = crit,  <<3>> = targetname,  <<4>> = ability, <<5>> = hitValue
	SI_LIBCOMBAT_LOG_FORMATSTRING8 = "<<1>> |cddffdd<<2>>|r <<3>>heals |cffffffyou|r with <<4>> for |cffffff<<5>>.",  	-- healing in, i.e. "[0.0s] Someone critically heals you with Mutagen for 1234.". <<1>> = timestring, <<2>> = sourceName, <<3>> = crit,  <<4>> = ability, <<5>> = hitValue
	SI_LIBCOMBAT_LOG_FORMATSTRING9 = "<<1>> |cffffffYou|r <<2>>heal |cffffffyourself|r with <<3>> for |cffffff<<4>>.",  -- healing self, i.e. "[0.0s] You critically heal yourself with Mutagen for 1234.". <<1>> = timestring, <<2>> = crit,  <<3>> = ability, <<4>> = hitValue

	SI_LIBCOMBAT_LOG_FORMATSTRING10 = "<<1>> |cffffff<<2>>|r <<3>> <<4>><<5>>.",  -- buff, i.e. "[0.0s] You gained Block from yourself." <<1>> = timestring, <<2>> = sourceName, <<3>> = changetype,  <<4>> = ability, <<5>> = source
	SI_LIBCOMBAT_LOG_FORMATSTRING11 = "<<1>> |cffffff<<2>>|r <<3>> <<4>><<5>>.",  -- buff, i.e. "[0.0s] You gained Block from yourself." <<1>> = timestring, <<2>> = sourceName, <<3>> = changetype,  <<4>> = ability, <<5>> = source
	SI_LIBCOMBAT_LOG_FORMATSTRING12 = "<<1>> |cffffff<<2>>|r <<3>> <<4>><<5>>.",  -- buff, i.e. "[0.0s] You gained Block from yourself." <<1>> = timestring, <<2>> = sourceName, <<3>> = changetype,  <<4>> = ability, <<5>> = source
	SI_LIBCOMBAT_LOG_FORMATSTRING13 = "<<1>> |cffffff<<2>>|r <<3>> <<4>><<5>>.",  -- buff, i.e. "[0.0s] You gained Block from yourself." <<1>> = timestring, <<2>> = sourceName, <<3>> = changetype,  <<4>> = ability, <<5>> = source

	SI_LIBCOMBAT_LOG_FORMATSTRING14 = "<<1>> Your <<2>> <<3>> |cffffff<<4>>|r<<5>>.",  -- buff, i.e. "[0.0s] Weaponpower increased to 1800 (+100)". <<1>> = timeString, <<2>> = stat, <<3>> = changeText,  <<4>> = value, <<5>> = changeValueText

	SI_LIBCOMBAT_LOG_FORMATSTRING15 = "<<1>> |cffffffYou|r <<2>> <<3>> <<4>> <<5>>.",  -- resource, i.e. "[0.0s] You gained 200 Magicka (Base Regeneration)" <<1>> = timeString, <<2>> = changeTypeString, <<3>> = amount,  <<4>> = resource, <<5>> = ability

	SI_LIBCOMBAT_LOG_FORMATSTRING20 = "<<1>> <<2>>: <<3>>% HP. (<<4>>/<<5>>)",  -- boss HP, i.e. "[0.0s] Z'Maja: 98% HP. (63707822/64683864)" 	<<1>> = timeString, <<2>> = bossName, <<3>> = percent, <<4>> = currenthp, <<5>> = maxhp
	SI_LIBCOMBAT_LOG_FORMATSTRING21 = "<<1>> FPS: <<2>> (<<3>> - <<4>>), Ping: <<5>> ms",  -- performance, i.e. "[0.0s] FPS: 80 (59 - 85), Ping: 79 ms" <<1>> = timeString, <<2>> = average FPS, <<3>> = minimum FPS, <<4>> = maximum FPS, <<5>> = ping

	SI_LIBCOMBAT_LOG_FORMATSTRING_SKILLS1 = "<<1>> You cast <<2>><<3>>.", 							-- skill used, i.e. "[0.0s] You used Puncturing Sweeps (Delay: 85 ms). 			<<1>> = timestring, <<2>> = Ability, <<3>> = skill delay
	SI_LIBCOMBAT_LOG_FORMATSTRING_SKILLS2 = "<<1>> You start to cast <<2>><<3>>.", 					-- skill used, i.e. "[0.0s] You start to cast Solar Barrage (Delay: 85 ms). 	<<1>> = timestring, <<2>> = Ability, <<3>> = skill delay
	SI_LIBCOMBAT_LOG_FORMATSTRING_SKILLS3 = "<<1>> You start to channel <<2>><<3>>.", 				-- skill used, i.e. "[0.0s] You start to channel Blazing Spear (Delay: 85 ms). 	<<1>> = timestring, <<2>> = Ability, <<3>> = skill delay
	SI_LIBCOMBAT_LOG_FORMATSTRING_SKILLS4 = "<<1>> You finished casting <<2>>.", 					-- skill used, i.e. "[0.0s] You finished casting Blazing Spear. 				<<1>> = timestring, <<2>> = Ability
	SI_LIBCOMBAT_LOG_FORMATSTRING_SKILLS5 = "<<1>> Your cast of <<2>> was registered.", 			-- skill used, i.e. "[0.0s] You finished casting Blazing Spear. 				<<1>> = timestring, <<2>> = Ability
	SI_LIBCOMBAT_LOG_FORMATSTRING_SKILLS6 = "<<1>> Your cast of <<2>> was activated from queue.", 	-- skill used, i.e. "[0.0s] You finished casting Blazing Spear. 				<<1>> = timestring, <<2>> = Ability

    SI_LIBCOMBAT_LOG_FORMATSTRING_DEATH1 = "<<1>> |cffffff<<2>>|r |cff3333died|r.<<4>>",
    SI_LIBCOMBAT_LOG_FORMATSTRING_DEATH2 = "<<1>> |cffffff<<2>>|r |c00cc00ressurected|r.",
    SI_LIBCOMBAT_LOG_FORMATSTRING_DEATH3 = "<<1>> <<2>> <<3>> <<4>>.",
	SI_LIBCOMBAT_LOG_FORMATSTRING_DEATH4 = "<<1>> <<2>> <<3>> <<4>>.",

	SI_LIBCOMBAT_LOG_FORMATSTRING_SKILLDELAY = " (Delay: |cffffff<<1>>|r ms)",

	SI_LIBCOMBAT_LOG_RESURRECT1 = "|c00cc00resurrect|r",
	SI_LIBCOMBAT_LOG_RESURRECT2 = "|c00cc00resurrects|r",

	SI_LIBCOMBAT_CUSTOM_ABILITY_FORMAT = GetString(SI_ABILITY_NAME) .. " (<<2>>)",

}

SI_LIBCOMBAT_LOADED = true

for stringId, stringValue in pairs(strings) do
	ZO_CreateStringId(stringId, stringValue)
	SafeAddVersion(stringId, 1)
end