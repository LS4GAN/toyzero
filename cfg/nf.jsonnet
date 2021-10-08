// Produce a noise filter component for an anode

// This can be arbitrarily hairy and probably best to make a new file
// if substantial changes are needed.

local wc = import "wirecell.jsonnet";
local pg = import "pgraph.jsonnet";

function(anode, fieldresp, chndb, nsamples, tick=0.5*wc.us, rms_cuts=[]) {
    local apaid = anode.data.ident,

    local single = {
        type: 'pdOneChannelNoise',
        name: '%d'%apaid,
        data: {
            noisedb: wc.tn(chndb),
            anode: wc.tn(anode),
            resmp: [
            ],
        },
    },

    // In principle there may be multiple filters of each of each
    // type.  Define them above and collect them by type here.
    local filters = {
        channel: [ single, ],
        group: [ ],
        status: [ ],
    },

    local obnf = pg.pnode({

        type: 'OmnibusNoiseFilter',
        name: '%d'%apaid,
        data: {

            // Nonzero forces the number of ticks in the waveform
            nticks: 0,

            // channel bin ranges are ignored
            // only when the channelmask is merged to `bad`
            maskmap: {sticky: "bad", ledge: "bad", noisy: "bad"},
            channel_filters: [wc.tn(f) for f in filters.channel],
            grouped_filters: [wc.tn(f) for f in filters.group],
            channel_status_filters: [wc.tn(f) for f in filters.status],
            noisedb: wc.tn(chndb),
            intraces: 'orig%d' % apaid,  // frame tag get all traces
            outtraces: 'raw%d' % apaid,
        },
    }, uses=[chndb, anode]+filters.channel+filters.group+filters.status, nin=1, nout=1),
    
    res: obnf

}.res

