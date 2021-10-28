// configure DNN-ROI for one APA given anode and torch service (ts)
// objects.  The plane_channels should be a 3-list of pairs giving
// channel begin/end numbers for each plane's contiguous channel IDs
// with U,V,W as index 0,1,2.
//
// FIXME: okay for pdsp/mb but what if a detector does not have
// contiguous IDs???  To be more general, DNNROIFinding should be made
// to take an exhaustive list of channel IDs.

local wc = import "wirecell.jsonnet";
local pg = import "pgraph.jsonnet";

// The prefix is prepended to all internal node names.

function (anode, ts, prefix="dnnroi", output_scale=1.0) 
    local apaid = anode.data.ident;
    local prename = prefix + std.toString(apaid);

    local dnnroi_u = pg.pnode({
        type: "DNNROIFinding",
        name: prename+"u",
        data: {
            anode: wc.tn(anode),
            plane: 0,
            intags: ['loose_lf%d'%apaid, 'mp2_roi%d'%apaid, 'mp3_roi%d'%apaid],
            decon_charge_tag: "decon_charge%d" %apaid,
            outtag: "dnnsp%du"%apaid,
            output_scale: output_scale,
            forward: wc.tn(ts)
        }
    }, nin=1, nout=1, uses=[ts, anode]);
    local dnnroi_v = pg.pnode({
        type: "DNNROIFinding",
        name: prename+"v",
        data: {
            anode: wc.tn(anode),
            plane: 1,
            intags: ['loose_lf%d'%apaid, 'mp2_roi%d'%apaid, 'mp3_roi%d'%apaid],
            decon_charge_tag: "decon_charge%d" %apaid,
            outtag: "dnnsp%dv"%apaid,
            output_scale: output_scale,
            forward: wc.tn(ts)
        }
    }, nin=1, nout=1, uses=[ts, anode]);
    local dnnroi_w = pg.pnode({
        type: "PlaneSelector",
        name: prename+"w",
        data: {
            anode: wc.tn(anode),
            plane: 2,
            tags: ["gauss%d"%apaid],
            tag_rules: [{
                frame: {".*":"DNNROIFinding"},
                trace: {["gauss%d"%apaid]:"dnnsp%dw"%apaid},
            }],
        }
    }, nin=1, nout=1, uses=[anode]);

    local dnnpipes = [dnnroi_u, dnnroi_v, dnnroi_w];
    local dnnfanout = pg.pnode({
        type: "FrameFanout",
        name: prename,
        data: {
            multiplicity: 3
        }
    }, nin=1, nout=3);

    local dnntag = "dnnsp%d" % apaid;

    local dnnfanin = pg.pnode({
        type: "FrameFanin",
        name: prename,
        data: {
            multiplicity: 3,
            tag_rules: [{
                frame: {".*":dnntag}
            } for plane in ["u", "v", "w"]]
        },
    }, nin=3, nout=1);
    
    pg.intern(innodes=[dnnfanout],
              outnodes=[dnnfanin],
              centernodes=dnnpipes,
              edges=[pg.edge(dnnfanout, dnnpipes[ind], ind, 0) for ind in [0,1,2]] +
              [pg.edge(dnnpipes[ind], dnnfanin, 0, ind) for ind in [0,1,2]])
