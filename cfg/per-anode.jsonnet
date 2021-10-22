// Per-anode functions

local wc = import "wirecell.jsonnet";
local pg = import "pgraph.jsonnet";

local tz = import "toyzero.jsonnet";
local dnnroi = import "dnnroi.jsonnet";

function (anode, det)
{
    anode: anode,
    det: det,
    apaid: anode.data.ident,
    channel_range: det.channel_range($.apaid),

    sim_fr: tz.field_response(det.sim.response),
    sp_fr: tz.field_response(det.sp.response),

    er: tz.elec_response(det.params.elec.shaping,
                         det.params.elec.gain,
                         det.params.elec.postgain,
                         det.params.daq.nticks,
                         det.params.daq.tick),
    rc: tz.rc_response(1.0*wc.ms,
                       det.params.daq.nticks,
                       det.params.daq.tick),
    sim_pirs: tz.pirs($.sim_fr, [$.er], [$.rc]),
    sp_pirs: tz.pirs($.sp_fr, [$.er], [$.rc]),

    sim(random) :: tz.sim(anode, 
                          $.sim_pirs,
                          det.params.daq,
                          det.params.adc,
                          det.params.lar,
                          det.sim.noise,
                          'adc',
                          random),

    dense_bounds : {
        chbeg: $.channel_range[0][0],
        chend: $.channel_range[2][1],
        tbbeg: 0,
        tbend: det.params.daq.nticks
    },

    frame_tap(tag, filename, digitize=false) ::
        pg.fan.tap('FrameFanout', 
                   tz.io.frame_sink(tag,
                                    filename, 
                                    tags=[tag],
                                    digitize=digitize,
                                    dense=$.dense_bounds),
                   tag),


    local chndb_perfect =
        det.sp.chndb.perfect(anode, $.sp_fr,
                             det.params.daq.nticks,
                             det.params.daq.tick),

    nf : tz.nf(anode, $.sp_fr, chndb_perfect,
               det.params.daq.nticks, det.params.daq.tick),


    sp(dnnroi_prep=false) ::
        local override = if dnnroi_prep then {
            sparse: true,
            use_roi_debug_mode: true,
            use_multi_plane_protection: true,
            process_planes: [0, 1, 2]
        } else {};
        tz.sp(anode, $.sp_fr, $.er, det.sp.filters,
              tz.adcpermv(det.params.adc),
              override=override),
    
    dnnsp(ts) :: dnnroi(anode, ts, $.channel_range),

}
