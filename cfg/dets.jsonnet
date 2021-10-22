
{
    pdsp: {
        params: import "pgrapher/experiment/pdsp/simparams.jsonnet",
        wires: "protodune-wires-larsoft-v4.json.bz2",

        sim: {
            response: "dune-garfield-1d565.json.bz2",
            noise: "protodune-noise-spectra-v1.json.bz2",
        },           
        sp: {
            filters: import "pgrapher/experiment/pdsp/sp-filters.jsonnet",
            chndb: import "pdsp_chndb.jsonnet",
            response: $.pdsp.sim.response,
        }, 
        channel_range(n) :: 
            local b = n*2560;
            [[b,b+800],[b+800,b+1600],[b+1600,b+2560]],

    },
}
