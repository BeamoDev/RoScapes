-- WordDictionary.luau
-- Main word list used by the game.


local WordDictionary = {}

-- Word set for O(1) lookup
local WORD_SET = {}

-- All words from the GitHub dictionary (3-8 letters, common words)
local WORDS = {
	-- 3-letter words
	"aah", "abs", "ace", "act", "add", "ado", "ads", "aft", "age", "ago", "aha", "aid", "ail", "aim", "air", "ale", "all", "alt", "amp", "and", "ant", "any", "ape", "app", "apt", "arc", "are", "ark", "arm", "art", "ash", "ask", "asp", "ate", "awe", "axe", "aye",
	"bad", "bag", "bah", "bam", "ban", "bar", "bas", "bat", "bay", "bed", "bee", "beg", "bet", "bib", "bid", "big", "bin", "bio", "bit", "biz", "boa", "bob", "bod", "bog", "boo", "bop", "bot", "bow", "box", "boy", "bra", "bro", "bud", "bug", "bum", "bun", "bus", "but", "buy", "bye",
	"cab", "cad", "cam", "can", "cap", "car", "cat", "cay", "chi", "cob", "cod", "cog", "con", "coo", "cop", "cot", "cow", "coy", "cry", "cub", "cue", "cup", "cur", "cut",
	"dab", "dad", "dam", "day", "den", "dew", "did", "dig", "dim", "din", "dip", "doc", "doe", "dog", "don", "dot", "dow", "dry", "dub", "dud", "due", "dug", "duh", "dun", "duo", "dye",
	"ear", "eat", "ebb", "eek", "eel", "egg", "ego", "eke", "elf", "elk", "elm", "emu", "end", "era", "err", "eve", "ewe", "eye",
	"fab", "fad", "fan", "far", "fat", "fax", "fed", "fee", "fen", "few", "fig", "fin", "fir", "fit", "fix", "flu", "fly", "fob", "foe", "fog", "for", "fox", "fro", "fry", "fun", "fur",
	"gag", "gal", "gap", "gas", "gee", "gel", "gem", "get", "gig", "gin", "git", "gnu", "god", "goo", "got", "gum", "gun", "gut", "guy", "gym",
	"had", "hag", "hah", "ham", "has", "hat", "hay", "hem", "hen", "her", "hew", "hex", "hey", "hid", "him", "hip", "his", "hit", "hoe", "hog", "hop", "hot", "how", "hub", "hue", "hug", "huh", "hum", "hut",
	"ice", "icy", "ilk", "ill", "imp", "ink", "inn", "ion", "ire", "its", "ivy",
	"jab", "jag", "jam", "jar", "jaw", "jay", "jet", "jib", "jig", "job", "jog", "jot", "joy", "jug", "jus", "jut",
	"keg", "key", "kid", "kin", "kit", "koi",
	"lab", "lad", "lag", "lam", "lap", "lat", "law", "lax", "lay", "led", "leg", "let", "lid", "lie", "lip", "lit", "lob", "log", "lot", "low", "lox", "lug", "lye",
	"mad", "mag", "mam", "man", "map", "mar", "mat", "maw", "max", "may", "meg", "men", "met", "mid", "mil", "mix", "mob", "mom", "moo", "mop", "mow", "mud", "mug", "mum",
	"nab", "nag", "nan", "nap", "naw", "nay", "net", "new", "nil", "nip", "nit", "nix", "nod", "nor", "not", "now", "nub", "nun", "nut",
	"oak", "oar", "oat", "odd", "ode", "off", "oft", "ohm", "oil", "old", "one", "ooh", "ops", "opt", "orb", "ore", "our", "out", "ova", "owe", "owl", "own",
	"pad", "pal", "pan", "pap", "par", "pat", "paw", "pay", "pea", "peg", "pen", "pep", "per", "pet", "pew", "phi", "pic", "pie", "pig", "pin", "pit", "ply", "pod", "pop", "pot", "pow", "pox", "pro", "pry", "pub", "pug", "pun", "pup", "pus", "put",
	"rad", "rag", "ram", "ran", "rap", "rat", "raw", "ray", "red", "ref", "rem", "rep", "rib", "rid", "rig", "rim", "rip", "rob", "rod", "rot", "row", "rub", "rue", "rug", "rum", "run", "rut", "rye",
	"sac", "sad", "sag", "sap", "sat", "saw", "sax", "say", "sea", "see", "set", "sew", "sex", "she", "shy", "sim", "sin", "sip", "sir", "sis", "sit", "six", "ski", "sky", "sly", "sob", "sod", "son", "sop", "sow", "soy", "spa", "spy", "sub", "sue", "sum", "sun", "sup",
	"tab", "tad", "tag", "tan", "tap", "tar", "tau", "tax", "tea", "tee", "ten", "the", "thy", "tic", "tie", "til", "tin", "tip", "tis", "toe", "ton", "too", "top", "tot", "tow", "toy", "try", "tub", "tug", "tux", "two",
	"ugh", "umm", "ups", "urn", "use",
	"vac", "van", "vat", "vet", "via", "vie", "vow",
	"wad", "wag", "war", "was", "wax", "way", "web", "wed", "wee", "wet", "who", "why", "wig", "win", "wit", "wiz", "woe", "wok", "won", "woo", "wow", "wry",
	"xis",
	"yak", "yam", "yea", "yen", "yep", "yes", "yet", "yew", "yin", "yon", "you", "yum", "yup",
	"zag", "zap", "zig", "zip", "zit", "zoo",
	
	-- 4-letter words
	"able", "ably", "abut", "aced", "aces", "ache", "achy", "acid", "acme", "acne", "acre", "acts", "adds", "afar", "afro", "aged", "ages", "ahem", "ahoy", "aide", "aids", "ails", "aims", "airs", "airy", "ajar", "akin", "alas", "ales", "ally", "alms", "aloe", "also", "alto", "alum", "amen", "amid", "ammo", "amok", "amps", "anew", "ante", "anti", "ants", "apes", "apex", "apps", "arch", "arcs", "area", "arid", "arks", "arms", "army", "arts", "arty", "ashy", "asks", "atom", "atop", "aunt", "aura", "auto", "avid", "away", "awed", "awes", "awry", "axed", "axes", "axis", "axle",
	"babe", "baby", "back", "bade", "bail", "bait", "bake", "bald", "bale", "balk", "ball", "balm", "band", "bane", "bang", "bank", "bans", "barb", "bard", "bare", "bark", "barn", "bars", "base", "bash", "bask", "bass", "bath", "bats", "bawl", "bays", "bead", "beak", "beam", "bean", "bear", "beat", "beau", "beck", "beds", "beef", "been", "beep", "beer", "bees", "beet", "begs", "bell", "belt", "bend", "bent", "berm", "best", "beta", "bets", "bevy", "bias", "bibs", "bide", "bids", "bike", "bile", "bill", "bind", "bins", "bios", "bird", "bite", "bits", "blah", "blam", "bled", "blew", "blip", "blob", "blog", "blot", "blow", "blue", "blur", "boar", "boat", "bobs", "bode", "body", "bogs", "boil", "bola", "bold", "boll", "bolo", "bolt", "bomb", "bond", "bone", "bong", "bonk", "bony", "book", "boom", "boon", "boos", "boot", "bore", "born", "boss", "both", "bots", "bout", "bowl", "bows", "boys", "bozo", "brag", "bran", "bras", "brat", "bred", "brew", "brie", "brig", "brim", "brow", "buck", "buds", "buff", "bugs", "bulb", "bulk", "bull", "bump", "bums", "bunk", "buns", "bunt", "buoy", "burg", "burn", "burp", "burr", "bury", "bush", "bust", "busy", "buts", "butt", "buys", "buzz", "byte",
	"cabs", "cafe", "cage", "cake", "calf", "call", "calm", "came", "camo", "camp", "cams", "cane", "cans", "cape", "caps", "carb", "card", "care", "carp", "cars", "cart", "case", "cash", "cask", "cast", "cats", "cave", "cede", "cell", "cent", "chad", "chap", "char", "chat", "chef", "chew", "chic", "chin", "chip", "chop", "chow", "chub", "chug", "chum", "cite", "city", "clad", "clam", "clan", "clap", "claw", "clay", "clip", "clod", "clog", "clot", "club", "clue", "coal", "coat", "coax", "cobs", "coco", "coda", "code", "coed", "cogs", "coil", "coin", "coke", "cola", "cold", "colt", "coma", "comb", "come", "comp", "cone", "cons", "cook", "cool", "coop", "coos", "coot", "cope", "cops", "copy", "cord", "core", "cork", "corn", "cost", "cots", "coup", "cove", "cowl", "cows", "cozy", "crab", "cram", "crew", "crib", "croc", "crop", "crow", "crud", "cube", "cubs", "cued", "cues", "cuff", "cull", "cult", "cups", "curb", "curd", "cure", "curl", "curt", "cusp", "cuss", "cute", "cuts", "cyan", "cyst", "czar",
	"dabs", "dads", "daft", "dale", "dame", "damp", "dams", "dank", "dare", "dark", "darn", "dart", "dash", "data", "date", "dawn", "days", "daze", "dead", "deaf", "deal", "dean", "dear", "debt", "deck", "deed", "deem", "deep", "deer", "deft", "defy", "deli", "dell", "demo", "dens", "dent", "deny", "desk", "dewy", "dial", "dice", "died", "diet", "digs", "dike", "dill", "dime", "dims", "dine", "ding", "dink", "dint", "dips", "dire", "dirt", "disc", "dish", "disk", "diva", "dive", "dock", "docs", "doer", "does", "dogs", "dole", "doll", "dome", "done", "dons", "doom", "door", "dope", "dorm", "dose", "dote", "dots", "dour", "dove", "down", "doze", "drab", "drag", "dram", "draw", "drew", "drip", "drop", "drub", "drug", "drum", "dual", "dubs", "duck", "duct", "dude", "duds", "duel", "dues", "duet", "duke", "dull", "duly", "dump", "dune", "dung", "dunk", "dupe", "dusk", "dust", "duty", "dyed", "dyes",
	"each", "earl", "earn", "ears", "ease", "east", "easy", "eats", "ebbs", "echo", "eddy", "edge", "edgy", "edit", "eels", "eggs", "egos", "elms", "else", "emit", "ends", "envy", "eons", "epic", "eras", "errs", "etch", "euro", "even", "ever", "evil", "ewes", "exam", "exec", "exes", "exit", "expo", "eyed", "eyes",
	"face", "fact", "fade", "fads", "fail", "fair", "fake", "fall", "fame", "fang", "fans", "fare", "farm", "fast", "fate", "fats", "fawn", "faze", "fear", "feat", "feds", "feed", "feel", "fees", "feet", "fell", "felt", "fend", "fern", "fess", "feta", "fete", "feud", "fife", "figs", "file", "fill", "film", "find", "fine", "fins", "fire", "firm", "firs", "fish", "fist", "fits", "five", "fizz", "flab", "flag", "flak", "flan", "flap", "flat", "flaw", "flay", "flea", "fled", "flee", "flew", "flex", "flip", "flit", "flop", "flow", "flue", "flux", "foal", "foam", "foes", "foil", "fold", "folk", "fond", "font", "food", "fool", "foot", "fora", "ford", "fore", "fork", "form", "fort", "foul", "four", "fowl", "frat", "fray", "free", "fret", "frog", "from", "fuel", "full", "fund", "funk", "furs", "fury", "fuse", "fuss", "fuzz",
	"gaff", "gaga", "gags", "gain", "gait", "gala", "gale", "gall", "gals", "game", "gang", "gape", "garb", "gash", "gasp", "gate", "gave", "gawk", "gaze", "gear", "geek", "gees", "gels", "gems", "gene", "gent", "germ", "gets", "gift", "gigs", "gill", "gilt", "girl", "gist", "give", "glad", "glam", "glee", "glen", "glib", "glob", "glow", "glue", "glum", "glut", "gnat", "gnaw", "gnus", "goad", "goal", "goat", "gobs", "gods", "goes", "gogo", "gold", "golf", "gone", "gong", "good", "goof", "goon", "goop", "gore", "gory", "gosh", "goth", "gout", "gown", "grab", "grad", "gram", "gray", "grew", "grey", "grid", "grim", "grin", "grip", "grit", "grow", "grub", "gulf", "gull", "gulp", "gums", "gunk", "guns", "guru", "gush", "gust", "guts", "guys", "gyms",
	"hack", "haft", "hags", "haha", "hail", "hair", "hale", "half", "hall", "halo", "halt", "hams", "hand", "hang", "hard", "hare", "hark", "harm", "harp", "hart", "hash", "hate", "hats", "haul", "have", "hawk", "haze", "hazy", "head", "heal", "heap", "hear", "heat", "heed", "heel", "heft", "heir", "held", "hell", "helm", "help", "hemp", "hems", "hens", "herb", "herd", "here", "hero", "hers", "hewn", "hick", "hide", "high", "hike", "hill", "hilt", "hind", "hint", "hips", "hire", "hiss", "hits", "hive", "hoax", "hobo", "hock", "hoes", "hogs", "hold", "hole", "holy", "home", "hone", "honk", "hood", "hoof", "hook", "hoop", "hoot", "hope", "hops", "horn", "hose", "host", "hour", "howl", "hubs", "hues", "huff", "huge", "hugs", "hula", "hulk", "hull", "hump", "hums", "hung", "hunk", "hunt", "hurl", "hurt", "hush", "husk", "huts", "hymn", "hype",
	"iced", "ices", "icky", "icon", "idea", "idle", "idly", "idol", "iffy", "ills", "imps", "inch", "info", "inks", "inky", "inns", "into", "ions", "iota", "ires", "iris", "irks", "iron", "isle", "itch", "item",
	"jack", "jade", "jail", "jams", "jaws", "jazz", "jeer", "jerk", "jest", "jets", "jibe", "jigs", "jilt", "jinx", "jobs", "jock", "join", "joke", "jolt", "jots", "judo", "juke", "jump", "junk", "jury", "just", "juts",
	"kale", "keel", "keen", "keep", "kelp", "kept", "keys", "kick", "kids", "kill", "kilt", "kind", "king", "kiss", "kite", "kits", "knee", "knew", "knit", "knob", "knot", "know",
	"labs", "lace", "lack", "lacy", "lads", "lady", "lags", "laid", "lain", "lair", "lake", "lamb", "lame", "lamp", "land", "lane", "lank", "laps", "lard", "lark", "lash", "lass", "last", "late", "lats", "laud", "lava", "lawn", "laws", "lays", "lazy", "lead", "leaf", "leak", "lean", "leap", "leek", "leer", "left", "legs", "lend", "lens", "lent", "less", "lest", "lets", "levy", "lewd", "liar", "lice", "lick", "lids", "lied", "lien", "lies", "life", "lift", "like", "lilt", "lily", "limb", "lime", "limo", "limp", "line", "link", "lint", "lion", "lips", "lisp", "list", "lite", "live", "load", "loaf", "loam", "loan", "lobe", "lobs", "lock", "lode", "loft", "logo", "logs", "loin", "lone", "long", "look", "loom", "loon", "loop", "loot", "lope", "lops", "lord", "lore", "lose", "loss", "lost", "lots", "loud", "lout", "love", "lows", "lube", "luck", "luge", "lugs", "lull", "lump", "lung", "lure", "lurk", "lush", "lust", "lute", "lynx", "lyre",
	"mace", "made", "mage", "mags", "maid", "mail", "main", "make", "male", "mall", "malt", "mama", "mane", "many", "maps", "mare", "mark", "mart", "mash", "mask", "mass", "mast", "mate", "math", "mats", "maul", "maze", "mead", "meal", "mean", "meat", "meds", "meek", "meet", "mega", "megs", "meld", "melt", "memo", "mend", "menu", "meow", "mere", "mesa", "mesh", "mess", "mica", "mice", "mids", "mild", "mile", "milk", "mill", "mime", "mind", "mine", "mini", "mink", "mint", "mire", "miss", "mist", "mite", "mitt", "moan", "moat", "mobs", "mock", "mode", "mods", "mold", "mole", "molt", "moms", "monk", "mono", "mood", "moon", "moor", "moos", "moot", "mops", "more", "moss", "most", "mote", "moth", "move", "mown", "mows", "much", "muck", "muds", "mugs", "mule", "mull", "mums", "murk", "muse", "mush", "musk", "must", "mute", "mutt", "myth",
	"nags", "nail", "name", "nape", "naps", "nary", "nave", "navy", "nays", "near", "neat", "neck", "need", "neon", "nerd", "nest", "nets", "news", "next", "nice", "nick", "nigh", "nine", "nips", "nits", "node", "nods", "noel", "none", "nook", "noon", "nope", "norm", "nose", "nosy", "note", "noun", "nova", "nude", "nuke", "null", "numb", "nuns", "nuts",
	"oaks", "oars", "oath", "oats", "obey", "oboe", "odds", "odor", "ogle", "ogre", "oils", "oily", "okra", "omen", "omit", "once", "ones", "only", "onto", "onus", "onyx", "oops", "ooze", "opal", "open", "opts", "opus", "oral", "orbs", "orca", "ores", "ouch", "ours", "oust", "outs", "oval", "oven", "over", "owed", "owes", "owls", "owns", "oxen",
	"pace", "pack", "pact", "pads", "page", "paid", "pail", "pain", "pair", "pale", "pall", "palm", "pals", "pane", "pang", "pans", "pant", "papa", "para", "pare", "park", "pars", "part", "pass", "past", "pate", "path", "pave", "pawn", "paws", "pays", "peak", "peal", "pear", "peas", "peat", "peck", "peek", "peel", "peep", "peer", "pegs", "pelt", "pens", "pent", "peon", "perk", "perm", "pert", "pest", "pets", "pews", "phew", "pick", "pics", "pier", "pies", "pigs", "pike", "pile", "pill", "pine", "ping", "pink", "pins", "pint", "pipe", "pita", "pits", "pity", "plan", "play", "plea", "pled", "plop", "plot", "plow", "ploy", "plug", "plum", "plus", "pods", "poem", "poet", "poke", "pole", "poll", "polo", "poly", "pomp", "pond", "pong", "pony", "poof", "pool", "poop", "poor", "pope", "pops", "pore", "pork", "port", "pose", "posh", "post", "pots", "pour", "pout", "pray", "prep", "prey", "prim", "prod", "prom", "prop", "pros", "prow", "pubs", "puck", "puff", "pull", "pulp", "puma", "pump", "punk", "puns", "punt", "puny", "pups", "pure", "purr", "push", "puss", "puts", "putt", "pyre",
	"quad", "quay", "quid", "quip", "quit", "quiz",
	"race", "rack", "racy", "raft", "rage", "rags", "raid", "rail", "rain", "rake", "ramp", "rams", "rang", "rank", "rant", "raps", "rapt", "rare", "rash", "rasp", "rate", "rats", "rave", "rays", "raze", "read", "real", "reap", "rear", "redo", "reds", "reed", "reef", "reek", "reel", "refs", "rein", "rely", "rend", "rent", "repo", "reps", "rest", "ribs", "rice", "rich", "ride", "rids", "rife", "riff", "rift", "rigs", "rile", "rims", "rind", "ring", "rink", "riot", "ripe", "rips", "rise", "risk", "rite", "road", "roam", "roan", "roar", "robe", "robs", "rock", "rode", "rods", "roil", "role", "roll", "romp", "roof", "rook", "room", "root", "rope", "rose", "rosy", "rote", "rots", "rout", "rove", "rows", "rubs", "ruby", "rude", "rugs", "ruin", "rule", "rump", "rune", "rung", "runs", "runt", "ruse", "rush", "rust", "ruts",
	"sack", "sacs", "safe", "saga", "sage", "sago", "sags", "said", "sail", "sake", "sale", "salt", "same", "sand", "sane", "sang", "sank", "sash", "sass", "save", "saws", "says", "scab", "scam", "scan", "scar", "scud", "scum", "seal", "seam", "sear", "seas", "seat", "sect", "seed", "seek", "seem", "seen", "seep", "seer", "sees", "self", "sell", "semi", "send", "sent", "sets", "sewn", "sews", "shag", "shah", "sham", "shed", "shin", "ship", "shoe", "shoo", "shop", "shot", "show", "shun", "shut", "sick", "side", "sift", "sigh", "sign", "silk", "sill", "silo", "silt", "sine", "sing", "sink", "sins", "sips", "sire", "sirs", "site", "sits", "size", "skew", "skid", "skim", "skin", "skip", "skis", "skit", "slab", "slam", "slap", "slat", "slaw", "slay", "sled", "slew", "slid", "slim", "slip", "slit", "slob", "slog", "slop", "slot", "slow", "slug", "slum", "slur", "smog", "smug", "smut", "snag", "snap", "snip", "snob", "snot", "snow", "snub", "snug", "soak", "soap", "soar", "sobs", "sock", "soda", "sofa", "soft", "soil", "sold", "sole", "solo", "some", "song", "sons", "soon", "soot", "sops", "sore", "sort", "soul", "soup", "sour", "spam", "span", "spar", "spas", "spat", "spec", "sped", "spew", "spin", "spit", "spot", "spry", "spud", "spun", "spur", "stab", "stag", "star", "stat", "stay", "stem", "step", "stew", "stir", "stop", "stow", "stub", "stud", "stun", "subs", "such", "suck", "suds", "sued", "sues", "suit", "sulk", "sumo", "sump", "sums", "sung", "sunk", "suns", "sure", "surf", "swab", "swag", "swam", "swan", "swap", "swat", "sway", "swig", "swim", "sync"
}

-- Build the word set for fast lookup
for _, word in ipairs(WORDS) do
	WORD_SET[word:upper()] = true
end

-- Function to check if a word is valid
function WordDictionary.IsValidWord(word)
	if not word or typeof(word) ~= "string" then
		return false
	end
	
	word = word:lower()
	return WORD_SET[word] == true
end

-- Function to get all valid words from a set of letters
function WordDictionary.FindAllWords(letters, maxLength)
	maxLength = maxLength or 8
	local results = {}
	local letterCount = {}
	
	-- Count available letters
	for _, letter in ipairs(letters) do
		letter = letter:lower()
		letterCount[letter] = (letterCount[letter] or 0) + 1
	end
	
	-- Helper to check if word can be formed
	local function canFormWord(word)
		local needed = {}
		for i = 1, #word do
			local c = word:sub(i, i)
			needed[c] = (needed[c] or 0) + 1
			if not letterCount[c] or needed[c] > letterCount[c] then
				return false
			end
		end
		return true
	end
	
	-- Check all words in dictionary
	for word, _ in pairs(WORD_SET) do
		if #word >= 2 and #word <= maxLength and canFormWord(word:lower()) then
			table.insert(results, word:upper())
		end
	end
	
	return results
end

return WordDictionary
