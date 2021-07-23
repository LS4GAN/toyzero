#!/bin/bash

set -x

tiers=(raw orig gauss threshold)

taps=""
for tier in ${tiers[*]}
do
    taps+="{\"$tier\":\"testit/fake-frames-${tier}.npz\"}"
done

if [ -f testit/fake-frames-orig-apa0.npz ] ; then
    echo "wire-cell has run already, rm testit if you want"
else
    mkdir -p testit
    wire-cell \
        -l stdout -L debug -P cfg\
        -A input=data/depos/depos.npz \
        --tla-code taps=$taps \
        -A wires=data/wires/wires.json.bz2  \
        -A resps=data/resps/fake-resps.json.bz2 \
        -A thread=multi \
        -A noisef=protodune-noise-spectra-v1.json.bz2 \
        -c cfg/main-depos-sigproc.jsonnet || exit 
fi


for tier in raw orig gauss
do
    for apaid in 0 1 2 3 4 5
    do
        tag=${tier}${apaid}
        wirecell-gen \
            plot-sim \
            testit/fake-frames-${tier}-apa${apaid}.npz \
            -p frames -b 0,2560 --tag ${tier}${apaid} \
            testit/fake-frames-${tier}-apa${apaid}.png
    done
done



