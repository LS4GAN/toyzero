// This is a main wire-cell configuration file.
//
// It implements the chain:
//   (depos)->sim(signal,noise)->sigproc->(signals)
//
// It takes a number of top-level-arguments (TLA) which can control
// input configuration and input data and a number of output data
// "taps".  You may also control if it runs in single or multi thread
// mode
//
// Run like
//
//  wire-cell \
//    -A depos=depos.npz \
//    -A taps={...see below...} \
//    -A wires=wires-geometry.json.bz2 \
//    -A resps=field-response.json.bz2 \
//    -A resps_sim=field-response-for-sim.json.bz2 \
//    -A resps_sigproc=field-response-for-sigproc.json.bz2 \
//    -A noisef=/path/to/noise/model/file \
//    -A thread=[single|multi] \
//    -c main-depos-sim-adc.jsonnet
//
// The 'noisef' TLA is optional and specifies a noise model file.  If
// not given, only signal is simulated.
//
// If "taps" is given it specifies a mapping from a data tier key word
// to a file name.  The key is one of the conventional tags:
//
// - orig :: means the ADC-level frames out of the simulation
// - gauss :: means the signal processing with Gaussian filter
//
// The file name may have a "%" formatter which will be interpolated
// against the APA ID number.  If omitted, "-apa%d" will be inserted
// at the end of the base file name just prior to the extention
// (likely .npz).

local wc = import "wirecell.jsonnet";
local pg = import "pgraph.jsonnet";

local tz = import "toyzero.jsonnet";
local io = import "ioutils.jsonnet";
local nf = import "nf.jsonnet";
local sp = import "sp.jsonnet";

local params = import "pgrapher/experiment/pdsp/simparams.jsonnet";
local spfilt = import "pgrapher/experiment/pdsp/sp-filters.jsonnet";
local chndb = import "pdsp_chndb.jsonnet";

function(input, taps, wires, resps_sim, resps_sigproc, noisef=null, thread='single')
    local app = if thread == 'single'
                then 'Pgrapher'
                else 'TbbFlow';
    local seeds = [0,1,2,3,4];  // maybe let CLI set?
    local depos = io.npz_source_depo("depos", input);


    local wireobj = tz.wire_file(wires);
    local anodes = tz.anodes(wireobj, params.det.volumes);

    local apaids = std.range(0, std.length(anodes)-1);

    local robjs_sim = tz.responses(resps_sim, params.elec, params.daq);
    local robjs_sigproc = tz.responses(resps_sigproc, params.elec, params.daq);

    local random = tz.random(seeds);

    local drifter = tz.drifter(params.det.volumes, params.lar, random);
    local bagger = tz.bagger(params.daq);

    local chndb_perfect(n) =
        chndb.perfect(anodes[n], robjs_sim.fr,
                      params.daq.nticks,
                      params.daq.tick);

    local tap_out(tap, apaid) =
        if std.objectHas(taps, tap)
        then [io.frame_out(tap+"%d", apaid, taps[tap], tags=[tap+"%d"], cap = tap=="gauss")]
        else [];

    local sim(n) = [
        local anode = anodes[n];
        tz.sim(anode,               // kitchen
               robjs_sim.pirs,      // sink
               params.daq,
               params.adc,
               params.lar,
               noisef,
               'adc',
               random)
    ] + tap_out("orig", n);

    local adcpermv = tz.adcpermv(params.adc);
    local nfsp(n) = [
        nf(anodes[n], robjs_sigproc.fr, chndb_perfect(n),
           params.daq.nticks, params.daq.tick),
    ] + tap_out("raw", n) + [
        sp(anodes[n], robjs_sigproc.fr, robjs_sigproc.er, spfilt, adcpermv)
    ] + tap_out("gauss", n);

    local oneapa(n) = pg.pipeline(sim(n) + nfsp(n));

    local pipes = [oneapa(n) for n in apaids];

    local body = pg.fan.fanout('DepoSetFanout', pipes);
    local full = pg.pipeline([depos, drifter, bagger, body]);

    tz.main(full, app)


