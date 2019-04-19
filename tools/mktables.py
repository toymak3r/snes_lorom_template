#!/usr/bin/env python
from __future__ import print_function, with_statement, division
import math
try:
    xrange
except NameError:
    xrange = range

def make_bytetable(it):
    x = 0
    out = []
    for el in it:
        out.append(',' if x else '  .byte ')
        out.append("%3d" % el)
        x += 1
        if x >= 16:
            x = 0
            out.append('\n')
    if x:
        out.append('\n')
    return ''.join(out)

# Playback frequency on the Super NES DSP is expressed in
# 125/16 = 7.8125 Hz units and can go no higher than 128 kHz.
# Our tuning assumes that each sample's period is 32 units,
# or middle C at (261+5/8) * 32 = 8372 Hz.

lowest_freq = 55 * 32 / 7.8125
num_notes = 64
freqs = [int(round(lowest_freq * math.pow(2, i / 12.0)))
          for i in xrange(num_notes)]

tmpl = """; Lookup tables for Super NES sound engine
; generated with mktables.py

.segment "SPCIMAGE"
noteFreqsLo:
%s
noteFreqsHi:
%s
"""
tables = (
    make_bytetable(f & 0xFF for f in freqs),
    make_bytetable(f >> 8 for f in freqs)
)
    
print(tmpl % tables)
