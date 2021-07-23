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
datadir = config.get("datadir", "data")
plotdir = config.get("plotdir", "plots")
outdir = config.get("outdir", os.environ.get("TOYZERO_OUTDIR", "."))

datadir = os.path.abspath(os.path.join(outdir, datadir))
plotdir = os.path.abspath(os.path.join(outdir, plotdir))
    
seed = config.get("seed", "1,2,3,4")
ntracks = config.get("ntracks", 10)
nevents = config.get("nevents", 10)
wcloglvl = config.get("wcloglvl", "info")

tiers = config.get("tiers", ["noiseless"])

# print(f"OUTDIR:{outdir}")
# print(f"NEVENTS:{nevents}")
# print(f"WCLOGLVL:{wcloglvl}")
print(f"TIERS:{tiers}, {type(tiers)}")

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
# a few places want a list of APA IDs
apa_iota = list(range(6))

# The data domains describe a universe.  For toyzero, they are
# associated with a particular detector response.
DOMAINS = ["fake", "real"]

# The data tiers for frame or image
TIERS = ["noiseless", "signal"]

# some important file names
real_resps    = f'{datadir}/resps/real-resps.{wcdata_ext}'
fake_resps    = f'{datadir}/resps/fake-resps.{wcdata_ext}'
domain_resps  = f'{datadir}/resps/{{domain}}-resps.{wcdata_ext}'
wires_file    = f'{datadir}/wires/wires.{wcdata_ext}'
depos_file    = f'{datadir}/depos/depos.npz'

# resp - prepare response files

rule get_resp_real:
    input:
        HTTP.remote(f'{wcdata_url}/{resps}.{wcdata_ext}', keep_local=True)
    output:
        temp(real_resps)
    run:
        shell("mkdir -p {datadir}")
        shell("cp {input} {output}")

rule gen_resp_fake:
    input:
        real_resps
    output:
        temp(fake_resps)
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
        temp(wires_file)
    run:
        shell("mkdir -p {datadir}")
        shell("cp {input} {output}")


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

    # params_cmd = 'wcsonnet pgrapher/experiment/pdsp/simparams.jsonnet'
    # jtext = subprocess.check_output(params_cmd, shell=True)
    # jdat = json.loads(jtext)
    # bb = jdat['det']['bounds']
    # p1 = bb['tail']
    # p2 = bb['head']
    # corn = list()
    # diag = list()
    # for l in "xyz":
    #     c = p1[l]
    #     dc = p2[l]-p1[l]
    #     # warning, pretend we know WCT's SoU here....
    #     corn.append(f'{c:.1f}*mm')
    #     diag.append(f'{dc:.1f}*mm')

    # found by running once and looking at AnodePlane log msgs
    diag = '16000.0*mm,6100.0*mm,7000.0*mm'
    corn = '-8000.0*mm,0.0*mm,0.0*mm'

    return dict(tracks = ntracks, sets = nevents, seed = seed,
                corn = corn, diag = diag)
                #corn = ','.join(corn), diag = ','.join(diag))

rule gen_depos:
    input:
        wires_file
    params:
        p = gen_depos_cfg
    output:
        temp(depos_file)
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

def wct_cfg_file(w):
    slugs = dict(signal="depos-sigproc",
                 noiseless="depos-sim-adc")
    slug = slugs[w.tier]
    return f'cfg/main-{slug}.jsonnet'


# note, passes bogus TLAs so don't use the genearted json!
rule wct_dots:
    input:
        config = wct_cfg_file
    output:
        json = temp(f'{plotdir}/dots/{{tier}}/cfg.json'),
        dot  = temp(f'{plotdir}/dots/{{tier}}/dag.dot'),
        png  = f'{plotdir}/dots/{{tier}}/dag.png',
        pdf  = f'{plotdir}/dots/{{tier}}/dag.pdf'
    shell: '''
    mkdir -p {plotdir}/dots/{wildcards.tier};
    wcsonnet \
    -P cfg \
    -A input=DEPOS-FILE \
    --tla-code taps='{{"orig":"frame-orig-.npz","gauss":"frame-gauss.npz"}}' \
    -A wires=WIRES-FILE \
    -A resps=RESPS-FILE \
    {input.config} > {output.json};
    wirecell-pgraph dotify --no-params --jpath=-1 {output.json} {output.dot} ;
    dot -Tpng -o {output.png} {output.dot} ;
    dot -Tpdf -o {output.pdf} {output.dot}
    '''
rule all_dots:
    input:
        expand(rules.wct_dots.output, tier=tiers)

# this gives the pattern for one per-APA frame file.  The %d is
# interpolated by wire-cell configuration.
frames_pattern = f'{datadir}/frames/{{tier}}/{{domain}}-frames-apa%d.npz'
frames_wildcard = f'{datadir}/frames/{{tier}}/{{domain}}-frames-apa{{apa}}.npz'

def frame_taps(w):
    if w.tier == "noiseless":
        tap = "orig"
    else:
        tap = "gauss"
    fp = frames_pattern.format(**dict(w))
    return dict(tap=tap, pat=fp)

rule sim_frames:
    input:
        wires = wires_file,
        resps = domain_resps,
        depos = depos_file,
        config = wct_cfg_file
    output:
        temp([frames_pattern%n for n in apa_iota])
    params:
        p = frame_taps
    shell: '''
    rm -f {output}; 
    wire-cell \
    -l stdout -L {config[wcloglvl]} \
    -P cfg \
    -A input={input.depos} \
    --tla-code 'taps={{"{params.p[tap]}":"{params.p[pat]}"}}' \
    -A wires={input.wires} \
    -A resps={input.resps} \
    -c {input.config}
    '''
        
def gen_plot_frames(w):
    i = int(w.apa)
    if w.tier == "noiseless":
        return dict(chb=f'{i},{i+2560}', tag="")
    if w.tier == "signal":
        tag = f"gauss{i}"
        return dict(chb=f'0,2560', tag=tag)

rule plot_frames:
    input:
        frames_wildcard
    output:
        f'{plotdir}/frames-{{tier}}-{{domain}}-apa{{apa}}.{{ext}}'
    params:
        p = gen_plot_frames
    shell:'''
    wirecell-gen plot-sim {input} {output} -p frames -b {params.p[chb]} --tag "{params.p[tag]}"
    '''

rule plot_frames_hidpi:
    input:
        f'{plotdir}/frames-{{tier}}-{{domain}}-apa{{apa}}.pdf'
    output:
        f'{plotdir}/hidpi/frames-{{tier}}-{{domain}}-apa{{apa}}.png'
    params:

    shell:'''
    pdftoppm -rx 600 -ry 600 {input} | pnmtopng > {output}
    '''


rule all_frames:
    input:
        expand(rules.sim_frames.output, domain=["real","fake"],
               tier=tiers),
        expand(rules.plot_frames.output, domain=["real","fake"],
               tier=tiers,
               ext=["png","pdf"], apa=apa_iota),
        expand(rules.plot_frames_hidpi.output, domain=["real","fake"],
               tier=tiers, apa=[0])



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
#    domain = ["protodune"],
    event  = list(range(nevents)),
    apa    = apa_iota,
    plane  = ["U","V","W"],
)

rule split_images:
    input:
        frames_wildcard
    output:
        expand(datadir+'/images/{{tier}}/{{domain}}/protodune-orig-{event}-{apa}-{plane}.npz',
               **split_outer_product)
    shell: '''
    wirecell-util frame-split \
    -f {datadir}/images/{wildcards.tier}/{wildcards.domain}/{{detector}}-{{tag}}-{{index}}-{{anodeid}}-{{planeletter}}.npz \
    {input}
    '''

def gen_title(w):
    if w.domain == 'real':
        dim='2D'
    else:
        dim='q1D'
    return f'"{w.tier} {w.domain}/{dim}, event {w.event}, APA {w.apa}, {w.plane} plane"',

## Note, we must match the input here by hand to the output above
## because the domain is not included in the expand above but is here.
## Above is 1->N, here is 1->1.
rule plot_split_images:
    input:
        datadir+'/images/{tier}/{domain}/protodune-orig-{event}-{apa}-{plane}.npz',
    output:
        plotdir+'/images/{tier}/{domain}/{cmap}/protodune-orig-{event}-{apa}-{plane}.{ext}'
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
        expand(rules.split_images.output,
               domain=["real","fake"], tier=tiers),
        expand(
            rules.plot_split_images.output,
            domain = ["real","fake"],
            tier = tiers,
            event  = [0], apa=[2], plane=["U"],
            ext    = ["png", "pdf", "svg"],
            cmap   = ["seismic", "Spectral", "terrain", "coolwarm", "viridis"],
        )

rule just_images:
    input:
        expand(rules.split_images.output,
               domain=["real","fake"],
               tier=tiers)

rule all:
    input:
        rules.all_resp.input,
        rules.all_wires.input,
        rules.all_depos.input,
        rules.all_frames.input,
        rules.all_images.input

