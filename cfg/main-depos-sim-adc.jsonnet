// This is a main wire-cell configuration file.
//
// It implements the chain (depos)->[sim]->(ADC).
//
// It takes a number of top-level-arguments (TLA).
//
// Run like
//
//  wire-cell \
//    -A input=depos.npz -A output=frames.npz \
//    -A wires=wires-geometry.json.bz2 \
//    -A resps=field-response.json.bz2 \
//    -A noisef=/path/to/noise/model/file \
//    -c main-depos-sim-adc.jsonnet
//
// The 'noise' TLA is optional and defaults to "no".

local wc = import "wirecell.jsonnet";
local pg = import "pgraph.jsonnet";

local tz = import "toyzero.jsonnet";
local io = import "ioutils.jsonnet";

function(input, output, wires, resps, noisef=null) 
local seeds = [0,1,2,3,4];  // maybe let CLI set?
local depos = io.npz_source_depo("depos", input);

local params = tz.protodune_params;

local wireobj = tz.wire_file(wires);
local anodes = tz.anodes(wireobj, params.det.volumes);

local apaids = std.range(0, std.length(anodes)-1);

local pirs = tz.pirs(resps, params.daq, params.elec);

local random = tz.random(seeds);

local drifter = tz.drifter(params.det.volumes, params.lar, random);
local bagger = tz.bagger(params.daq);

local apasim(n) =
    tz.apasim(anodes[n], pirs, params.det.volumes[n],
              params.daq, params.adc, params.lar,
              noisef, random);

local simpipes = [apasim(n) for n in apaids];


local frames = io.frame_save_npz("frames", output);
local dump = io.frame_sink();

local simbody = pg.fan.pipe('DepoSetFanout', simpipes, 'FrameFanin');
local full = pg.pipeline([depos, drifter, bagger, simbody, frames, dump]);
tz.main(full)

