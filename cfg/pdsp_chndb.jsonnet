// This defines channel noise databases for noise filtering for pdsp.

local wc = import "wirecell.jsonnet";

{
    // The "perfect noise" database is one that is free of any
    // "special" considerations such as per channel variability.  The
    // "official" perfect chndb depends on the official "chndb-base"
    // and that seems to be adulterated with specific settings.  We
    // try to start fresh here.
    perfect(anode, fr, nsamples, tick=0.5*wc.us) :: {
        local apaid = anode.data.ident,
        type:'OmniChannelNoiseDB',
        name: std.toString(apaid),
        uses: [anode, fr],
        data: {
            anode: wc.tn(anode),
            field_response: wc.tn(fr),
            tick: tick,
            nsamples: nsamples,

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
            
            // last match wins
            channel_info: [

                // First entry provides default channel info across ALL
                // channels.  Subsequent entries override a subset of channels
                // with a subset of these entries.  There's no reason to
                // repeat values found here in subsequent entries unless you
                // wish to change them.
                {
                    channels: std.range(apaid * 2560, (apaid + 1) * 2560 - 1),
                    nominal_baseline: 2350.0,  // adc count
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
                    /// this will use an average calculated from the anode
                    // response: { wpid: wc.WirePlaneId(wc.Ulayer) },
                    /// this uses hard-coded waveform.
                    response_offset: 120, // offset of the negative peak
                    pad_window_front: 20,
                    decon_limit: 0.02,
                    decon_limit1: 0.07,
                    roi_min_max_ratio: 3.0,
                },

                {
                    //channels: { wpid: wc.WirePlaneId(wc.Vlayer) },
	            channels: std.range(apaid * 2560 + 800, apaid * 2560 + 1600- 1),
                    /// this will use an average calculated from the anode
                    // response: { wpid: wc.WirePlaneId(wc.Vlayer) },
                    /// this uses hard-coded waveform.
                    decon_limit: 0.01,
                    decon_limit1: 0.08,
                    roi_min_max_ratio: 1.5,
                },

                {
                    //channels: { wpid: wc.WirePlaneId(wc.Wlayer) },
	            channels: std.range(apaid * 2560 + 1600, apaid * 2560 + 2560- 1),
                    nominal_baseline: 900.0,
                    decon_limit: 0.05,
                    decon_limit1: 0.08,
                },


            ],
        }                       // data
    }                           // perfect()
}
