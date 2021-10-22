local wc = import "wirecell.jsonnet";
local pg = import 'pgraph.jsonnet';

local ut = import 'utils.jsonnet';

{
    // Return a numpy depo source configuration.
    npz_source_depo(name, filename, loadby="set") ::
        if loadby == "set"
        then pg.pnode({
            type: 'NumpyDepoSetLoader',
            name: name,
            data: {
                filename: filename
            }
        }, nin=0, nout=1)
        else pg.pnode({
            type: 'NumpyDepoLoader',
            name: name,
            data: {
                filename: filename
            }
        }, nin=0, nout=1),
    
    tar_source_depo(name, filename, scale=1.0) ::
        pg.pnode({
            type: 'DepoFileSource',
            name: name,
            data: { inname: filename, scale: scale }
        }, nin=0, nout=1),
            
    depo_source(filename, name="", scale=1.0) ::
        if std.endsWith(filename, ".npz")
        then $.npz_source_depo(name, filename)
        else $.tar_source_depo(name, filename, scale),


    // Return a numpy frame saver configuration.
    frame_save_npz(name, filename, digitize=true, tags=[]) :: pg.pnode({
        type: 'NumpyFrameSaver',
        name: name,
        data: {
            filename: filename,
            digitize: digitize,
            frame_tags: tags,
        }}, nin=1, nout=1),

    // Use to cap off a frame stream with a sink.
    frame_cap(name="frame-cap") :: pg.pnode({
        type: "DumpFrames",
        name: name,
    }, nin=1, nout=0),    


    // Sink a frame to a tar stream.  Filename extension can be .tar,
    // .tar.bz2 or .tar.gz.  There's no monkey business with a %d in
    // the file name.  Pass in a unique, literal file name.  Same goes
    // for tags.
    frame_sink(name, outfile, tags=[], digitize=false, dense=null) :: 
        pg.pnode({
            type: "FrameFileSink",
            name: name,
            data: {
                outname: outfile,
                tags: tags,
                digitize: digitize,
                dense: dense,
            },
        }, nin=1, nout=0),
        
    frame_tap(name, sink, tag, cap=false) :: 
        if cap
        then sink
        else pg.fan.tap('FrameFanout', sink, name,
                        tag_rules=[ // one for each port!
                            {frame:{'.*':tag}},
                            {frame:{'.*':tag}},
                        ]),


    
}
