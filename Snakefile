#!/usr/bin/env snakemake

import json
from snakemake.remote.HTTP import RemoteProvider as HTTPRemoteProvider
HTTP = HTTPRemoteProvider()

wcdata_url = "https://github.com/WireCell/wire-cell-data/raw/master"
wcdata_ext = "json.bz2"

## for now we support a low diversity build.  Just one detector (one
## set of wires which are downloaded) which are for ProtoDUNE-SP and
## one "real" and one "fake" set of field responses.  The "fake" is
## derived from "real" which is downloaded.  Later we may expand these
## to span some set of each.
resps = "dune-garfield-1d565"
wires = "protodune-wires-larsoft-v4"

# some important file names
real_resps = f'data/real-resps.{wcdata_ext}'
fake_resps = f'data/fake-resps.{wcdata_ext}'
domain_resps = f'data/{{domain}}-resps.{wcdata_ext}'
wires_file = f'data/wires.{wcdata_ext}'
depos_file = 'data/depos.npz'
domain_frames = 'data/{domain}-frames.npz'

# resp - prepare response files

rule get_resp_real:
    input:
        HTTP.remote(f'{wcdata_url}/{resps}.{wcdata_ext}', keep_local=True)
    output:
        real_resps
    run:
        shell("mkdir -p data")
        shell("mv {input} {output}")

rule gen_resp_fake:
    input:
        real_resps
    output:
        fake_resps
    shell: '''
    wirecell-sigproc frzero -n 0 -o {output} {input}
    '''

rule plot_resp:
    input:
        domain_resps
    output:
        'plots/{domain}-resps-diagnostic.png'
    shell: '''
    mkdir -p plots; 
    wirecell-sigproc plot-response {input} {output}
    '''

rule all_resp:
    input:
        rules.get_resp_real.output,
        rules.gen_resp_fake.output,
        expand(rules.plot_resp.output, domain=["real","fake"])

# wires - get wires file

rule get_wires:
    input:
        HTTP.remote(f'{wcdata_url}/{wires}.{wcdata_ext}', keep_local=True)
    output:
        wires_file
    run:
        shell("mkdir -p data")
        shell("mv {input} {output}")


rule plot_wires:
    input:
        wires_file
    output:
        'plots/wires-diagnostic.pdf'
    shell: '''
    mkdir -p plots;
    wirecell-util plot-wires {input} {output}
    '''

rule all_wires:
    input:
        rules.get_wires.output,
        rules.plot_wires.output


# depos - generate ionization point depositions

def gen_depos_cfg(w):
    'Dig out the bounding box of the detector'

    params_cmd = 'wcsonnet pgrapher/experiment/pdsp/simparams.jsonnet'
    jtext = subprocess.check_output(params_cmd, shell=True)
    jdat = json.loads(jtext)
    bb = jdat['det']['bounds']

    p1 = bb['tail']
    p2 = bb['head']
    corn = list()
    diag = list()
    for l in "xyz":
        c = p1[l]
        dc = p2[l]-p1[l]
        # warning, pretend we know WCT's SoU here....
        corn.append(f'{c:.1f}*mm')
        diag.append(f'{dc:.1f}*mm')

    return dict(tracks = 10, sets = 10, # fixme: get from config file?
                corn = ','.join(corn), diag = ','.join(diag))

rule gen_depos:
    input:
        wires_file
    params:
        p = gen_depos_cfg
    output:
        depos_file
    shell: '''
    wirecell-gen depo-lines \
    --tracks {params.p[tracks]} --sets {params.p[sets]} \
    --diagonal '{params.p[diag]}' --corner '{params.p[corn]}' \
    --output {output}
    '''

rule all_depos:
    input:
        expand(rules.gen_depos.output, wire=wires)


# frames

rule sim_dots:
    input:
        config = 'cfg/main-depos-sim-adc.jsonnet'
    output:
        json = 'data/sim-graph.json',
        dot = 'data/sim-graph.dot',
        png = 'plots/sim-graph.png',
        pdf = 'plots/sim-graph.pdf'
    shell: '''
    wcsonnet \
    -P cfg \
    -A input=DEPOS-FILE \
    -A output=FRAMES-FILE \
    -A wires=WIRES-FILE \
    -A resps=RESPS-FILE \
    {input.config} > {output.json};
    wirecell-pgraph dotify --jpath=-1 {output.json} {output.dot} ;
    dot -Tpng -o {output.png} {output.dot} ;
    dot -Tpdf -o {output.pdf} {output.dot}
    '''

rule sim_frames:
    input:
        wires = wires_file,
        resps = domain_resps,
        depos = depos_file,
        config = 'cfg/main-depos-sim-adc.jsonnet'
    output:
        frames = domain_frames
    shell: '''
    wire-cell \
    -l stdout -L info \
    -P cfg \
    -A input={input.depos} \
    -A output={output.frames} \
    -A wires={input.wires} \
    -A resps={input.resps} \
    -c {input.config}
    '''
        
rule all_frames:
    input:
        expand(rules.sim_frames.output, domain=["real","fake"])


rule split_images:
    input:
        domain_frames
    output:
        directory('data/images/{domain}')
    shell: '''
    wirecell-util frame-split \
    -f {output}/{{detector}}-{{tag}}-{{index}}-{{anodeid}}-{{planeletter}}.npz \
    {input}
    '''

rule all_images:
    input:
        expand(rules.split_images.output, domain=["real","fake"])


rule all:
    input:
        rules.all_resp.input,
        rules.all_wires.input,
        rules.all_depos.input,
        rules.all_frames.input,
        rules.all_images.input
