return {
-- These are more like threshold min/max between tiers.  Not really true potencies.
    ['default'] = {
		['curaga'] = {85,160,640},
		['cure'] = {42,80,185,420},
        ['waltz'] = {80,140,300},
        ['waltzga'] = {80},
		['bluega'] = {190},
        ['blue'] = {115,200},
		['min_thresholds'] = {
            ['cure'] = {87,199,438,817},
            ['curaga'] = {172,363,675},
			['waltz'] = {155,321,556},
            ['waltzga'] = {155},
            ['blue'] = {221,600},
            ['bluega'] = {250},
        },
    },
	['BLU'] = {
		['bluega'] = {150,290},
        ['blue'] = {140,275,720},
		['min_thresholds'] = {
            ['blue'] = {288,600,725},
            ['bluega'] = {300,1014},
        },
	},
	['DNC'] = {
		['waltz'] = {210,415,745,1195,1800,2200},
        ['waltzga'] = {210,405},
		['min_thresholds'] = {
			['waltz'] = {441,778,1230,1846,2268},
            ['waltzga'] = {429,1038},
		},
	},
	['WHM'] = {
		['curaga'] = {205,375,595,990,1680,1900},
		['cure'] = {155,275,390,700,1190,1415},
		['min_thresholds'] = {
            ['cure'] = {307,430,756,1257,1491,1875},
            ['curaga'] = {414,633,1070,1755,2003},
        },
    },
    ['PLD'] = {
		['curaga'] = {190,325,500},
		['cure'] = {100,185,330,700},
		['min_thresholds'] = {
            ['cure'] = {201,369,732,1177},
            ['curaga'] = {298,519,962},
        },
		
    },
}
