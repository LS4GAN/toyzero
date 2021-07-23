#!/bin/bash

set -x

mkdir -p testit

tiers=(orig gauss)

taps=""
for tier in ${tiers[*]}
do
    taps+="{\"$tier\":\"testit/fake-frames-${tier}.npz\"}"
done

if [ -f testit/depos.npz ] ; then
    echo "depos already generated"
else
    wirecell-gen depo-lines \
    --seed 1234 \
    --tracks 100 \
    --sets 1 \
    --diagonal '16000.0*mm,6100.0*mm, 7000.0*mm' \
    --corner   '-8000.0*mm,0.0*mm,0.0*mm' \
    --output testit/depos.npz || exit
fi

if [ -f testit/fake-frames-orig-apa0.npz ] ; then
    echo "wire-cell has run already, rm testit if you want"
else
    wire-cell \
        -l stdout -L debug -P cfg\
        -A input=depos.npz \
        --tla-code taps=$taps \
        -A wires=data/wires/wires.json.bz2  \
        -A resps=data/resps/fake-resps.json.bz2 \
        -A thread=multi \
        -A noisef=protodune-noise-spectra-v1.json.bz2 \
        -c cfg/main-depos-sigproc.jsonnet || exit 
fi


for tier in orig gauss
do
    for apaid in 0 1 2 3 4 5
    do
        tag=${tier}${apaid}
        wirecell-gen \
            plot-sim \
            testit/fake-frames-${tier}-apa${apaid}.npz \
            -p frames -b 0,2560 --tag ${tier}${apaid} \
            testit/fake-frames-${tier}-apa${apaid}.png || exit
    done
done



