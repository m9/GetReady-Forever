-- The versions of outside data the tools work with, and the SHA-256 of each download.
-- Change it with: luajit tools/deps.lua use <name> [version]
return {
	questiedb = {
		version = "1.1.1",
		commit = "4dbb82440a27856f8dccf57094a5d792cdc7cc9b",
		files = {
			["QuestieDB-1.1.1-Forever.zip"] = "2527118d861e497fa40bdb6d061883bf09649d5f96e09de6885f578aefbb5e59",
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
