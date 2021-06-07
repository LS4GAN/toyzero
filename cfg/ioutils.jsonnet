local wc = import "wirecell.jsonnet";
local g = import 'pgraph.jsonnet';
{
    // Return a numpy depo source configuration.
    npz_source_depo(name, filename) :: g.pnode({
        type: 'NumpyDepoLoader',
        name: name,
        data: {
            filename: filename
        }
    }, nin=0, nout=1),


    // Return a numpy frame saver configuration.
    frame_save_npz(name, filename, digitize=true, tags=[]) :: g.pnode({
        type: 'NumpyFrameSaver',
        name: name,
        data: {
            filename: filename,
            digitize: digitize,
            frame_tags: tags,
        }}, nin=1, nout=1),

    // Use to cap off a frame stream with a sink.
    frame_sink(name="frame-sink") :: g.pnode({
        type: "DumpFrames",
        name: name,
    }, nin=1, nout=0),    
}
