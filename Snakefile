#!/usr/bin/env snakemake

import json
from snakemake.remote.HTTP import RemoteProvider as HTTPRemoteProvider
HTTP = HTTPRemoteProvider()

wcdata_url = "https://github.com/WireCell/wire-cell-data/raw/master"
wcdata_ext = "json.bz2"
resp2ds = ["garfield-1d-boundary-path-rev-dune"]
onedmark = "-wire0"
resp1ds = [r2d + onedmark for r2d in resp2ds]
wires = ["protodune-wires-larsoft-v4"]


# resp - prepare response files

rule get_wct_data:
    input:
        HTTP.remote(f'{wcdata_url}/{{thing}}.{wcdata_ext}', keep_local=True)
    output:
        f'data/{{thing}}.{wcdata_ext}'
    run:
        shell("mkdir -p data")
        shell("mv {input} {output}")

rule gen_resp1d:
    input:
        f'data/{{resp}}.{wcdata_ext}'
    output:
        f'data/{{resp}}{onedmark}.{wcdata_ext}'
    shell: '''
    wirecell-sigproc frzero -n 0 -o {output} {input}
    '''

rule plot_resp:
    input:
        f'data/{{resp}}.{wcdata_ext}'
    output:
        'plots/{resp}.png'
    shell: '''
    mkdir -p plots; 
    wirecell-sigproc plot-response {input} {output}
    '''

rule all_resp:
    input:
        expand(rules.get_wct_data.output, thing=resp2ds),
        expand(rules.gen_resp1d.output, resp=resp2ds),
        expand(rules.plot_resp.output, resp=resp1ds+resp2ds)

# wires - get wires file

rule plot_wires:
    input:
        f'data/{{wire}}.{wcdata_ext}'
    output:
        'plots/{wire}.pdf'
    shell: '''
    mkdir -p plots;
    wirecell-util plot-wires {input} {output}
    '''

rule all_wires:
    input:
        expand(rules.get_wct_data.output, thing=wires),
        expand(rules.plot_wires.output, wire=wires)

# depos - generate ionization point depositions

# def load_gencfg(w):
#     return json.load('gencfg/depos.json')

# rule gen_depos:
#     input:
#         'gencfg/depos.json'
#     params:
#         p = load_gencfg
#     output:
#         'data/depos.npz'
#     shell: '''
#     wirecell-gen depo-lines ---tracks 10 --sets 10 --diagonal --corner --output {output}



rule all:
    input:
        rules.all_resp.input,
        rules.all_wires.input
