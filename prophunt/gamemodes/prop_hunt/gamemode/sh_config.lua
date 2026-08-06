-- Props will not be able to become these models
BANNED_PROP_MODELS = {
	"models/props/cs_assault/dollar.mdl",
	"models/props/cs_assault/money.mdl",
	"models/props/cs_office/snowman_arm.mdl",
	"models/props/cs_office/computer_mouse.mdl",
	"models/props/cs_office/projector_remote.mdl",
	"models/props/cs_militia/reload_bullet_tray.mdl",
	"models/foodnhouseholditems/egg.mdl"
}


-- Maximum time (in minutes) for this fretta gamemode (Default: 30)
GAME_TIME = 30


-- Number of seconds hunters are blinded/locked at the beginning of the map (Default: 30)
HUNTER_BLINDLOCK_TIME = 30


-- Health points removed from hunters when they shoot  (Default: 25)
HUNTER_FIRE_PENALTY = 5


-- How much health to give back to the Hunter after killing a prop (Default: 100)
HUNTER_KILL_BONUS = 100


-- If you loose one of these will be played
-- Set blank to disable

-- // DEV HELP: why this is  not working anymore? \\ --
LOSS_SOUNDS = {
	"vo/announcer_failure.wav",
	"vo/announcer_you_failed.wav"
}

-- Sound files hunters can taunt with
-- You need at least 2 files listed here
HUNTER_TAUNTS = {

	-- Normal Taunts
	"taunts/hunters/come_to_papa.wav",
	"taunts/hunters/father.mp3",
	"taunts/hunters/fireassis.wav",
	"taunts/hunters/hitassist.wav",
	"taunts/hunters/now_what.wav",
	"taunts/hunters/you_dont_know_the_power.wav",
	"taunts/hunters/you_underestimate_the_power.wav",
	"taunts/hunters/glados-president.wav",
	"taunts/hunters/rude.mp3",
	"taunts/hunters/soul.mp3",
	"taunts/hunters/illfindyou.mp3",
	
	-- Half-Life 2
	"vo/k_lab/ba_guh.wav",

	-- Male
	"vo/npc/male01/vanswer13.wav",
	"vo/npc/male01/thehacks01.wav",
	"vo/npc/male01/runforyourlife02.wav",
	"vo/npc/male01/overhere01.wav",
	"vo/npc/male01/overthere01.wav",
	"vo/npc/male01/overthere02.wav"
}


-- Sound files props can taunt with
-- You need at least 2 files listed here
PROP_TAUNTS = {
	"taunts/boom_headshot.wav",
	"taunts/go_away_or_i_shall.wav",
	"taunts/ill_be_back.wav",
	"taunts/negative.wav",
	"taunts/doh.wav",
	"taunts/oh_yea_he_will_pay.wav",
	"taunts/ok_i_will_tell_you.wav",
	"taunts/please_come_again.wav",
	"taunts/threat_neutralized.wav",
	"taunts/what_is_wrong_with_you.wav",
	"taunts/woohoo.wav",
	"taunts/props/1.mp3",
	"taunts/props/2.mp3",
	"taunts/props/3.mp3",
	"taunts/props/4.mp3",
	
	-- // Half-life 2 taunts \\ --
	
	-- Citadel part
	"vo/citadel/br_ohshit.wav",
	"vo/citadel/br_youfool.wav",
	"vo/citadel/br_youneedme.wav",
	
	-- Coast part
	"vo/coast/odessa/male01/nlo_cheer01.wav",
	"vo/coast/odessa/male01/nlo_cheer02.wav",
	"vo/coast/odessa/male01/nlo_cheer03.wav",
	"vo/coast/odessa/male01/nlo_cheer04.wav",
	"vo/coast/odessa/female01/nlo_cheer01.wav",
	"vo/coast/odessa/female01/nlo_cheer02.wav",
	"vo/coast/odessa/female01/nlo_cheer03.wav",
	
	-- Gman
	"vo/gman_misc/gman_riseshine.wav",
	
	-- // General NPC Quotes \\ --
		
	-- Barney
	"vo/npc/barney/ba_damnit.wav",
	"vo/npc/barney/ba_laugh01.wav",
	"vo/npc/barney/ba_laugh02.wav",
	"vo/npc/barney/ba_laugh03.wav",
	"vo/npc/barney/ba_laugh04.wav",
	
	-- Male Citizen
	"vo/npc/male01/hacks01.wav",
	"vo/npc/male01/hacks02.wav",
	"vo/npc/male01/vanswer01.wav",
	"vo/npc/male01/question05.wav",
	"vo/npc/male01/question06.wav",
	"vo/npc/male01/answer34.wav",
	"vo/npc/male01/question30.wav",
	"vo/npc/male01/question26.wav",
	"vo/npc/male01/incoming02.wav",
	"vo/npc/male01/gethellout.wav",
	
	-- Father Grigori
	"vo/ravenholm/madlaugh04.wav",
	
	-- Fixed taunts
	"taunts/fixed/13_fix.wav",
	"taunts/fixed/bees_fix.wav",
	
	-- Additionals ==
	
	-- Moved from Hunter to Props (this supposed to be props...)
	"taunts/hunters/laugh.wav"
}


-- Hunters can now pick from every player model GMod registers via
-- player_manager.AllValidModels() (F4 while on Hunters, or console command
-- ph_hunter_model_menu) - selection applies live, no respawn needed. The old
-- hardcoded 4-model list has been removed in favor of that full registry.


-- Folder (relative to sound/) that the Prop Taunt Menu [F4/F3] auto-scans for
-- .wav/.mp3/.ogg files - drop a new file in content/sound/prophunt_taunts/props/
-- and it shows up automatically, no code edits needed.
--
-- This folder name is unique to this addon on purpose - file.Find(..., "GAME")
-- searches every mounted addon's content merged together, so a generic name like
-- "taunts/props/" risks other addons' sounds leaking into this menu (this
-- happened before - see git history). Keep this unique; ask before changing it.
PROP_TAUNT_FOLDER = "prophunt_taunts/props/"


-- Seconds a player has to wait before they can taunt again (Default: 2 or 3)
TAUNT_DELAY = 2


-- Rounds played on a map (Default: 10)
ROUNDS_PER_MAP = 10


-- Time (in seconds) for each round (Default: 300)
ROUND_TIME = 300


-- Determains if players should be team swapped every round [0 = No, 1 = Yes] (Default: 1)
SWAP_TEAMS_EVERY_ROUND = 1


-- Determains if teams should still be swapped when the score is 0-0 [0 = No, 1 = Yes] (Default: 0)
SWAP_TEAMS_POINTS_ZERO = 0


-- If you win, one of these will be played
-- Set blank to disable

-- // DEV HELP: why this is  not working anymore? \\ --
VICTORY_SOUNDS = {
	"vo/announcer_success.wav",
	"vo/announcer_victory.wav",
	"vo/announcer_we_succeeded.wav"
}