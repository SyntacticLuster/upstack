from pathlib import Path
lines = Path('scripts/sim/Sim.gd').read_text().splitlines()
for i,line in enumerate(lines[:80],1):
    print(f"{i:04d}:{line}")
