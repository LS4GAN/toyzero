// Produce a noise filter component for an anode

// This can be arbitrarily hairy and probably best to make a new file
// if substantial changes are needed.

local wc = import "wirecell.jsonnet";
local pg = import "pgraph.jsonnet";

function(anode, fieldresp, nsamples, tick=0.5*wc.us, rms_cuts=[]) {
    local apaid = anode.data.ident,

    local chndb = {
        type: 'OmniChannelNoiseDB',
        name: 'ocndbperfect%d' % apaid,
        uses: [anode, fieldresp],
        data: {
            anode: wc.tn(anode),
            field_response: wc.tn(fieldresp),
            tick: tick,

            // This sets the number of frequency-domain bins used in the noise
            // filtering.  It is not necessarily true that the time-domain
            // waveforms have the same number of ticks.  This must be non-zero.
            nsamples: nsamples,

            // Group channels into their domains of coherency
            groups: [
                std.range(apaid * 2560 + u * 40, apaid * 2560 + (u + 1) * 40 - 1)
                for u in std.range(0, 19)
            ] + [
                std.range(apaid * 2560 + 800 + v * 40, apaid * 2560 + 800 + (v + 1) * 40 - 1)
                for v in std.range(0, 19)
            ] + [
                std.range(apaid * 2560 + 1600 + w * 48, apaid * 2560 + 1600 + (w + 1) * 48 - 1)
                for w in std.range(0, 19)
            ],


            // Overide defaults for specific channels.  If an info is
            // mentioned for a particular channel in multiple objects in this
            // list then last mention wins.
            channel_info: [
                // First entry provides default channel info across ALL
                // channels.  Subsequent entries override a subset of channels
                // with a subset of these entries.  There's no reason to
                // repeat values found here in subsequent entries unless you
                // wish to change them.
                {
                    channels: std.range(apaid * 2560, (apaid + 1) * 2560 - 1),
                    nominal_baseline: 2048.0,  // adc count
                    gain_correction: 1.0,  // unitless
                    response_offset: 0.0,  // ticks?
                    pad_window_front: 10,  // ticks?
                    pad_window_back: 10,  // ticks?
                    decon_limit: 0.02,
                    decon_limit1: 0.09,
                    adc_limit: 15,
                    roi_min_max_ratio: 0.8, // default 0.8
                    min_rms_cut: 1.0,  // units???
                    max_rms_cut: 30.0,  // units???

                    // parameter used to make "rcrc" spectrum
                    rcrc: 1.1 * wc.millisecond, // 1.1 for collection, 3.3 for induction
                    rc_layers: 1, // default 2

                    // parameters used to make "config" spectrum
                    reconfig: {},

                    // list to make "noise" spectrum mask
                    freqmasks: [],

                    // field response waveform to make "response" spectrum.
                    response: {},
                },
                {
                    //channels: { wpid: wc.WirePlaneId(wc.Ulayer) },
                    channels: std.range(apaid * 2560, apaid * 2560 + 800- 1),
                    response: { wpid: wc.WirePlaneId(wc.Ulayer) },
                    response_offset: 120, // offset of the negative peak
                    pad_window_front: 20,
                    decon_limit: 0.02,
                    decon_limit1: 0.07,
                    roi_min_max_ratio: 3.0,
                },
                {
                    //channels: { wpid: wc.WirePlaneId(wc.Vlayer) },
                    channels: std.range(apaid * 2560 + 800, apaid * 2560 + 1600- 1),
                    response: { wpid: wc.WirePlaneId(wc.Vlayer) },
                    response_offset: 124,
                    decon_limit: 0.01,
                    decon_limit1: 0.08,
                    roi_min_max_ratio: 1.5,
                },
                {
                    //channels: { wpid: wc.WirePlaneId(wc.Wlayer) },
                    channels: std.range(apaid * 2560 + 1600, apaid * 2560 + 2560- 1),
                    nominal_baseline: 400.0,
                    decon_limit: 0.05,
                    decon_limit1: 0.08,
                },
            ] + rms_cuts,
        },                      // data
    },                          // chndb

    local single = {
        type: 'pdOneChannelNoise',
        name: 'ocn%d'%apaid,
        data: {
            noisedb: wc.tn(chndb),
            anode: wc.tn(anode),
            resmp: [
                {channels: std.range(2128, 2175), sample_from: 5996},
                {channels: std.range(1520, 1559), sample_from: 5996},
                {channels: std.range( 440,  479), sample_from: 5996},
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
        name: 'nf%d'%apaid,
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

