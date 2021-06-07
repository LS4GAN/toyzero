local wc = import "wirecell.jsonnet";
local pg = import "pgraph.jsonnet";


// define general object for toyzero

{
    protodune_params: import "pgrapher/experiment/pdsp/simparams.jsonnet",

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


    // Return "PlaneImpactResponse" objects.  daq and elec likely come
    // from params.
    pirs(respf, daq, elec): {

        local field_resp = {
            type: "FieldResponse",
            name: respf,
            data: {
                filename: respf
            }
        },
        
        local binning = { nticks: daq.nticks, tick: daq.tick },

        local rc_resp = {
            type: "RCResponse",
            data: binning {
                width: 1.0*wc.ms,
            }
        },

        local elec_resp = {
            type: "ColdElecResponse",
            data: binning {
                shaping: elec.shaping,
                gain: elec.gain,
                postgain: elec.postgain,
            },            
        },


        ret: [ {
            type: "PlaneImpactResponse",
            name : "PIRplane%d" % plane,
            data : {
                plane: plane,
                field_response: wc.tn(field_resp),
                short_responses: [wc.tn(elec_resp)],
                // this needs to be big enough for convolving FR*CE
                overall_short_padding: 200*wc.us,
                long_responses: [wc.tn(rc_resp)],
                // this needs to be big enough to convolve RC
                long_padding: 1.5*wc.ms,
            },
            uses: [field_resp, elec_resp, rc_resp],
        } for plane in [0,1,2]],

    }.ret,


    // A pipeline of nodes to simulate one APA.
    //
    // The vol, daq, adc, lar likely comes from params.
    // The noisef should be a file name.
    // fixme: probably should be broken up...
    apasim(anode, pirs, vol, daq, adc, lar, noisef=null, seeds=[0,1,2,3,4]) : {
        local random = {
            type: "Random",
            data: {
                generator: "default",
                seeds: seeds,
            }
        },

        local drifter = pg.pnode({
            local xregions = wc.unique_list(vol.faces),

            type: "Drifter",
            data: lar {
                rng: wc.tn(random),
                xregions: xregions,
                time_offset: 0.0,
                
                fluctuate: true, 
            },
        }, nin=1, nout=1, uses=[random]),

        local bagger = pg.pnode({
            type:'DepoBagger',
            data: {
                gate: [0, daq.nticks*daq.tick],
            },
        }, nin=1, nout=1),

        local ductor = pg.pnode({
            type:'DepoTransform',
            data: {
                rng: wc.tn(random),
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
        }, nin=1, nout=1, uses=pirs + [anode, random]),

        local reframer = pg.pnode({
            type: 'Reframer',
            data: {
                anode: wc.tn(anode),
                tags: [],
                fill: 0.0,
                tbin: 0,
                toffset: 0,
                nticks: daq.nticks,
            },
        }, nin=1, nout=1),

        local digitizer = pg.pnode({
            type: "Digitizer",
            data : adc {
                anode: wc.tn(anode),
                frame_tag: "orig%d"%anode.data.ident,
            }
        }, nin=1, nout=1, uses=[anode]),

        
        local csdb = null,

        local noise_model = {
            type: "EmpiricalNoiseModel",
            name: "empericalnoise-" + anode.name,
            data: {
                anode: wc.tn(anode),
                chanstat: if std.type(csdb) == "null" then "" else wc.tn(csdb),
                spectra_file: noisef,
                nsamples: daq.nticks,
                period: daq.tick,
                wire_length_scale: 1.0*wc.cm, // optimization binning
            },
            uses: [anode] + if std.type(csdb) == "null" then [] else [csdb],
        },
        local noise = pg.pnode({
            type: "AddNoise",
            name: "addnoise-" + noise_model.name,
            data: {
                rng: wc.tn(random),
                model: wc.tn(noise_model),
                nsamples: daq.nticks,
                replacement_percentage: 0.02, // random optimization
            }}, nin=1, nout=1, uses=[random, noise_model]),
        
        local beg = [drifter, bagger, ductor, reframer],

        local mid = if std.type(noisef) == "null" then [] else [noise],

        local end = [digitizer],

        pipeline: pg.pipeline(beg + mid + end),
    }.pipeline,

    local plugins = [
        "WireCellSio", "WireCellAux",
        "WireCellGen", "WireCellSigProc",
        "WireCellApps", "WireCellPgraph"],
    

    main(graph) :: {
        local app = {
            type: 'Pgrapher',
            data: {
                edges: pg.edges(graph)
            },
        },
        local cmdline = {
            type: "wire-cell",
            data: {
                plugins: plugins,
                apps: ["Pgrapher"],
            }
        },
        seq: [cmdline] + pg.uses(graph) + [app],
    }.seq
}
