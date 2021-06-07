// Define objects describing protodune.

local params = import "pgrapher/experiment/pdsp/simparams.jsonnet";

function(wires, resps)
{
    volumes: params.volumes,

    local wireobj = {type:"WireSchemaFile", data: {filename: wires}},

    anodes: [ {
        type: "AnodePlane",
        name: "AnodePlane%d", vol.wires,
        data: {
            ident: vol.wires,
            wire_schema: wc.tn(wireobj),
            faces: vol.faces,
        },
        uses: [wireobj]
    } for vol in volumes],
}
