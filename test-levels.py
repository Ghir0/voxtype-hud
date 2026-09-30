import math
import struct
import subprocess
import sys


def tone(sec, amp):
    n = int(16000 * sec)
    out = bytearray()
    for i in range(n):
        v = int(amp * 32767 * math.sin(2 * math.pi * 180 * i / 16000))
        out += struct.pack("<h", v)
    return bytes(out)


pcm = tone(1, 0.0005) + tone(1, 0.05) + tone(1, 0.30)
p = subprocess.run([sys.executable, "hud-levels.py"], input=pcm, capture_output=True)
vals = [float(x) for x in p.stdout.decode().split()]
print("campioni:", len(vals))
print("silenzio     media: %.3f" % (sum(vals[:24]) / 24))
print("voce bassa   media: %.3f" % (sum(vals[25:49]) / 24))
print("voce forte   media: %.3f" % (sum(vals[50:74]) / 24))
print("primi 8:", [round(v, 2) for v in vals[:8]])
print("ultimi 8:", [round(v, 2) for v in vals[-8:]])
