"""bands.py: the quality bands of the temper CLI (temper bands): each metric's history against its mean and sigma.

  python3 -I bands.py <metrics.json> <bands.json> <window> <min points> <drift run> <metrics> <1sigma> <2sigma> <3sigma> <now>

Called by cmd_bands in scripts/temper; it lived inside the CLI until 9.8.0, which moved it here to keep the CLI under the
plugin directory's 256 KiB limit for a file. Standard library only.
"""
import json, math, sys
metrics_path, out_path, window, min_points, drift_run, metrics_sep, t1, t2, t3, ts = sys.argv[1:11]
# Clamp config to sane floors, never crash on it (spine degradation contract): a
# non-integer or out-of-range window/min-points/drift-run falls back to its default
# rather than raising. window>=2 and min-points>=2 keep the baseline slice and the
# variance non-empty; drift-run>=2 keeps the run rule meaningful.
def _cfg_int(raw, default, floor):
    try:
        n = int(float(raw))
    except (ValueError, TypeError):
        return default
    return n if n >= floor else floor
window = _cfg_int(window, 10, 2)
min_points = _cfg_int(min_points, 4, 2)
drift_run = _cfg_int(drift_run, 6, 2)
# Two friendly aliases; beyond them, ANY <name>_history array in metrics.json is
# band-able by name — `temper metrics append <name> <value>` is how a series
# (including external ones: CI failure rate, 5xx counts) gets points.
ALIASES = {'coverage': 'coverage_history', 'tests': 'test_count_history'}
try:
    m = json.load(open(metrics_path))
    if not isinstance(m, dict):
        m = {}
except Exception:
    m = {}   # malformed metrics == absent; never a crash, never a breach (spine contract)

def numeric(v):
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, dict):
        for k in ('value', 'coverage', 'count', 'pct'):
            if isinstance(v.get(k), (int, float)) and not isinstance(v.get(k), bool):
                return float(v[k])
    return None

tier_names = {0: 'ok', 1: '1sigma', 2: '2sigma', 3: '3sigma'}
actions = {'1sigma': t1, '2sigma': t2, '3sigma': t3}
results, lines, worst, any_data = {}, [], 0, False
for name in [s for s in metrics_sep.split('\x1f') if s]:
    key = ALIASES.get(name)
    if key is None:
        candidate = name if name.endswith('_history') else f"{name}_history"
        if isinstance(m.get(candidate), list):
            key = candidate
    if key is None:
        known = sorted(set(ALIASES) | {k[:-len('_history')] for k in m if k.endswith('_history') and isinstance(m.get(k), list)})
        lines.append(f"  [--] {name} — unknown metric (known: {', '.join(known)}); skipped")
        results[name] = {'tier': 'unknown-metric'}
        continue
    raw = m.get(key, [])
    series = [x for x in (numeric(v) for v in (raw if isinstance(raw, list) else [])) if x is not None]
    if len(series) < min_points:
        lines.append(f"  [--] {name} — insufficient data ({len(series)} point(s) recorded, need {min_points})")
        results[name] = {'tier': 'insufficient-data', 'points': len(series)}
        continue
    any_data = True
    latest = series[-1]
    base = series[max(0, len(series) - 1 - window):-1]
    mean = sum(base) / len(base)
    sigma = math.sqrt(sum((x - mean) ** 2 for x in base) / len(base))
    if sigma == 0:
        z = 0.0 if latest == mean else (3.0 if latest > mean else -3.0)
    else:
        z = (latest - mean) / sigma
    level = 3 if abs(z) >= 3 else 2 if abs(z) >= 2 else 1 if abs(z) >= 1 else 0
    run = series[-drift_run:]
    drift = len(run) >= drift_run and (all(p > mean for p in run) or all(p < mean for p in run))
    if drift and level < 2:
        level = 2
    tier = tier_names[level]
    action = actions.get(tier)
    worst = max(worst, level)
    line = (f"  [{tier if level else 'ok'}] {name} — latest {latest:g} vs baseline "
            f"{mean:.2f} ±{sigma:.2f} (z={z:+.2f}, window {len(base)})")
    if drift:
        line += f" [drift: {drift_run} consecutive same-side point(s)]"
    if level >= 1:
        line += f": action={action}"
    lines.append(line)
    results[name] = {'latest': latest, 'mean': round(mean, 4), 'sigma': round(sigma, 4),
                     'z': round(z, 4), 'tier': tier, 'drift': drift,
                     'action': action if level >= 1 else None, 'window': len(base)}
verdict = 'BREACH' if worst >= 2 else ('OK' if any_data else 'INSUFFICIENT-DATA')
with open(out_path, 'w') as f:
    json.dump({'verdict': verdict, 'metrics': results, 'ts': ts}, f, indent=2)
    f.write('\n')
print(f"temper bands -> {verdict}")
for l in lines:
    print(l)
if worst >= 2:
    print("A 2sigma+ breach is a closing-the-loop trigger: /temper:status renders it; a "
          "propose-tier breach is drafted as .temper/specs/<slug>/intent.md for /temper to run.")
sys.exit(1 if worst >= 2 else 0)
