local wc = import "wirecell.jsonnet";
local pg = import 'pgraph.jsonnet';

local ut = import 'utils.jsonnet';

{
    // Return a numpy depo source configuration.
    npz_source_depo(name, filename) :: pg.pnode({
        type: 'NumpyDepoLoader',
        name: name,
        data: {
            filename: filename
        }
    }, nin=0, nout=1),


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
    frame_sink(name="frame-sink") :: pg.pnode({
        type: "DumpFrames",
        name: name,
    }, nin=1, nout=0),    


    // Save frames to outfile.
    //
    // name, outfile and elements of the tags list may have a single
    // "%" format code which if it exists will be interpolated again
    // the "index".
    //
    // If outfile has not "%" format the string "-apa%d" will be
    // appended to the base file name (prior to .ext).
    //
    // The "name" is used to give unique objects.
    //
    // The tags determine which among all available frames/trace tags
    // to save.
    //
    // If digitize is true, frame samples will be truncated to int
    // else left as float.
    //
    // If cap is false, the resulting node acts as a filter.
    frame_out(name, index, outfile, tags=["gauss%d"], digitize=false, cap=true) :: {
        local nam = if ut.haspct(name) then name%index else name,
        local tint = [if ut.haspct(t) then t%index else t for t in tags],
        local end = if cap then [$.frame_sink(nam)] else [],
        local outf = if ut.haspct(outfile) then outfile%index else ut.basename_append(outfile, "-apa%d"%index),

        ret: pg.pipeline([$.frame_save_npz(nam, outf, digitize=digitize, tags=tint)]
                         + end)
    }.ret,
    
}
