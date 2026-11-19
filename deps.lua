-- The versions of outside data the tools work with, and the SHA-256 of each download.
-- Change it with: luajit tools/deps.lua use <name> [version]
return {
	questiedb = {
		version = "1.1.3",
		commit = "8b8df2dc12a34e2eb82bc7105b40405dce1c01f7",
		files = {
			["QuestieDB-1.1.3-Forever.zip"] = "98201b11bf9854895f2c966d3924b9fb10d18d10dcad7540465e7d761c1f624d",
		},
	},
	attune = {
		version = "16001-41",
		commit = "d6ba859a625e2c7be3618f36597fcd85853f905f",
		files = {
			["Attune.toc"] = "4931efed957ea7829de8e57e4f27ab8fa54d03016a464b2d38994c8152ed3223",
			["AttuneClassQuests.lua"] = "3953b4957c167d0d13429897fbdf7ca75e76f22ec41af47f1c446f752f8ad8a6",
			["AttuneData.lua"] = "94494b3b61d8433b27774e871c3261b1deff3a3637ef83f83fc1e8d9eeb834f5",
		},
	},
}
