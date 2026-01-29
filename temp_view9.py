from pathlib import Path
lines = Path('scripts/sim/Sim.gd').read_text().splitlines()
for i,line in enumerate(lines,1):
    if 1950 <= i <= 1975:
        print(f"{i:04d}:{line}")
