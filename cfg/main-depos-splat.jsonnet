// This is a main wire-cell configuration file.
//
// It implements the chain:
//   (depos)->splat->(signals)
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
//    -A thread=[single|multi] \
//    -c main-depos-splat.jsonnet
//
// If "taps" is given it specifies a mapping from a data tier key word
// to a file name.  The key is one of the conventional tags:
//
// - splat :: the output of DepoSplat.
//
// The file name may have a "%" formatter which will be interpolated
// against the APA ID number.  If omitted, "-apa%d" will be inserted
// at the end of the base file name just prior to the extention
// (likely .npz).

local wc = import "wirecell.jsonnet";
local pg = import "pgraph.jsonnet";

local tz = import "toyzero.jsonnet";
local io = import "ioutils.jsonnet";

local params = import "pgrapher/experiment/pdsp/simparams.jsonnet";
local spfilt = import "pgrapher/experiment/pdsp/sp-filters.jsonnet";
local chndb = import "pdsp_chndb.jsonnet";

function(input, taps, wires, thread='single')
    local app = if thread == 'single'
                then 'Pgrapher'
                else 'TbbFlow';
    local seeds = [0,1,2,3,4];  // maybe let CLI set?
    local depos = io.npz_source_depo("depos", input);


    local wireobj = tz.wire_file(wires);
    local anodes = tz.anodes(wireobj, params.det.volumes);

    local apaids = std.range(0, std.length(anodes)-1);

    local random = tz.random(seeds);

    local drifter = tz.drifter(params.det.volumes, params.lar, random);

    local tap_out(tap, apaid) =
        if std.objectHas(taps, tap)
        then [io.frame_out(tap+"%d", apaid, taps[tap], tags=[tap+"%d"], cap = tap=="gauss")]
        else [];

    local splat(n, ) = [
        local anode = anodes[n];
        tz.splat(anode, params.daq, params.lar)
    ] + tap_out("splat", n);

    local oneapa(n) = pg.pipeline(splat(n));

    local pipes = [oneapa(n) for n in apaids];

    local body = pg.fan.fanout('DepoFanout', pipes);
    local full = pg.pipeline([depos, drifter, body]);

    tz.main(full, app)


