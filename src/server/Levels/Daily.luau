-- Daily.luau


return {
	packName = "Daily Challenge",
	packColor = Color3.fromRGB(84, 126, 255),

	levelColors = {
		Color3.fromRGB(84, 126, 255),
		Color3.fromRGB(255, 124, 184),
		Color3.fromRGB(87, 206, 164),
		Color3.fromRGB(255, 176, 92),
		Color3.fromRGB(166, 128, 255),
	},

	levels = {
	-- Level 1
	{
		letters = {'A', 'N', 'G', 'S', 'T', 'E'},
		grid = {
			".........N",
			".......A.E",
			".....ANGST",
			"TENS.G.E.S",
			"...A.E.S..",
			"...GENT...",
			"...E.T....",
		},
		words = {'AGENT', 'AGES', 'ANGST', 'GENT', 'NETS', 'SAGE', 'TENS'},
		bonus = {'AGE', 'ANT', 'ANTE', 'EAT', 'GAS', 'GET', 'NET', 'SAG', 'SAT', 'SEA', 'SET', 'TAG', 'TAN', 'TEA', 'TEN'},
	},
	-- Level 2
	{
		letters = {'L', 'E', 'S', 'T', 'A', 'R'},
		grid = {
			"TEAS",
			"...E",
			"L..A",
			"EARL",
			"S.E.",
			"TEAR",
			"..L.",
		},
		words = {'EARL', 'LEST', 'REAL', 'SEAL', 'TEAR', 'TEAS'},
		bonus = {'ARE', 'ART', 'ARTS', 'EAR', 'EARS', 'EAST', 'EAT', 'EATS', 'LET', 'RAT', 'SAT', 'SEA', 'SET', 'TAR', 'TEA'},
	},
	-- Level 3
	{
		letters = {'W', 'E', 'N', 'T', 'L', 'A'},
		grid = {
			"......WENT",
			"...LATE...",
			"...A..A...",
			"...N..L...",
			"WALE......",
			"E.........",
			"L.........",
			"T.........",
		},
		words = {'LANE', 'LATE', 'WALE', 'WEAL', 'WELT', 'WENT'},
		bonus = {'ANT', 'ANTE', 'EAT', 'LAW', 'LAWN', 'LEAN', 'LENT', 'LET', 'NEAT', 'NET', 'NEW', 'TAN', 'TEA', 'TEN', 'WET'},
	},
	-- Level 4
	{
		letters = {'T', 'A', 'R', 'P', 'M', 'E'},
		grid = {
			".....R....",
			"..TAME....",
			"..A..A..M.",
			"TERM.PARE.",
			"..P.....T.",
			"......REAM",
		},
		words = {'META', 'PARE', 'REAM', 'REAP', 'TAME', 'TARP', 'TERM'},
		bonus = {'APE', 'ARE', 'ARM', 'ART', 'EAR', 'EAT', 'MAP', 'MAT', 'MET', 'PAR', 'PAT', 'PEA', 'PET', 'RAM', 'RAP'},
	},
	-- Level 5
	{
		letters = {'A', 'I', 'D', 'E', 'R', 'M'},
		grid = {
			"....A....",
			"....I...A",
			"....R...I",
			"....E.A.M",
			"...ADMIRE",
			"...I..M.R",
			"...D..E..",
			"ARMED.D..",
			"...R.....",
		},
		words = {'ADMIRE', 'AIDER', 'AIMED', 'AIMER', 'AIRED', 'ARMED'},
		bonus = {'AID', 'AIR', 'ARE', 'ARM', 'DAM', 'DAME', 'DARE', 'DIE', 'DIM', 'EAR', 'MAD', 'RAM', 'RED', 'RID', 'RIM'},
	},
	-- Level 6
	{
		letters = {'S', 'W', 'I', 'G', 'N', 'O'},
		grid = {
			"......W",
			"......I",
			"SONG..N",
			"W..IONS",
			"I..N...",
			"G..SNOW",
		},
		words = {'GINS', 'IONS', 'SNOW', 'SONG', 'SWIG', 'WINS'},
		bonus = {'GOWN', 'NOW', 'OWN', 'OWN', 'SIGN', 'SIN', 'SING', 'SON', 'SOW', 'SOWN', 'WIG', 'WIGS', 'WIN', 'WING', 'WON'},
	},
	-- Level 7
	{
		letters = {'A', 'R', 'M', 'E', 'D', 'N'},
		grid = {
			"..M..",
			"AMEND",
			"R.N.A",
			"M.D.R",
			"E...E",
			"DARN.",
			"...E.",
			"...R.",
			"...D.",
		},
		words = {'AMEND', 'ARMED', 'DARE', 'DARN', 'MEND', 'NERD'},
		bonus = {'AND', 'ARE', 'ARM', 'DAM', 'DAME', 'DEAN', 'DEN', 'EAR', 'END', 'MAD', 'MAN', 'MEN', 'RAM', 'RAN', 'RED'},
	},
	-- Level 8
	{
		letters = {'A', 'R', 'M', 'E', 'D', 'I'},
		grid = {
			".......A.",
			".......R.",
			".......M.",
			"....AIDER",
			"AIRED..D.",
			"....M....",
			"...AIMED.",
			"....R....",
			".AIMER...",
		},
		words = {'ADMIRE', 'AIDER', 'AIMED', 'AIMER', 'AIRED', 'ARMED'},
		bonus = {'AID', 'AIR', 'ARE', 'ARM', 'DAM', 'DAME', 'DARE', 'DIE', 'DIM', 'EAR', 'MAD', 'RAM', 'RED', 'RID', 'RIM'},
	},
	-- Level 9
	{
		letters = {'D', 'E', 'A', 'N', 'M', 'L'},
		grid = {
			"...M..",
			"..MEND",
			"...A..",
			"DEAN..",
			"A.....",
			"LANE..",
			"E.A...",
			"..M...",
			"..E...",
		},
		words = {'DALE', 'DEAN', 'LANE', 'MEAN', 'MEND', 'NAME'},
		bonus = {'AND', 'DAM', 'DAME', 'DEAL', 'DEN', 'ELM', 'END', 'LAD', 'LADE', 'LAME', 'LAND', 'LED', 'MAD', 'MAN', 'MEN'},
	},
	-- Level 10
	{
		letters = {'A', 'I', 'D', 'E', 'R', 'M'},
		grid = {
			"....A....",
			"....I...A",
			"....R...I",
			"....E.A.M",
			"...ADMIRE",
			"...I..M.R",
			"...D..E..",
			"ARMED.D..",
			"...R.....",
		},
		words = {'ADMIRE', 'AIDER', 'AIMED', 'AIMER', 'AIRED', 'ARMED'},
		bonus = {'AID', 'AIR', 'ARE', 'ARM', 'DAM', 'DAME', 'DARE', 'DIE', 'DIM', 'EAR', 'MAD', 'RAM', 'RED', 'RID', 'RIM'},
	},
	-- Level 11
	{
		letters = {'S', 'W', 'A', 'T', 'E', 'P'},
		grid = {
			"STEP...",
			"W..A...",
			"A.SWAT.",
			"P..S.E.",
			".....A.",
			"...WEST",
		},
		words = {'PAWS', 'STEP', 'SWAP', 'SWAT', 'TEAS', 'WEST'},
		bonus = {'APE', 'EAT', 'PAT', 'PAW', 'PEA', 'PET', 'SAP', 'SAT', 'SAW', 'SEA', 'SET', 'SEW', 'TAP', 'TEA', 'WAS'},
	},
	-- Level 12
	{
		letters = {'E', 'A', 'R', 'N', 'S', 'T'},
		grid = {
			"...E..",
			"..EATS",
			"E..R..",
			"ARTS..",
			"R.....",
			"NEAR..",
			"...A..",
			"...N..",
			"...T..",
		},
		words = {'ARTS', 'EARN', 'EARS', 'EATS', 'NEAR', 'RANT'},
		bonus = {'ANT', 'ARE', 'ART', 'EAR', 'EAT', 'NET', 'RAN', 'RAT', 'SAT', 'SEA', 'SET', 'TAN', 'TAR', 'TEA', 'TEN'},
	},
	-- Level 13
	{
		letters = {'M', 'E', 'A', 'D', 'I', 'L'},
		grid = {
			"....M.",
			"D.MEAD",
			"E...I.",
			"AIMED.",
			"L.E...",
			"..A...",
			"MELD..",
		},
		words = {'AIMED', 'DEAL', 'MAID', 'MEAD', 'MEAL', 'MELD'},
		bonus = {'AID', 'DALE', 'DAM', 'DAME', 'DIAL', 'DIE', 'DIM', 'DIME', 'ELM', 'IDEA', 'LAD', 'LED', 'LID', 'LIE', 'MAD'},
	},
	-- Level 14
	{
		letters = {'S', 'N', 'I', 'T', 'P', 'H'},
		grid = {
			"HIPS",
			"I...",
			"NITS",
			"T..H",
			".S.I",
			"SNIP",
			".I..",
			".T..",
		},
		words = {'HINT', 'HIPS', 'NITS', 'SHIP', 'SNIP', 'SNIT'},
		bonus = {'HIP', 'HIS', 'HIT', 'HITS', 'ITS', 'NIP', 'NIPS', 'NIT', 'PIN', 'PINS', 'PIT', 'SIN', 'SIP', 'SIT', 'TIP'},
	},
	-- Level 15
	{
		letters = {'A', 'I', 'R', 'E', 'D', 'M'},
		grid = {
			"....A....",
			"....I...A",
			"....R...I",
			"....E.A.M",
			"...ADMIRE",
			"...I..M.R",
			"...D..E..",
			"ARMED.D..",
			"...R.....",
		},
		words = {'ADMIRE', 'AIDER', 'AIMED', 'AIMER', 'AIRED', 'ARMED'},
		bonus = {'AID', 'AIR', 'ARE', 'ARM', 'DAM', 'DAME', 'DARE', 'DIE', 'DIM', 'EAR', 'MAD', 'RAM', 'RED', 'RID', 'RIM'},
	},
	-- Level 16
	{
		letters = {'A', 'R', 'T', 'S', 'E', 'B'},
		grid = {
			".T.T.",
			".A.A.",
			".R.B.",
			".EAST",
			"T.R..",
			"EATS.",
			"A.S..",
			"R....",
		},
		words = {'ARTS', 'EAST', 'EATS', 'TABS', 'TARE', 'TEAR'},
		bonus = {'ARE', 'ART', 'BAR', 'BARE', 'BAT', 'BET', 'EAR', 'EAT', 'RAT', 'SAT', 'SEA', 'SET', 'TAB', 'TAR', 'TEA'},
	},
	-- Level 17
	{
		letters = {'D', 'A', 'M', 'E', 'L', 'T'},
		grid = {
			"...META",
			"...A.A.",
			".L.L.M.",
			"DAME.E.",
			".T.....",
			"MELT...",
		},
		words = {'DAME', 'LATE', 'MALE', 'MELT', 'META', 'TAME'},
		bonus = {'DALE', 'DAM', 'DATE', 'DEAL', 'EAT', 'ELM', 'LAD', 'LADE', 'LAME', 'LED', 'LET', 'MAD', 'MAT', 'MET', 'TEA'},
	},
	-- Level 18
	{
		letters = {'A', 'I', 'M', 'E', 'R', 'D'},
		grid = {
			"....A....",
			"....I...A",
			"....R...I",
			"....E.A.M",
			"...ADMIRE",
			"...I..M.R",
			"...D..E..",
			"ARMED.D..",
			"...R.....",
		},
		words = {'ADMIRE', 'AIDER', 'AIMED', 'AIMER', 'AIRED', 'ARMED'},
		bonus = {'AID', 'AIR', 'ARE', 'ARM', 'DAM', 'DAME', 'DARE', 'DIE', 'DIM', 'EAR', 'MAD', 'RAM', 'RED', 'RID', 'RIM'},
	},
	-- Level 19
	{
		letters = {'A', 'L', 'I', 'E', 'N', 'V'},
		grid = {
			"....A.",
			"ALIEN.",
			"L...V.",
			"I.VEIL",
			"V.E.L.",
			"EVIL..",
			"..N...",
		},
		words = {'ALIEN', 'ALIVE', 'ANVIL', 'EVIL', 'VEIL', 'VEIN'},
		bonus = {'LAIN', 'LANE', 'LEAN', 'LIE', 'LIEN', 'LINE', 'LIVE', 'NAIL', 'NAVE', 'VAIN', 'VALE', 'VAN', 'VANE', 'VEAL', 'VIA'},
	},
	-- Level 20
	{
		letters = {'A', 'I', 'R', 'E', 'D', 'M'},
		grid = {
			"....A....",
			"....I...A",
			"....R...I",
			"....E.A.M",
			"...ADMIRE",
			"...I..M.R",
			"...D..E..",
			"ARMED.D..",
			"...R.....",
		},
		words = {'ADMIRE', 'AIDER', 'AIMED', 'AIMER', 'AIRED', 'ARMED'},
		bonus = {'AID', 'AIR', 'ARE', 'ARM', 'DAM', 'DAME', 'DARE', 'DIE', 'DIM', 'EAR', 'MAD', 'RAM', 'RED', 'RID', 'RIM'},
	},
	-- Level 21
	{
		letters = {'A', 'I', 'R', 'E', 'D', 'W'},
		grid = {
			"...W...",
			"...I...",
			".D.D..R",
			"AIRED.E",
			".R..R.A",
			".E.RAID",
			"....W..",
		},
		words = {'AIRED', 'DIRE', 'DRAW', 'RAID', 'READ', 'WIDE'},
		bonus = {'AID', 'AIR', 'ARE', 'DARE', 'DEAR', 'DEW', 'DIE', 'DREW', 'EAR', 'RAW', 'RED', 'RID', 'WAD', 'WAR', 'WED'},
	},
	-- Level 22
	{
		letters = {'S', 'T', 'A', 'R', 'P', 'E'},
		grid = {
			".STAR...",
			"....A...",
			".PEST...",
			".A..STEP",
			".T......",
			"PETS....",
		},
		words = {'PATE', 'PEST', 'PETS', 'RATS', 'STAR', 'STEP'},
		bonus = {'APE', 'ARE', 'ART', 'EAR', 'EAT', 'PAR', 'PAT', 'PEA', 'PET', 'RAP', 'RAT', 'SAP', 'SAT', 'SEA', 'SET'},
	},
	-- Level 23
	{
		letters = {'M', 'E', 'E', 'T', 'S', 'A'},
		grid = {
			".MEET..",
			".E.....",
			".T.S...",
			"SATE...",
			"E..A...",
			"E..TEAS",
			"M......",
		},
		words = {'MEET', 'META', 'SATE', 'SEAT', 'SEEM', 'TEAS'},
		bonus = {'EASE', 'EAST', 'EAT', 'EATS', 'MAST', 'MAT', 'MATE', 'MATS', 'MEAT', 'MET', 'SAT', 'SEA', 'SEE', 'SET', 'TEA'},
	},
	-- Level 24
	{
		letters = {'P', 'E', 'A', 'T', 'S', 'V'},
		grid = {
			"..S..",
			"..A.S",
			"..V.A",
			".PEAT",
			".A..E",
			".T...",
			"PEST.",
			"...A.",
			"...P.",
			"...E.",
		},
		words = {'PATE', 'PEAT', 'PEST', 'SATE', 'SAVE', 'TAPE'},
		bonus = {'APE', 'EAST', 'EAT', 'EATS', 'PAT', 'PEA', 'PET', 'SAP', 'SAT', 'SEA', 'SET', 'TAP', 'TEA', 'VAT', 'VET'},
	},
	-- Level 25
	{
		letters = {'A', 'I', 'R', 'E', 'D', 'M'},
		grid = {
			".......A.",
			".......R.",
			".......M.",
			"....AIDER",
			"AIRED..D.",
			"....M....",
			"...AIMED.",
			"....R....",
			".AIMER...",
		},
		words = {'ADMIRE', 'AIDER', 'AIMED', 'AIMER', 'AIRED', 'ARMED'},
		bonus = {'AID', 'AIR', 'ARE', 'ARM', 'DAM', 'DAME', 'DARE', 'DIE', 'DIM', 'EAR', 'MAD', 'RAM', 'RED', 'RID', 'RIM'},
	},
	-- Level 26
	{
		letters = {'V', 'A', 'S', 'T', 'R', 'E'},
		grid = {
			"..VATS.",
			"..A....",
			"..S....",
			"ARTS...",
			".E.TARE",
			".V.A...",
			".S.R...",
		},
		words = {'ARTS', 'REVS', 'STAR', 'TARE', 'VAST', 'VATS'},
		bonus = {'ARE', 'ART', 'EAR', 'EARS', 'EAST', 'EAT', 'EATS', 'RAT', 'SAT', 'SEA', 'SET', 'TAR', 'TEA', 'VAT', 'VET'},
	},
	-- Level 27
	{
		letters = {'O', 'V', 'E', 'R', 'P', 'S'},
		grid = {
			"......P",
			"......O",
			"...ORES",
			"...V..E",
			"...E...",
			".PORE..",
			".R.....",
			"ROVE...",
			".S.....",
		},
		words = {'ORES', 'OVER', 'PORE', 'POSE', 'PROS', 'ROVE'},
		bonus = {'ORE', 'PRO', 'REPS', 'REVS', 'ROPE', 'ROSE', 'SORE'},
	},
	-- Level 28
	{
		letters = {'A', 'R', 'M', 'E', 'D', 'I'},
		grid = {
			".......A.",
			".......R.",
			".......M.",
			"....AIDER",
			"AIRED..D.",
			"....M....",
			"...AIMED.",
			"....R....",
			".AIMER...",
		},
		words = {'ADMIRE', 'AIDER', 'AIMED', 'AIMER', 'AIRED', 'ARMED'},
		bonus = {'AID', 'AIR', 'ARE', 'ARM', 'DAM', 'DAME', 'DARE', 'DIE', 'DIM', 'EAR', 'MAD', 'RAM', 'RED', 'RID', 'RIM'},
	},
	-- Level 29
	{
		letters = {'A', 'N', 'G', 'E', 'R', 'T'},
		grid = {
			".....N.",
			"..ANGER",
			"..N..A.",
			"RATE.T.",
			"E.E....",
			"N......",
			"TERN...",
		},
		words = {'ANGER', 'ANTE', 'NEAT', 'RATE', 'RENT', 'TERN'},
		bonus = {'AGE', 'ANT', 'ARE', 'ART', 'EAR', 'EAT', 'GET', 'NET', 'RAG', 'RAN', 'RAT', 'TAG', 'TAN', 'TAR', 'TEA'},
	},
	-- Level 30
	{
		letters = {'A', 'I', 'M', 'E', 'R', 'D'},
		grid = {
			"....A....",
			"....I...A",
			"....R...I",
			"....E.A.M",
			"...ADMIRE",
			"...I..M.R",
			"...D..E..",
			"ARMED.D..",
			"...R.....",
		},
		words = {'ADMIRE', 'AIDER', 'AIMED', 'AIMER', 'AIRED', 'ARMED'},
		bonus = {'AID', 'AIR', 'ARE', 'ARM', 'DAM', 'DAME', 'DARE', 'DIE', 'DIM', 'EAR', 'MAD', 'RAM', 'RED', 'RID', 'RIM'},
	},
	-- Level 31
	{
		letters = {'A', 'F', 'T', 'E', 'R', 'M'},
		grid = {
			"..TRAM",
			".F...A",
			".AFTER",
			".T.A.T",
			"TEAM..",
			"...E..",
		},
		words = {'AFTER', 'FATE', 'MART', 'TAME', 'TEAM', 'TRAM'},
		bonus = {'ARE', 'ARM', 'ART', 'EAR', 'EAT', 'FAME', 'FAR', 'FARE', 'FAT', 'MAT', 'MET', 'RAM', 'RAT', 'TAR', 'TEA'},
	},
	-- Level 32
	{
		letters = {'T', 'O', 'N', 'S', 'I', 'L'},
		grid = {
			"TONS...",
			"I......",
			"N..SILO",
			"SOIL.O.",
			"...O.I.",
			"SNIT.N.",
		},
		words = {'LOIN', 'SILO', 'SLOT', 'SNIT', 'SOIL', 'TINS', 'TONS'},
		bonus = {'INTO', 'IONS', 'ITS', 'LINT', 'LION', 'LIST', 'LIT', 'LOT', 'NIT', 'NOT', 'OIL', 'SIN', 'SIT', 'SON', 'TON'},
	},
	-- Level 33
	{
		letters = {'A', 'G', 'R', 'E', 'E', 'D'},
		grid = {
			"GRAD..D...",
			"...AGREE..",
			"GEAR..A...",
			"...E..RAGE",
		},
		words = {'AGREE', 'DARE', 'DEAR', 'GEAR', 'GRAD', 'RAGE'},
		bonus = {'AGE', 'AGED', 'ARE', 'DEER', 'DRAG', 'EAR', 'EDGE', 'RAG', 'READ', 'RED', 'REED'},
	},
	-- Level 34
	{
		letters = {'A', 'C', 'H', 'E', 'D', 'R'},
		grid = {
			".......H",
			".......A",
			"...C.C.R",
			"...ACHED",
			".H.R.A..",
			"HEAD.R..",
			".R......",
			".D......",
		},
		words = {'ACHED', 'CARD', 'CHAR', 'HARD', 'HEAD', 'HERD'},
		bonus = {'ACE', 'ACHE', 'ACRE', 'ARE', 'CAR', 'CARE', 'DARE', 'DEAR', 'EACH', 'EAR', 'HAD', 'HARE', 'HEAR', 'HER', 'RED'},
	},
	-- Level 35
	{
		letters = {'A', 'R', 'M', 'E', 'D', 'I'},
		grid = {
			"....A....",
			"....I...A",
			"....R...I",
			"....E.A.M",
			"...ADMIRE",
			"...I..M.R",
			"...D..E..",
			"ARMED.D..",
			"...R.....",
		},
		words = {'ADMIRE', 'AIDER', 'AIMED', 'AIMER', 'AIRED', 'ARMED'},
		bonus = {'AID', 'AIR', 'ARE', 'ARM', 'DAM', 'DAME', 'DARE', 'DIE', 'DIM', 'EAR', 'MAD', 'RAM', 'RED', 'RID', 'RIM'},
	},
	-- Level 36
	{
		letters = {'S', 'T', 'A', 'R', 'E', 'U'},
		grid = {
			"STAR.....",
			"...ARTS..",
			"...T..E..",
			"SURE..A..",
			".....TRUE",
		},
		words = {'ARTS', 'RATE', 'SEAR', 'STAR', 'SURE', 'TRUE'},
		bonus = {'ARE', 'ART', 'EAR', 'EARS', 'EAST', 'EAT', 'EATS', 'RAT', 'RUT', 'SAT', 'SEA', 'SET', 'TAR', 'TEA', 'USE'},
	},
	-- Level 37
	{
		letters = {'T', 'I', 'P', 'S', 'N', 'H'},
		grid = {
			"..TIPS.",
			".....P.",
			"...SNIT",
			"THIN.T.",
			"...I...",
			"..SPIN.",
		},
		words = {'SNIP', 'SNIT', 'SPIN', 'SPIT', 'THIN', 'TIPS'},
		bonus = {'HINT', 'HIP', 'HIPS', 'HIS', 'HIT', 'HITS', 'ITS', 'NIP', 'NIT', 'PIN', 'PIT', 'SIN', 'SIP', 'SIT', 'TIP'},
	},
	-- Level 38
	{
		letters = {'A', 'R', 'M', 'E', 'D', 'I'},
		grid = {
			".......A.",
			".......R.",
			".......M.",
			"....AIDER",
			"AIRED..D.",
			"....M....",
			"...AIMED.",
			"....R....",
			".AIMER...",
		},
		words = {'ADMIRE', 'AIDER', 'AIMED', 'AIMER', 'AIRED', 'ARMED'},
		bonus = {'AID', 'AIR', 'ARE', 'ARM', 'DAM', 'DAME', 'DARE', 'DIE', 'DIM', 'EAR', 'MAD', 'RAM', 'RED', 'RID', 'RIM'},
	},
	-- Level 39
	{
		letters = {'A', 'L', 'E', 'R', 'T', 'N'},
		grid = {
			"...ANTE",
			"...L...",
			"R.LENT.",
			"A..R.A.",
			"NEAT.R.",
			"T....E.",
		},
		words = {'ALERT', 'ANTE', 'LENT', 'NEAT', 'RANT', 'TARE'},
		bonus = {'ANT', 'ARE', 'ART', 'EAR', 'EARL', 'EARN', 'EAT', 'LET', 'NET', 'RAN', 'RAT', 'TAN', 'TAR', 'TEA', 'TEN'},
	},
	-- Level 40
	{
		letters = {'A', 'I', 'M', 'E', 'D', 'R'},
		grid = {
			".......A.",
			".......R.",
			".......M.",
			"....AIDER",
			"AIRED..D.",
			"....M....",
			"...AIMED.",
			"....R....",
			".AIMER...",
		},
		words = {'ADMIRE', 'AIDER', 'AIMED', 'AIMER', 'AIRED', 'ARMED'},
		bonus = {'AID', 'AIR', 'ARE', 'ARM', 'DAM', 'DAME', 'DARE', 'DIE', 'DIM', 'EAR', 'MAD', 'RAM', 'RED', 'RID', 'RIM'},
	},
	-- Level 41
	{
		letters = {'A', 'I', 'D', 'E', 'R', 'L'},
		grid = {
			"......LARD",
			".......I..",
			"...AIDER..",
			"...I.I.E..",
			"...L.A.D..",
			"...E.L....",
			"RAID......",
		},
		words = {'AIDER', 'AILED', 'AIRED', 'DIAL', 'LARD', 'RAID'},
		bonus = {'AID', 'AIR', 'ARE', 'DALE', 'DARE', 'DEAL', 'DEAR', 'DIE', 'EAR', 'LAD', 'LED', 'LID', 'LIE', 'RED', 'RID'},
	},
	-- Level 42
	{
		letters = {'G', 'E', 'T', 'S', 'N', 'A'},
		grid = {
			".....TANG",
			".......E.",
			"...N...S.",
			"...ANGST.",
			"...G.E...",
			"TANS.TAGS",
			".....S...",
		},
		words = {'ANGST', 'GETS', 'NAGS', 'NEST', 'TAGS', 'TANG', 'TANS'},
		bonus = {'AGE', 'AGES', 'ANT', 'EAT', 'GAS', 'GET', 'NET', 'SAG', 'SAT', 'SEA', 'SET', 'TAG', 'TAN', 'TEA', 'TEN'},
	},
	-- Level 43
	{
		letters = {'V', 'E', 'I', 'L', 'S', 'A'},
		grid = {
			".....S..",
			"..VISA..",
			".....L..",
			".AISLE..",
			".L..I...",
			".I..VISE",
			".V..E...",
			"VEIL....",
		},
		words = {'AISLE', 'ALIVE', 'LIVE', 'SALE', 'VEIL', 'VISA', 'VISE'},
		bonus = {'EVIL', 'LIE', 'LIES', 'SAIL', 'SAVE', 'SEA', 'SEAL', 'VALE', 'VASE', 'VEAL', 'VIA', 'VIAL', 'VILE'},
	},
	-- Level 44
	{
		letters = {'A', 'I', 'R', 'E', 'D', 'L'},
		grid = {
			".REAL",
			"....I",
			"....E",
			"AIRED",
			"I....",
			"LAIR.",
			"E....",
			"DIRE.",
		},
		words = {'AILED', 'AIRED', 'DIRE', 'LAIR', 'LIED', 'REAL'},
		bonus = {'AID', 'AIR', 'ARE', 'DALE', 'DARE', 'DEAL', 'DEAR', 'DIE', 'EAR', 'LAD', 'LED', 'LID', 'LIE', 'RED', 'RID'},
	},
	-- Level 45
	{
		letters = {'A', 'I', 'D', 'E', 'R', 'M'},
		grid = {
			"....A....",
			"....I...A",
			"....R...I",
			"....E.A.M",
			"...ADMIRE",
			"...I..M.R",
			"...D..E..",
			"ARMED.D..",
			"...R.....",
		},
		words = {'ADMIRE', 'AIDER', 'AIMED', 'AIMER', 'AIRED', 'ARMED'},
		bonus = {'AID', 'AIR', 'ARE', 'ARM', 'DAM', 'DAME', 'DARE', 'DIE', 'DIM', 'EAR', 'MAD', 'RAM', 'RED', 'RID', 'RIM'},
	},
	-- Level 46
	{
		letters = {'P', 'E', 'A', 'L', 'S', 'T'},
		grid = {
			".S.PEAL",
			".E....E",
			".A.LAPS",
			"PLEA..T",
			"...S...",
			"SALT...",
		},
		words = {'LAPS', 'LAST', 'LEST', 'PEAL', 'PLEA', 'SALT', 'SEAL'},
		bonus = {'APE', 'EAST', 'EAT', 'LAP', 'LET', 'PAL', 'PAT', 'PEA', 'PET', 'SAP', 'SAT', 'SEA', 'SET', 'TAP', 'TEA'},
	},
	-- Level 47
	{
		letters = {'D', 'A', 'R', 'E', 'D', 'I'},
		grid = {
			"..AIDED..",
			"..D...A..",
			"AIDER.R..",
			"..E..DEAR",
			"AIRED....",
		},
		words = {'ADDER', 'AIDED', 'AIDER', 'AIRED', 'DARE', 'DEAR'},
		bonus = {'ADD', 'AID', 'AIR', 'ARE', 'DAD', 'DEAD', 'DID', 'DIE', 'DIED', 'DIRE', 'EAR', 'IDEA', 'RAID', 'RED', 'RID'},
	},
	-- Level 48
	{
		letters = {'A', 'I', 'M', 'E', 'R', 'D'},
		grid = {
			".......A.",
			".......R.",
			".......M.",
			"....AIDER",
			"AIRED..D.",
			"....M....",
			"...AIMED.",
			"....R....",
			".AIMER...",
		},
		words = {'ADMIRE', 'AIDER', 'AIMED', 'AIMER', 'AIRED', 'ARMED'},
		bonus = {'AID', 'AIR', 'ARE', 'ARM', 'DAM', 'DAME', 'DARE', 'DIE', 'DIM', 'EAR', 'MAD', 'RAM', 'RED', 'RID', 'RIM'},
	},
	-- Level 49
	{
		letters = {'A', 'C', 'T', 'O', 'R', 'S'},
		grid = {
			"...ACTOR",
			"...C....",
			"SORT....",
			"...OATS.",
			"SOAR....",
			"...SCAT.",
		},
		words = {'ACTOR', 'ACTORS', 'OATS', 'SCAT', 'SOAR', 'SORT'},
		bonus = {'ACT', 'ART', 'ARTS', 'CAR', 'CARS', 'CART', 'CAST', 'CAT', 'CATS', 'COAT', 'OAR', 'OAT', 'RAT', 'SAT', 'TAR'},
	},
	-- Level 50
	{
		letters = {'A', 'R', 'M', 'E', 'D', 'I'},
		grid = {
			"....A....",
			"....I...A",
			"....R...I",
			"....E.A.M",
			"...ADMIRE",
			"...I..M.R",
			"...D..E..",
			"ARMED.D..",
			"...R.....",
		},
		words = {'ADMIRE', 'AIDER', 'AIMED', 'AIMER', 'AIRED', 'ARMED'},
		bonus = {'AID', 'AIR', 'ARE', 'ARM', 'DAM', 'DAME', 'DARE', 'DIE', 'DIM', 'EAR', 'MAD', 'RAM', 'RED', 'RID', 'RIM'},
	},
	}
}
