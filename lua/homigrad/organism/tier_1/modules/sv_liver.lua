local max, min, clamp, Approach, Rand, random = math.max, math.min, math.Clamp, math.Approach, math.Rand, math.random

hg.organism.module.liver = {}
local module = hg.organism.module.liver

--[[
	LIVER MODULE
	org.liver is still the "total damage" scalar (0..1) so existing damage code that does
	`org.liver = org.liver + dmg` keeps working. Every tick we look at how much org.liver went up
	(delta) and turn that hit into real injuries:

	contusion  (livercontusion)  - bruising: pain + stamina debuff, heals by itself
	laceration (liverlac)        - active bleeding, depth decides rate; shallow ones clot, deep ones don't
	hematoma   (liverhematoma)   - blood trapped under the capsule, can rupture later (delayed hemorrhage)
	bile leak  (liverbile)       - torn bile ducts, chemical peritonitis until walled off
	biloma     (liverbiloma)     - walled-off bile collection, infection nidus
	necrosis   (livernecrosis)   - devascularised tissue dying after a delay, fever + liver failure
	infection  (liverinfection)  - abscess / sepsis, only starts after a delay

	All durations are in seconds and sized for a round, not for real days. Tune CFG.
]]

local CFG = {
	min_event = 0.02,           -- ignore hits smaller than this
	lac_threshold = 0.12,       -- hit size needed to cut the parenchyma
	hematoma_threshold = 0.08,
	bile_threshold = 0.20,
	necrosis_threshold = 0.45,

	bleed_scale = 18,           -- blood/s at lac = 1 (before pulse scaling)
	bleed_exp = 1.5,            -- deeper = disproportionately worse
	selfseal_max = 0.45,        -- lacerations deeper than this never clot on their own
	clot_time = 90,

	contusion_heal = 300,
	hematoma_resorb = 600,
	hematoma_rupture = 0.9,
	rupture_delay = {120, 360},
	rebleed_delay = {90, 300},
	necrosis_delay = {60, 240},
	necrosis_regen = 1800,      -- liver regenerates, slowly, when not infected

	biloma_rate = 150,
	bile_seal = 240,
	infection_delay = 300,      -- minimum time after injury before infection can start
	infection_time = 420,       -- time for infection to go 0 -> 1 on a bad nidus

	max_fever = 40.3,
}

local function RR(t) return Rand(t[1], t[2]) end

module[1] = function(org)
	org.liver = 0
	org.liverprev = 0
	org.liverclock = 0
	org.liverlastinjury = -10000
	org.liverevents = {}

	org.livercontusion = 0
	org.liverlac = 0
	org.liverhematoma = 0
	org.liverbile = 0
	org.liverbiloma = 0
	org.livernecrosis = 0
	org.liverinfection = 0

	org.liverfunction = 1
	org.liverabx = 0      -- seconds of antibiotic cover left (set from a medication item, optional)
end

local function Tell(org, text, key)
	if org.isPly and not org.otrub and IsValid(org.owner) then
		org.owner:Notify(text, 60, key, 0)
	end
end

local function Flag(org, cond, text, key)
	if not (org.isPly and IsValid(org.owner)) then return end
	if cond and not org.otrub then
		org.owner:Notify(text, true, key, 10)
	else
		org.owner:ResetNotification(key)
	end
end

local function Schedule(org, kind, delay, power)
	org.liverevents[#org.liverevents + 1] = {at = org.liverclock + delay, kind = kind, power = power}
end

-- hematoma bursts through the capsule: sudden hemorrhage + pain spike
local function RuptureHematoma(org)
	local vol = org.liverhematoma
	org.liverhematoma = 0
	if vol <= 0.05 then return end

	org.liverlac = min(max(org.liverlac, 0.25 + vol * 0.6), 1)
	org.internalBleed = org.internalBleed + 3 + vol * 6
	org.painadd = min(org.painadd + 20 + vol * 30, 150)
	org.shock = min(max(org.shock, org.shock + 10 + vol * 15), 60)

	Tell(org, "Something just tore in my side... it hurts so much...", "liver_rupture")
end

-- turn a fresh chunk of liver damage into concrete injuries
local function ProcessInjury(org, delta)
	if delta < CFG.min_event then return end
	org.liverlastinjury = org.liverclock

	org.livercontusion = min(org.livercontusion + delta, 1)

	if delta >= CFG.lac_threshold then
		local depth = clamp(delta * Rand(0.8, 1.3), 0, 1)
		org.liverlac = min(max(org.liverlac, depth) + min(org.liverlac, depth) * 0.5, 1)

		-- shallow cut that seems fine now, may start bleeding again when the clot gets pulled off
		if depth >= 0.15 and depth < CFG.selfseal_max and random() < 0.35 then
			Schedule(org, "rebleed", RR(CFG.rebleed_delay), depth * Rand(0.6, 1))
		end
	end

	if delta >= CFG.hematoma_threshold and random() < clamp(delta * 2, 0.2, 0.9) then
		org.liverhematoma = min(org.liverhematoma + delta * Rand(0.4, 0.8), 1)

		if random() < 0.35 then
			Schedule(org, "rupture", RR(CFG.rupture_delay), org.liverhematoma)
		end
	end

	if delta >= CFG.bile_threshold and random() < clamp(delta, 0.15, 0.7) then
		org.liverbile = min(org.liverbile + delta * 0.6, 1)
	end

	if delta >= CFG.necrosis_threshold or org.liverlac >= 0.7 then
		Schedule(org, "necrosis", RR(CFG.necrosis_delay), clamp(delta * 0.5, 0.1, 0.6))
	end
end

local function RunEvents(org)
	local events = org.liverevents
	for i = #events, 1, -1 do
		local ev = events[i]
		if org.liverclock >= ev.at then
			if ev.kind == "rebleed" then
				-- fires when the patient is exerting, or eventually on its own
				if org.heartbeat > 110 or org.liverclock > ev.at + 60 then
					org.liverlac = max(org.liverlac, ev.power)
					org.painadd = min(org.painadd + 10, 150)
					Tell(org, "My side is wet... it's bleeding again.", "liver_rebleed")
					table.remove(events, i)
				end
			elseif ev.kind == "rupture" then
				if org.liverhematoma > 0.05 then RuptureHematoma(org) end
				table.remove(events, i)
			elseif ev.kind == "necrosis" then
				org.livernecrosis = min(org.livernecrosis + ev.power, 1)
				table.remove(events, i)
			else
				table.remove(events, i)
			end
		end
	end
end

module[2] = function(owner, org, dt)
	if not org.alive then return end

	org.liverclock = org.liverclock + dt

	-- 1. new damage (or healing) applied from outside to org.liver
	local delta = org.liver - org.liverprev
	if delta > 0 then
		ProcessInjury(org, delta)
	elseif delta < -0.001 and org.liverprev > 0 then
		local ratio = max(org.liver / org.liverprev, 0)
		org.livercontusion = org.livercontusion * ratio
		org.liverlac = org.liverlac * ratio
		org.liverhematoma = org.liverhematoma * ratio
	end

	RunEvents(org)

	-- 2. liver function: failing liver = worse clotting, toxins, confusion
	local necrosis = org.livernecrosis
	local fn = clamp(1 - necrosis * 1.2 - org.livercontusion * 0.15 - org.liverlac * 0.2, 0, 1)
	org.liverfunction = fn
	local coagulopathy = 1 + max(0.5 - fn, 0) * 2
	local cold = (org.temperature < 35) and 0.5 or 1

	org.liverabx = max(org.liverabx - dt, 0)

	-- 3. laceration: bleeding + clotting
	if org.liverlac > 0 then
		local rate = (org.liverlac ^ CFG.bleed_exp) * CFG.bleed_scale * coagulopathy

		-- an intact capsule contains part of the bleed as a growing hematoma
		if org.liverhematoma > 0 and org.liverhematoma < CFG.hematoma_rupture then
			org.liverhematoma = min(org.liverhematoma + rate * 0.6 * dt / 150, 1)
			rate = rate * 0.4
		end

		-- feeds the shared internal bleed (blood loss ~ internalBleed / 14 * 10 * pulse / 70)
		org.internalBleed = max(org.internalBleed, rate / 1.4)

		if org.liverlac < CFG.selfseal_max then
			local boost = (org.internalBleedHeal > 0) and 4 or 1
			local t = CFG.clot_time * (1 + org.liverlac * 4) * coagulopathy / (boost * cold)
			org.liverlac = max(org.liverlac - dt / t, 0)
			if org.liverlac < 0.02 then org.liverlac = 0 end
		end
	end

	if org.liverhematoma >= CFG.hematoma_rupture then
		RuptureHematoma(org)
	elseif org.liverhematoma > 0 and org.liverlac == 0 then
		org.liverhematoma = max(org.liverhematoma - dt / CFG.hematoma_resorb, 0)
	end

	-- 4. bile leak -> biloma
	if org.liverbile > 0 then
		org.liverbiloma = min(org.liverbiloma + org.liverbile * dt / CFG.biloma_rate, 1)
		if org.liverbile < 0.3 then
			org.liverbile = max(org.liverbile - dt / CFG.bile_seal, 0)
		end
	elseif org.liverbiloma > 0 and org.liverinfection <= 0 then
		org.liverbiloma = max(org.liverbiloma - dt / 900, 0)
	end

	-- free bile irritates the peritoneum until it is walled off
	local peritonitis = org.liverbile * (1 - min(org.liverbiloma * 2, 1) * 0.7)

	-- 5. infection / abscess: needs a nidus and time
	local nidus = (org.liverbiloma > 0.25 and org.liverbiloma or 0) + necrosis + org.liverhematoma * 0.3
	local abx = org.liverabx > 0

	if org.liverinfection <= 0 then
		if nidus > 0 and (org.liverclock - org.liverlastinjury) > CFG.infection_delay then
			if random() < nidus * 0.02 * dt * (abx and 0.1 or 1) then
				org.liverinfection = 0.02
			end
		end
	else
		if abx then
			-- antibiotics clear what they can, but a persistent collection or dead tissue keeps it alive
			local floor = (org.liverbiloma > 0.25 or necrosis > 0.3) and 0.3 or 0
			org.liverinfection = max(org.liverinfection - dt / (CFG.infection_time * 0.5), floor)
		else
			org.liverinfection = min(org.liverinfection + dt / CFG.infection_time * (1 + nidus), 1)
		end
	end
	local inf = org.liverinfection

	-- 6. slow regeneration of the liver
	org.livercontusion = max(org.livercontusion - dt / CFG.contusion_heal * (1 - necrosis), 0)
	if inf < 0.2 and necrosis > 0 then
		org.livernecrosis = max(org.livernecrosis - dt / CFG.necrosis_regen, 0)
	end

	-- 7. systemic effects
	local painTarget = org.livercontusion * 20 + org.liverlac * 28 + org.liverhematoma * 22
		+ peritonitis * 35 + inf * 25 + necrosis * 15
	if painTarget > 1 then
		org.avgpain = max(org.avgpain, min(painTarget, 78))
	end

	if org.stamina then
		local debuff = clamp(
			org.livercontusion * 0.25 + org.liverhematoma * 0.2 + (1 - fn) * 0.4
			+ inf * 0.3 + peritonitis * 0.2, 0, 0.7)
		if debuff > 0 then
			org.stamina[1] = min(org.stamina[1], org.stamina.max * (1 - debuff))
		end
	end

	local feverTarget = 36.7 + inf * 3.3 + necrosis * 0.8 + peritonitis * 0.6
	feverTarget = min(feverTarget, CFG.max_fever)
	if (inf > 0.15 or necrosis > 0.3 or peritonitis > 0.3) and org.temperature < feverTarget then
		org.temperature = Approach(org.temperature, feverTarget, dt / 45)
	end

	if inf > 0.7 then -- sepsis
		org.consciousness = min(org.consciousness, 1 - (inf - 0.7) * 2)
		org.shock = max(org.shock, (inf - 0.7) * 60)
	end

	if fn < 0.5 and not org.otrub then
		org.wantToVomit = (org.wantToVomit or 0) + random() * dt * (0.5 - fn) * 0.006
	end

	if fn < 0.35 then -- hepatic encephalopathy
		org.disorientation = max(org.disorientation or 0, (0.35 - fn) * 8)
	end

	if fn < 0.2 then
		org.consciousness = min(org.consciousness, 0.5 + fn * 2.5)
	end

	-- 8. patient feedback
	Flag(org, org.livercontusion > 0.05 and org.liverlac == 0, "A dull ache in my right side.", "liver1")
	Flag(org, peritonitis > 0.3, "My whole belly hurts... it keeps getting worse.", "liver2")
	Flag(org, inf > 0.2, "I feel feverish and weak, my side is throbbing.", "liver3")
	Flag(org, fn < 0.4, "Everything is hazy... I feel so sick.", "liver4")

	-- 9. keep org.liver as the worst component so other modules still read a sane value
	org.liver = clamp(max(org.livercontusion, org.liverlac, org.livernecrosis, org.liverhematoma * 0.6), 0, 1)
	org.liverprev = org.liver
end

-- for palpation / stethoscope / scanner style readouts
function hg.organism.LiverStatus(org)
	local out = {}
	if org.livercontusion > 0.05 then out[#out + 1] = "RUQ tenderness" end
	if org.liverlac > 0 then out[#out + 1] = "active hepatic bleeding" end
	if org.liverhematoma > 0.1 then out[#out + 1] = "subcapsular hematoma" end
	if org.liverbile > 0 then out[#out + 1] = "bile leak" end
	if org.liverbiloma > 0.25 then out[#out + 1] = "biloma" end
	if org.livernecrosis > 0.1 then out[#out + 1] = "hepatic necrosis" end
	if org.liverinfection > 0.2 then out[#out + 1] = "abscess / infection" end
	return out
end
