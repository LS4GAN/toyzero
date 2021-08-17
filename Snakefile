#!/usr/bin/env snakemake

import os
import json
from snakemake.remote.HTTP import RemoteProvider as HTTPRemoteProvider
HTTP = HTTPRemoteProvider()

# You can override with
##  $ snakemake --configfile mycfg.yaml [...] 
configfile: "toyzero.yaml"

# Or you can set individual config values
##  $ snakemake --config ntracks=100 [...]
datadir = config.get("datadir", "data")
plotdir = config.get("plotdir", "plots")
logdir = config.get("logdir", "logs")
outdir = config.get("outdir", os.environ.get("TOYZERO_OUTDIR", "."))

datadir = os.path.abspath(os.path.join(outdir, datadir))
plotdir = os.path.abspath(os.path.join(outdir, plotdir))
logdir  = os.path.abspath(os.path.join(outdir, logdir))
    
seed = config.get("seed", "1,2,3,4")
ntracks = int(config.get("ntracks", 10))
nevents = int(config.get("nevents", 10))
depotimes = config.get("depotimes", "-3*ms,6*ms")
wcloglvl = config.get("wcloglvl", "info")

# limit number of threads per wire-cell job
wct_threads = int(config.get("threads", 1))
# single threaded uses Pgrapher, multi uses TbbFlow
wct_threading = "single" if wct_threads == 1 else "multi"
print(f'WCT THREADS {wct_threads} ({wct_threading})')

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

# The data tiers for frame or image. We make all tiers in one job.
# The 'orig' is the output of the simulation and 'gauss' is the output
# of signal processing using the charge-preserving filters.
SIM_TIERS = ["orig", "gauss"]
TIERS = SIM_TIERS + ["splat"]

# some important file names
real_resps    = f'{datadir}/resps/real-resps.{wcdata_ext}'
fake_resps    = f'{datadir}/resps/fake-resps.{wcdata_ext}'
domain_resps  = f'{datadir}/resps/{{domain}}-resps.{wcdata_ext}'
wires_file    = f'{datadir}/wires/wires.{wcdata_ext}'
depos_file    = f'{datadir}/depos/depos.npz'
noise_file    = f'{datadir}/noise/protodune-noise-spectra-v1.{wcdata_ext}'

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

rule get_noisef:
    input:
        HTTP.remote(f'{wcdata_url}/protodune-noise-spectra-v1.{wcdata_ext}', keep_local=True)
    output:
        temp(noise_file)
    run:
        shell("mkdir -p {datadir}")
        shell("cp {input} {output}")

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

rule gen_depos:
    input:
        wires_file
    params:
        diag = '16000.0*mm,6100.0*mm,7000.0*mm',
        corn = '-8000.0*mm,0.0*mm,0.0*mm'
    output:
        temp(depos_file)
    shell: '''
    wirecell-gen depo-lines \
    --time {depotimes} \
    --seed {seed} \
    --tracks {ntracks} --sets {nevents} \
    --diagonal '{params.diag}' --corner '{params.corn}' \
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


wct_sigproc_cfg = 'cfg/main-depos-sigproc.jsonnet'
wct_splat_cfg = 'cfg/main-depos-splat.jsonnet'

def wct_dots_params(w):
    if w.verb == "brief":
        return "--no-params"
    return ""
# note, we pass bogus TLAs so don't use the generated json for
# anything real!
rule wct_dots:
    input:
        config = wct_sigproc_cfg
    output:
        json = temp(f'{plotdir}/dots/cfg-{{verb}}.json'),
        dot  = temp(f'{plotdir}/dots/dag-{{verb}}.dot'),
        png  = f'{plotdir}/dots/dag-{{verb}}.png',
        pdf  = f'{plotdir}/dots/dag-{{verb}}.pdf'
    params:
        wct_dots_params
    shell: '''
    mkdir -p {plotdir}/dots;
    wcsonnet \
    -P cfg \
    -A input=DEPOS-FILE \
    --tla-code taps='{{"orig":"frame-orig-apa%d.tar.bz2","gauss":"frame-gauss-apa%d.tar.bz2"}}' \
    -A wires=WIRES-FILE \
    -A resps_sim=RESPS-SIM-FILE \
    -A resps_sigproc=RESPS-SIGPROC-FILE \
    -A noisef=NOISE-FILE \
    {input.config} > {output.json};
    wirecell-pgraph dotify {params} --jpath=-1 {output.json} {output.dot} ;
    dot -Tpng -o {output.png} {output.dot} ;
    dot -Tpdf -o {output.pdf} {output.dot}
    '''
rule all_dots:
    input:
        expand(rules.wct_dots.output, verb=["full", "brief"])

# this gives the pattern for one per-APA frame file.  The %d is
# interpolated by wire-cell configuration.

frames_ext = "tar.bz2"
frames_wildcard = f'{datadir}/frames/{{tier}}/{{sim_domain}}-{{sigproc_domain}}-frames-apa{{apa}}.{frames_ext}'

def frame_taps(w):
    frames_pattern = f'{datadir}/frames/{{tier}}/{{sim_domain}}-{{sigproc_domain}}-frames-apa%d.{frames_ext}'
    taps = list()
    for tier in ('orig', 'gauss'):
        d = dict(w)
        d["tier"] = tier
        taps.append('"%s":"%s"' % (tier, frames_pattern.format(**d)))

    taps = ",".join(taps)
    return '{%s}'%taps

def sim_frame_files():
    frames_pattern = datadir + '/frames/{tier}/{{sim_domain}}-{{sigproc_domain}}-frames-apa{apaid}.' + frames_ext
    return expand(frames_pattern, tier=SIM_TIERS, apaid = apa_iota)

rule sim_frames:
    input:
        wires = wires_file,
        resps_sim = f'{datadir}/resps/{{sim_domain}}-resps.{wcdata_ext}',
        resps_sigproc = f'{datadir}/resps/{{sigproc_domain}}-resps.{wcdata_ext}',
        depos = depos_file,
        config = wct_sigproc_cfg,
        noise = noise_file
    output:
        temp(sim_frame_files())
    params:
        taps = frame_taps
    benchmark:
        f'{logdir}/sim-frames-{{sim_domain}}-{{sigproc_domain}}.tsv'
    shell: '''
    rm -f {output}; 
    wire-cell \
    --threads {wct_threads} \
    -A thread={wct_threading} \
    -l stdout -L {config[wcloglvl]} \
    -P cfg \
    -A input={input.depos} \
    --tla-code 'taps={params.taps}' \
    -A wires={input.wires} \
    -A resps_sim={input.resps_sim} \
    -A resps_sigproc={input.resps_sigproc} \
    -A noisef={input.noise} \
    -c {input.config}
    '''
        

# like sim_frames but we use DepoSplat instead of sim+sigproc.
rule splat_frames:
    input:
        wires = wires_file,
        depos = depos_file,
        config = wct_splat_cfg
    output:
        temp([f'{datadir}/frames/splat/splat-frames-apa{apa}.{frames_ext}' for apa in apa_iota])
    params:
        taps = f'{{"splat":"{datadir}/frames/splat/splat-frames-apa%d.{frames_ext}"}}'
    shell: '''
    rm -f {output}; 
    wire-cell \
    --threads {wct_threads} \
    -A thread={wct_threading} \
    -l stdout -L {config[wcloglvl]} \
    -P cfg \
    -A input={input.depos} \
    --tla-code 'taps={params.taps}' \
    -A wires={input.wires} \
    -c  {input.config}
    '''


def gen_plot_frames(w):
    i = int(w.apa)
    tag = f"{w.tier}{i}"
    return dict(chb=f'0,2560', tag=tag)

rule plot_frames:
    input:
        frames_wildcard
    output:
        f'{plotdir}/frames/{{tier}}/{{sim_domain}}-{{sigproc_domain}}-apa{{apa}}.{{ext}}'
    params:
        p = gen_plot_frames
    shell:'''
    wirecell-gen plot-sim {input} {output} -p frames -b {params.p[chb]} --tag "{params.p[tag]}"
    '''

rule plot_splat_frames:
    input:
        f'{datadir}/frames/splat/splat-frames-apa{{apa}}.tar.gz'
    output:
        f'{plotdir}/frames/splat/splat-apa{{apa}}.{{ext}}'
    shell:'''
    wirecell-gen plot-sim {input} {output} -p frames -b 0,2560 --tag splat{wildcards.apa}
    '''


rule just_splat_frames:
    input:
        rules.splat_frames.output

rule all_splat_frames:
    input:
        rules.just_splat_frames.input,        
        expand(rules.plot_splat_frames.output,
               ext=["png"], apa=apa_iota)
    

rule just_frames:
    input:
        expand(rules.sim_frames.output,
               sim_domain=["real","fake"],
               sigproc_domain=["real","fake"],
               ),
        

rule all_frames:
    input:
        rules.all_resp.input,
        rules.all_wires.input,
        rules.all_depos.input,
        rules.just_frames.input,
        expand(rules.plot_frames.output,
               sim_domain=["real","fake"],
               sigproc_domain=["real","fake"],
               tier=SIM_TIERS,
               ext=["png"], apa=apa_iota),

        # expand(rules.plot_frames_hidpi.output,
        #        sim_domain=["real","fake"],
        #        sigproc_domain=["real","fake"],
        #        tier=TIERS, apa=[0])



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
    event  = list(range(nevents)),
    plane  = ["U","V","W"],
)

# frames_wildcard = f'{datadir}/frames/{{tier}}/{{domain}}-frames-apa{{apa}}.{frames_ext}'

# this pattern is formatted inside wirecell-util frame-split.
split_array_pattern = '{detector}-{tag}-{index}-{planeletter}'

sigproc_rebin = 4
def rebin_number(w):
    if w.tier == "orig":
        return 0;
    return sigproc_rebin
def tick_offset(w):
    if w.tier == 'splat':
        # approx, chosen by comparing gauss W to splat W plots
        # this is pre-rebin ticks, 0.5us.
        return 125+8
    return 0

rule split_images:
    input:
        frames_wildcard
    output:
        expand(datadir+'/images/{{tier}}/{{sim_domain}}-{{sigproc_domain}}/protodune-{{tier}}{{apa}}-{event}-{plane}.npz',
               **split_outer_product)
    params:
        outpath = datadir+'/images/{tier}/{sim_domain}-{sigproc_domain}',
        mdpath = 'metadata-{apa}.json',
        rebin = rebin_number,
        tickoff = tick_offset
    benchmark:
        f'{logdir}/split-images-{{tier}}-{{sim_domain}}-{{sigproc_domain}}-apa{{apa}}.tsv'
    run:
        if not os.path.exists(params.outpath):
            os.makedirs(params.outpath)
        mdpath = os.path.join(params.outpath, params.mdpath)
        with open(mdpath, "w") as fp:
            fp.write(json.dumps(dict(wildcards), indent=4))
        shell('wirecell-util frame-split -t {params.tickoff} -r {params.rebin} -m {mdpath} -a {params.outpath}/{split_array_pattern} {input}')

rule split_splat_images:
    input:
        f'{datadir}/frames/splat/splat-frames-apa{{apa}}.{frames_ext}'
    output:
        expand(datadir+'/images/{{tier}}/splat/protodune-{{tier}}{{apa}}-{event}-{plane}.npz',
               **split_outer_product)
    params:
        outpath = datadir+'/images/{tier}/splat',
        mdpath = 'metadata-{apa}.json',
        rebin = rebin_number,
        tickoff = tick_offset
    run:
        if not os.path.exists(params.outpath):
            os.makedirs(params.outpath)
        mdpath = os.path.join(params.outpath, params.mdpath)
        with open(mdpath, "w") as fp:
            fp.write(json.dumps(dict(wildcards), indent=4))
        shell('wirecell-util frame-split -t {params.tickoff} -r {params.rebin} -m {mdpath} -a {params.outpath}/{split_array_pattern} {input}')


def plot_split_params(w):
    if w.tier == 'splat':
        dim="splat"
    elif w.sim_domain == 'real':
        dim='sim:2D'
    else:
        dim='sim:q1D'

    if w.tier == "gauss":
        # only one response is relevant to ADC tier
        # signals may have a different response used in decon.
        if w.sigproc_domain == 'real':
            dim+='/SP:2D'
        else:
            dim+='/SP:q1D'

    if w.tier == "orig":
        ztitle='ADC (baseline subtracted)'
        vmin=-50
        vmax=50
        baseline="median"
    else:
        ztitle='Signal (ionization electrons)'
        vmin=0
        vmax=20000
        baseline="0"

    # we make 2 zoom levels.  1 is full, 2 is something zoomed in.

    chan0 = 0
    nchans = 960 if w.plane == "W" else 800
    tick0 = 0
    nticks = 6000

    # pick a region with good activity in all 3 views
    if int(w.zoomlevel) == 2:
        nchans = int(nchans / 5)
        tick0 = 3600
        nticks = 800

    if w.tier != "orig":
        tick0 = int(tick0/sigproc_rebin)
        nticks = int(nticks/sigproc_rebin)

    zoom = f'{chan0}:{chan0+nchans},{tick0}:{tick0+nticks}'
    title = f'{w.tier} {dim}, event {w.event}, APA {w.apa}, {w.plane} plane'

    return locals()



## Note, we must match the input here by hand to the output above
## because the domain is not included in the expand above but is here.
## Above is 1->N, here is 1->1.
plot_split_shell = '''
    wirecell-util npz-to-img --cmap {wildcards.cmap} \
    --title '{params.p[title]}' \
    --xtitle 'Relative ticks number' \
    --ytitle 'Relative channel number' \
    --ztitle '{params.p[ztitle]}' \
    --zoom '{params.p[zoom]}' \
    --vmin '{params.p[vmin]}' --vmax '{params.p[vmax]}' \
    --mask 0 \
    --dpi 600 --baseline='{params.p[baseline]}' -o {output} {input}
    '''
rule plot_split_images:
    input:
        datadir+'/images/{tier}/{sim_domain}-{sigproc_domain}/protodune-{tier}{apa}-{event}-{plane}.npz',
    output:
        plotdir+'/images/{tier}/{sim_domain}-{sigproc_domain}/{cmap}/protodune-{tier}{apa}-{event}-{plane}-zoom{zoomlevel}.{ext}'
    params:
        p = plot_split_params
    shell: plot_split_shell

rule plot_split_splat_images:
    input:
        datadir+'/images/{tier}/splat/protodune-{tier}{apa}-{event}-{plane}.npz',
    output:
        plotdir+'/images/{tier}/splat/{cmap}/protodune-{tier}{apa}-{event}-{plane}-zoom{zoomlevel}.{ext}'
    params:
        p = plot_split_params
    shell: plot_split_shell

rule just_images:
    input:
        rules.just_frames.input,
        rules.just_splat_frames.input,
        expand(rules.split_images.output,
               sim_domain=["real","fake"],
               sigproc_domain=["real","fake"],
               tier=["gauss"], apa=apa_iota),
        expand(rules.split_splat_images.output,
               tier=["splat"], apa=apa_iota)

## note, list-of-list for the split_images rule
rule all_images:
    input:
        rules.just_images.input,
        expand(
            rules.plot_split_images.output,
            sim_domain = ["fake"],
            sigproc_domain = ["fake"],
            tier = ["orig"],
            event  = [0], apa=apa_iota, plane=["U","V","W"],
            ext    = ["png"],
            cmap   = ["seismic"],
            zoomlevel=[1, 2],
        ),
        expand(
            rules.plot_split_images.output,
            sim_domain = ["real"],
            sigproc_domain = ["real"],
            tier = ["orig"],
            event  = [0], apa=apa_iota, plane=["U","V","W"],
            ext    = ["png"],
            cmap   = ["seismic"],
            zoomlevel=[1, 2],
        ),
        expand(
            rules.plot_split_images.output,
            sim_domain = ["real","fake"],
            sigproc_domain = ["real","fake"],
            tier = ["gauss"],
            event  = [0], apa=apa_iota, plane=["U","V","W"],
            ext    = ["png"],
            cmap   = ["viridis"],
            zoomlevel=[1, 2],
        ),
        expand(
            rules.plot_split_splat_images.output,
            tier = ["splat"],
            event  = [0], apa=apa_iota, plane=["U","V","W"],
            ext    = ["png"],
            cmap   = ["viridis"],
            zoomlevel=[1, 2],
        )


rule all:
    input:
        rules.all_resp.input,
        rules.all_wires.input,
        rules.all_depos.input,
        rules.all_frames.input,
        rules.all_images.input

