#!/usr/bin/env snakemake

import json
import os
from snakemake.remote.HTTP import RemoteProvider as HTTPRemoteProvider
HTTP = HTTPRemoteProvider()

# You can override with
##  $ snakemake --configfile mycfg.yaml [...] 
configfile: "toyzero.yaml"

# Or you can set individual config values
##  $ snakemake --config ntracks=100 [...]
outdir = config.get("outdir", os.environ.get("TOYZERO_OUTDIR", "."))
datadir = os.path.join(outdir, config.get("datadir", "data"))
plotdir = os.path.join(outdir, config.get("plotdir", "plots"))
seed = config.get("seed", "1,2,3,4")
ntracks = config["ntracks"]#, 10)
nevents = config.get("nevents", 10)
print(f"NTRACKS:{ntracks}")

# The rest are hard wired for now
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
real_resps    = f'{datadir}/resps/real-resps.{wcdata_ext}'
fake_resps    = f'{datadir}/resps/fake-resps.{wcdata_ext}'
domain_resps  = f'{datadir}/resps/{{domain}}-resps.{wcdata_ext}'
wires_file    = f'{datadir}/wires/wires.{wcdata_ext}'
depos_file    = f'{datadir}/depos/depos.npz'
domain_frames = f'{datadir}/frames/{{domain}}-frames.npz'

# resp - prepare response files

rule get_resp_real:
    input:
        HTTP.remote(f'{wcdata_url}/{resps}.{wcdata_ext}', keep_local=True)
    output:
        real_resps
    run:
        shell("mkdir -p {datadir}")
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
        f'{plotdir}/{{domain}}-resps-diagnostic.png'
    shell: '''
    mkdir -p {plotdir}; 
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
        shell("mkdir -p {datadir}")
        shell("mv {input} {output}")


rule plot_wires:
    input:
        wires_file
    output:
        f'{plotdir}/wires-diagnostic.pdf'
    shell: '''
    mkdir -p {plotdir};
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

    return dict(tracks = ntracks, sets = nevents, seed = seed,
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
    --seed {params.p[seed]} \
    --tracks {params.p[tracks]} --sets {params.p[sets]} \
    --diagonal '{params.p[diag]}' --corner '{params.p[corn]}' \
    --output {output}
    '''

rule plot_depos:
    input:
        depos_file
    output:
        f'{plotdir}/depos-diagnostic.png'
    shell: '''
    wirecell-gen plot-sim {input} {output} -p depo
    '''
        
rule all_depos:
    input:
        expand(rules.gen_depos.output, wire=wires),
        expand(rules.plot_depos.output, wire=wires)


# frames

rule sim_dots:
    input:
        config = 'cfg/main-depos-sim-adc.jsonnet'
    output:
        json = f'{plotdir}/sim-graph.json',
        dot  = f'{plotdir}/sim-graph.dot',
        png  = f'{plotdir}/sim-graph.png',
        pdf  = f'{plotdir}/sim-graph.pdf'
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
        
def gen_plot_frames(w):
    i = int(w.apa)
    return dict(chb=f'{i},{i+2560}')

rule plot_frames:
    input:
        domain_frames
    output:
        f'{plotdir}/frames-{{domain}}-apa{{apa}}.{{ext}}'
    params:
        p = gen_plot_frames
    shell:'''
    wirecell-gen plot-sim {input} {output} -p frames -b {params.p[chb]}
    '''
rule plot_frames_hidpi:
    input:
        f'{plotdir}/frames-{{domain}}-apa{{apa}}.pdf'
    output:
        f'{plotdir}/hidpi/frames-{{domain}}-apa{{apa}}.png'
    params:

    shell:'''
    pdftoppm -rx 600 -ry 600 {input} | pnmtopng > {output}
    '''


rule all_frames:
    input:
        expand(rules.sim_frames.output, domain=["real","fake"]),
        expand(rules.plot_frames.output, domain=["real","fake"],
               ext=["png","pdf"], apa=list(range(6))),
        expand(rules.plot_frames_hidpi.output, domain=["real","fake"],
               apa=[0])



## This rule is a little tricky because frame-split generates its
## output file names while snake make must know these names in order
## to build a DAG without "holes".  Since we are able to give
## frame-split a pattern with which to form output file names we can
## at least predict what they will be.  However, is a 1-job->N-file
## pattern and we must exhaustively generate the output file names for
## snakemake.  To make matters more annoying we can not (apparently?)
## make output files from a function.  But we can call expand on
## static data (ie, defined right here).  So, that is what we do.
#
split_outer_product = dict(
    domain = ["protodune"],
    event  = list(range(10)),
    apa    = list(range(6)),
    plane  = ["U","V","W"],
)

rule split_images:
    input:
        domain_frames
    output:
        expand(datadir+'/images/{{domain}}/protodune-orig-{event}-{apa}-{plane}.npz',
               **split_outer_product)
    shell: '''
    wirecell-util frame-split \
    -f {datadir}/images/{wildcards.domain}/{{detector}}-{{tag}}-{{index}}-{{anodeid}}-{{planeletter}}.npz \
    {input}
    '''

def gen_title(w):
    if w.domain == 'real':
        dim='2D'
    else:
        dim='q1D'
    return f'"{w.domain}/{dim}, event {w.event}, APA {w.apa}, {w.plane} plane"',

## Note, we must match the input here by hand to the output above
## because the domain is not included in the expand above but is here.
## Above is 1->N, here is 1->1.
rule plot_split_images:
    input:
        datadir+'/images/{domain}/protodune-orig-{event}-{apa}-{plane}.npz',
    output:
        plotdir+'/images/{domain}/{cmap}/protodune-orig-{event}-{apa}-{plane}.{ext}'
    params:
        title = gen_title
    shell: '''
    wirecell-util npz-to-img --cmap {wildcards.cmap} \
    --title {params.title} \
    --xtitle 'Relative ticks number' \
    --ytitle 'Relative channel number' \
    --ztitle 'ADC (baseline subtracted)' \
    --zoom 300:500,0:1000 --mask 0 --vmin -50 --vmax 50 \
    --dpi 600 --baseline=median -o {output} {input}
    '''
## note, list-of-list for the split_images rule
rule all_images:
    input:
        expand(rules.split_images.output, domain=["real","fake"]),
        expand(
            rules.plot_split_images.output,
            domain = ["real","fake"],
            event  = [0], apa=[2], plane=["U"],
            ext    = ["png", "pdf", "svg"],
            cmap   = ["seismic", "Spectral", "terrain", "coolwarm", "viridis"],
        )

rule just_images:
    input:
        expand(rules.split_images.output, domain=["real","fake"]),

rule all:
    input:
        rules.all_resp.input,
        rules.all_wires.input,
        rules.all_depos.input,
        rules.all_frames.input,
        rules.all_images.input

