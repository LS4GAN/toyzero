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

function (anode, ts, plane_channels, prefix="dnnroi") 
    local apaid = anode.data.ident;
    local prename = prefix + std.toString(apaid);

    local dnnroi_u = pg.pnode({
        type: "DNNROIFinding",
        name: prename+"u",
        data: {
            anode: wc.tn(anode),
            intags: ['loose_lf%d'%apaid, 'mp2_roi%d'%apaid, 'mp3_roi%d'%apaid],
            outtag: "dnnsp%du"%apaid,
            cbeg: plane_channels[0][0],
            cend: plane_channels[0][1],
            torch_script: wc.tn(ts)
        }
    }, nin=1, nout=1, uses=[ts]);
    local dnnroi_v = pg.pnode({
        type: "DNNROIFinding",
        name: prename+"v",
        data: {
            anode: wc.tn(anode),
            intags: ['loose_lf%d'%apaid, 'mp2_roi%d'%apaid, 'mp3_roi%d'%apaid],
            outtag: "dnnsp%dv"%apaid,
            cbeg: plane_channels[1][0],
            cend: plane_channels[1][1],
            torch_script: wc.tn(ts)
        }
    }, nin=1, nout=1, uses=[ts]);
    local dnnroi_w = pg.pnode({
        type: "ChannelSelector",
        name: prename+"w",
        data: {
            channels: std.range(plane_channels[2][0], plane_channels[2][1]-1),
            tags: ["gauss%d"%apaid],
            tag_rules: [{
                frame: {".*":"DNNROIFinding"},
                trace: {["gauss%d"%apaid]:"dnnsp%dw"%apaid},
            }],
        }
    }, nin=1, nout=1);

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
