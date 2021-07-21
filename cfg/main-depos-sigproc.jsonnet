// This is a main wire-cell configuration file.
//
// It implements the chain:
//   (depos)->sim(signal,noise)->sigproc->(signals)
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
//    -A app=[Pgrapher|TbbFlow] \
//    -c main-depos-sim-adc.jsonnet
//
// The 'noisef' TLA is optional and specifies a noise model.  If not
// given, only signal is simulated.

local wc = import "wirecell.jsonnet";
local pg = import "pgraph.jsonnet";

local tz = import "toyzero.jsonnet";
local io = import "ioutils.jsonnet";
local nf = import "nf.jsonnet";
local sp = import "sp.jsonnet";

function(input, output, wires, resps, noisef=null, app='Pgrapher') 
local seeds = [0,1,2,3,4];  // maybe let CLI set?
local depos = io.npz_source_depo("depos", input);

local params = import "pgrapher/experiment/pdsp/simparams.jsonnet";
local spfilt = import "pgrapher/experiment/pdsp/sp-filters.jsonnet";

local wireobj = tz.wire_file(wires);
local anodes = tz.anodes(wireobj, params.det.volumes);

local apaids = std.range(0, std.length(anodes)-1);

local robjs = tz.responses(resps, params.elec, params.daq);

local random = tz.random(seeds);

local drifter = tz.drifter(params.det.volumes, params.lar, random);
local bagger = tz.bagger(params.daq);

local sim(n) =
    tz.sim(anodes[n], robjs.pirs, 
           params.daq, params.adc, params.lar,
           noisef, 'adc', random);

local adcpermv = tz.adcpermv(params.adc);
local nfsp(n) =
    pg.pipeline([
        //nf(anodes[n], robjs.fr, params.daq.nticks, params.daq.tick),
        sp(anodes[n], robjs.fr, robjs.er, spfilt, adcpermv)]);

local outfile(n) = {
    local l = std.split(output,"."),
    ret:"%s-apa%d.%s"%[l[0],n,l[1]]
}.ret;
local oneapa(n) = {
    local name = "gauss%d"%n,
    local outf = outfile(n),
    pipe: pg.pipeline([
        sim(n), nfsp(n),
        io.frame_save_npz(name, outf, digitize=false, tags=[name]),
        io.frame_sink(name)])
}.pipe;

local pipes = [oneapa(n) for n in apaids];

// local frame_tags = ["gauss%d"%n for n in apaids];
// local frames = io.frame_save_npz("frames", output,
//                                  digitize = false, tags=frame_tags);
// local dump = io.frame_sink();
// local body = pg.fan.pipe('DepoSetFanout', pipes, 'FrameFanin',
//                          outtags=frame_tags);

local body = pg.fan.fanout('DepoSetFanout', pipes);
local full = pg.pipeline([depos, drifter, bagger, body]);
tz.main(full, app)

