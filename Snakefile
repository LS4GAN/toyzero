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

rule summarize_wires:
    input:
        f'data/{{wire}}.{wcdata_ext}'
    output:
        'data/{wire}-summary.json'
    shell: '''
    wirecell-util wire-summary -o {output} {input}
    '''

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

## warning, as-is, this really only works on APA-CPA-APA detector patterns
def protodune_boundary(w):
    det = json.loads(open('data/{wire}-summary.json'.format(wire=w.wire)).read())
    p1 = det[0]['bb']['minp']
    p2 = det[0]['bb']['maxp']
    corn = list()
    diag = list()
    for l in "xyz":
        c = p1[l]
        dc = p2[l]-p1[l]
        # warning, pretend we know WCT's SoU here....
        corn.append(f'{c:.1f}*mm')
        diag.append(f'{dc:.1f}*mm')
    return dict(corn = ','.join(corn), diag = ','.join(diag))

rule gen_depos:
    input:
        'data/{wire}-summary.json'
    params:
        p = protodune_boundary,
        tracks = 10,
        sets = 10
    output:
        'data/{wire}-depos.npz'
    shell: '''
    wirecell-gen depo-lines \
    --tracks {params.tracks} --sets {params.sets} \
    --diagonal '{params.p[diag]}' --corner '{params.p[corn]}' \
    --output {output}
    '''

rule all_depos:
    input:
        expand(rules.gen_depos.output, wire=wires)


# wct - run wire-cell simulation


rule all:
    input:
        rules.all_resp.output,
        rules.all_wires.output,
        rules.all_depos.output
