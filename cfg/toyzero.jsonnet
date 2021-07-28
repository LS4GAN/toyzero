local wc = import "wirecell.jsonnet";
local pg = import "pgraph.jsonnet";
local ut = import "utils.jsonnet";

// define general object for toyzero

{

    // return a "wireobj"
    wire_file(filename) : {
        type:"WireSchemaFile",
        data: {filename: filename}
    },

    anodes(wireobj, volumes) : [ {
        type: "AnodePlane",
        name: "AnodePlane%d" % vol.wires,
        data: {
            ident: vol.wires,
            wire_schema: wc.tn(wireobj),
            faces: vol.faces,
        },
        uses: [wireobj]
    } for vol in volumes],


    field_response(filename) :: {
        type: "FieldResponse",
        name: filename,
        data: { filename: filename }
    },

    elec_response(shaping, gain, postgain, nticks, tick=0.5*wc.us) :: {
        type: "ColdElecResponse",
        data: {
            shaping: shaping,
            gain: gain,
            postgain: postgain,
            nticks: nticks,
            tick: tick,
        },            
    },

    rc_response(width, nticks, tick=0.5*wc.us) :: {
        type: "RCResponse",
        data: {
            width: width,
            nticks: nticks,
            tick: tick,
        }
    },
    
    // Return "PlaneImpactResponse" objects.
    // fr is field_response object.
    // srs is list of short response objects, eg elec_resp
    // lrs is list of long response objects, eg rc_response
    pirs(fr, srs, lrs): {
        ret: [ {
            type: "PlaneImpactResponse",
            name : "PIRplane%d" % plane,
            data : {
                plane: plane,
                field_response: wc.tn(fr),
                short_responses: [wc.tn(r) for r in srs],
                // this needs to be big enough for convolving FR*CE
                overall_short_padding: 200*wc.us,
                long_responses: [wc.tn(r) for r in lrs],
                // this needs to be big enough to convolve RC
                long_padding: 1.5*wc.ms,
            },
            uses: [fr] + srs + lrs,
        } for plane in [0,1,2]],
    }.ret,

    adcpermv(adc) :: 
        ((1 << adc.resolution)-1) / (adc.fullscale[1]-adc.fullscale[0]),

    responses(frfile, elec, daq, width=1.0*wc.ms) :: {

        fr: $.field_response(frfile),
        er: $.elec_response(elec.shaping, elec.gain, elec.postgain,
                            daq.nticks, daq.tick),
        rc: $.rc_response(width, daq.nticks, daq.tick),
        pirs: $.pirs(self.fr, [self.er], [self.rc])
    },


    default_seeds: [0, 1, 2, 3, 4],
    random(seeds = $.default_seeds) : {
        type: "Random",
        data: {
            generator: "default",
            seeds: seeds,
        }
    },


    /// Make a drifter for all volumes
    drifter(vols, lar, rnd=$.random(), time_offset=0, fluctuate=true) : pg.pnode({
        local xregions = wc.unique_list(std.flattenArrays([v.faces for v in vols])),
        
        type: "Drifter",
        data: lar {
            rng: wc.tn(rnd),
            xregions: xregions,
            time_offset: time_offset,
            fluctuate: fluctuate,
        },
    }, nin=1, nout=1, uses=[rnd]),

    bagger(daq) : pg.pnode({
        type:'DepoBagger',
        data: {
            gate: [0, daq.nticks*daq.tick],
        },
    }, nin=1, nout=1),
    

    // A per anode configure node for simulating noise.
    noisesim(anode, noisef, daq, chstat=null, rnd=$.random()) : {
        local apaid = anode.data.ident,
        
        local noise_model = {
            type: "EmpiricalNoiseModel",
            name: "emperical-noise-model-%d" % apaid,
            data: {
                anode: wc.tn(anode),
                chanstat: if std.type(chstat) == "null" then "" else wc.tn(chstat),
                spectra_file: noisef,
                nsamples: daq.nticks,
                period: daq.tick,
                wire_length_scale: 1.0*wc.cm, // optimization binning
            },
            uses: [anode] + if std.type(chstat) == "null" then [] else [chstat],
        },
        ret: pg.pnode({
            type: "AddNoise",
            name: "addnoise-" + noise_model.name,
            data: {
                rng: wc.tn(rnd),
                model: wc.tn(noise_model),
                nsamples: daq.nticks,
                replacement_percentage: 0.02, // random optimization
            }}, nin=1, nout=1, uses=[rnd, noise_model]),
    }.ret,

    digisim(anode, adc) :: {
        local apaid = anode.data.ident,
        ret: pg.pnode({
            type: "Digitizer",
            name: 'Digitizer%d' % apaid,
            data : adc {
                anode: wc.tn(anode),
                frame_tag: "orig%d"%apaid,
            }
        }, nin=1, nout=1, uses=[anode]),
    }.ret,

    sigsim(anode, pirs, daq, lar, rnd=$.random()) : {

        local apaid = anode.data.ident,

        local ductor = pg.pnode({
            type:'DepoTransform',
            name:'DepoTransform%d' % apaid,
            data: {
                rng: wc.tn(rnd),
                anode: wc.tn(anode),
                pirs: [wc.tn(p) for p in pirs],
                fluctuate: true,
                drift_speed: lar.drift_speed,
                first_frame_number: 0,
                readout_time: daq.nticks*daq.tick, 
                start_time: 0,
                tick: daq.tick,
                nsigma: 3,
            },
        }, nin=1, nout=1, uses=pirs + [anode, rnd]),

        local reframer = pg.pnode({
            type: 'Reframer',
            name: 'Reframer%d' % apaid,
            data: {
                anode: wc.tn(anode),
                tags: [],
                fill: 0.0,
                tbin: 0,
                toffset: 0,
                nticks: daq.nticks,
            },
        }, nin=1, nout=1),

        ret: pg.pipeline([ductor, reframer]),
    }.ret,

    // A kitchen sink pipeline of nodes to simulate one APA.
    //
    // The daq, adc, lar likely comes from params.
    //
    // Fullest chain is sig + noise -> adc
    //
    // If no lar or pirs is given, then no signal.
    // If no noisef given, then no noise.
    // If no adc given, then no digitizer
    // The tier can be 'adc' or something else if no digitizer.
    sim(anode, pirs, daq, adc, lar, noisef=null, tier='adc', rnd=$.random()) : {

        local apaid = anode.data.ident,

        local beg = if std.type(lar) == "null" || std.type(pirs) == "null" then [] else [
            $.sigsim(anode, pirs, daq, lar, rnd)],

        local mid = if std.type(noisef) == "null" then [] else [
            $.noisesim(anode, noisef, daq, rnd=rnd)],

        local end = if tier == 'adc' then [$.digisim(anode, adc)] else [],

        pipeline: pg.pipeline(beg + mid + end),
    }.pipeline,

    local plugins = [
        "WireCellSio", "WireCellAux",
        "WireCellGen", "WireCellSigProc",
        "WireCellApps", "WireCellPgraph", "WireCellTbb"],
    

    main(graph, app) :: {
        local appcfg = {
            type: app,
            data: {
                edges: pg.edges(graph)
            },
        },
        local cmdline = {
            type: "wire-cell",
            data: {
                plugins: plugins,
                apps: [appcfg.type]
            }
        },
        seq: [cmdline] + pg.uses(graph) + [appcfg],
    }.seq
}
