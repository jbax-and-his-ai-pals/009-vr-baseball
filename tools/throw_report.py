"""What the recorded throws say about pitch types and command. Plain Python 3, no packages.

    python tools/throw_report.py              # every throws_*.jsonl / events_*.jsonl in the game's user folder
    python tools/throw_report.py --dir PATH   # another folder

Sections (numbers quoted in docs/GAMEPLAY_NEXT.md come from here):
  1. Catcher signs: the pitch called vs the pitch the namer gave it
  2. Untagged game throws: what came out, and how often a wrist reading is far from usual
  3. Per session: hand-direction scatter, release-point scatter, strike rate
  4. Replay: strike rate if the funnel measured each throw against a fixed scatter instead of the player's own
  5. Deliberate vs accidental: one threshold on each gesture's own reading (hits on tagged throws, false
     alarms on ordinary ones)
  6. Seven-way nearest-centroid classifier on the wrist readings, leave-one-out (tagged throws)
  7. Game pitches far off the plate
  8. Command model replay: the logged aim readings through a candidate funnel (target, reference scatter,
     squeezed tails, spread), per session: in the zone, near the catcher's spot, far off the plate
  9. Grip pitches (Pitch choice: Grip): per grip, how often, its action, how much movement, and in words
  (Sections 1, 2, 5 and 6 are about the technique classifier and leave grip pitches out.)

    python tools/throw_report.py --command    # just section 8
"""
import collections, glob, json, math, os, random, statistics as st, sys

ZONE_HALF_W, ZONE_BOTTOM, ZONE_TOP, BALL_R = 0.30, 0.40, 1.30, 0.037
REF_SIGMA = (6.0, 5.5)            # degrees: the aim scatter every player starts from (HumanPitcher.aim_sigma)
TAGGED_PLAYER_A = ('2026-10-09T18-41', '2026-10-09T21-13', '2026-10-09T22-57')
# CatcherSigns: rows and columns of the called spots (metres), how near counts as hitting it.
SIGN_LOW, SIGN_MID, SIGN_HIGH, SIGN_IN_OUT, SIGN_NEAR = 0.55, 0.85, 1.15, 0.22, 0.30


def folder():
    if '--dir' in sys.argv:
        return sys.argv[sys.argv.index('--dir') + 1]
    return os.path.join(os.environ.get('APPDATA', ''), 'Godot', 'app_userdata', 'VR Baseball')


def load(pattern):
    out = []
    for f in sorted(glob.glob(os.path.join(folder(), pattern))):
        sess = os.path.basename(f).split('_', 1)[1][:16]
        for line in open(f, encoding='utf-8'):
            try:
                d = json.loads(line)
            except ValueError:
                continue
            d['_sess'] = sess
            out.append(d)
    return out


def sd(xs):
    return st.pstdev(xs) if len(xs) > 1 else 0.0


def is_strike(x, y):
    return abs(x) <= ZONE_HALF_W + BALL_R and ZONE_BOTTOM - BALL_R <= y <= ZONE_TOP + BALL_R


def freestyle(r):
    """A throw (or sign event) whose pitch name came from the technique classifier, not a chosen grip."""
    return r.get('pitch_select', r.get('select', 'Freestyle')) != 'Grip'


def untagged(r):
    return r.get('tag') in ('normal', '', None)


def features(r):
    w = r['wrist']
    usual = (w.get('baseline') or {}).get('speed') or 10.3
    return {'arc': w['z_snap'] + max(w.get('z_wind', 0.0), 0.0), 'side': w['z_side'], 'gyro': w['z_gyro'],
            'low': -w['z_slot'], 'slowness': 1.0 - r['raw']['speed'] / usual,
            'stiff': max(w.get('stiff', 0.0), w.get('push', 0.0))}


def main():
    throws = load('throws_*.jsonl')
    events = load('events_*.jsonl')
    print('%d throws, %d events' % (len(throws), len(events)))

    print('\n== 1. Catcher signs: called vs named ==')
    signs = [e for e in events if e.get('kind') == 'sign' and freestyle(e)]          # with grips the sign sets the grip
    print('signs %d, type matched %d, spot hit %d, both %d' % (len(signs), sum(bool(s.get('type')) for s in signs),
          sum(bool(s.get('loc')) for s in signs), sum(bool(s.get('perfect')) for s in signs)))
    by_call = collections.defaultdict(collections.Counter)
    for s in signs:
        by_call[s['sign'].split(',')[0]][s.get('thrown')] += 1
    for call, c in sorted(by_call.items(), key=lambda kv: -sum(kv[1].values())):
        print('  called %-10s n=%2d -> %s' % (call, sum(c.values()), dict(c.most_common())))

    print('\n== 2. Untagged game throws ==')
    game = [r for r in throws if 'game' in r and untagged(r) and 'wrist' in r and freestyle(r)]
    names = collections.Counter(r['pitch_name'] for r in game)
    print('n %d: %s' % (len(game), dict(names.most_common())))
    fb = names['Four-seam'] + names['Fastball']
    print('plain fastballs %.0f%%, unnamed ("Pitch") %.0f%%' % (100 * fb / len(game), 100 * names['Pitch'] / len(game)))
    for k in ('z_snap', 'z_side', 'z_gyro', 'z_slot', 'z_wind'):
        xs = [r['wrist'][k] for r in game if k in r['wrist']]
        print('  %-6s mean %+.2f sd %.2f  beyond 1.5 sd: %2.0f%%' % (k, st.mean(xs), sd(xs), 100 * sum(abs(x) > 1.5 for x in xs) / len(xs)))
    far = sum(1 for r in game if max(abs(r['wrist'][k]) for k in ('z_snap', 'z_side', 'z_gyro', 'z_slot')) > 1.5)
    print('  any of snap/side/gyro/slot beyond 1.5 sd: %.0f%%' % (100 * far / len(game)))

    print('\n== 3 and 4. Per session (untagged game throws with a funnel reading) ==')
    sessions = collections.defaultdict(list)
    for r in throws:
        f = r.get('funnel')
        if f and not f.get('fallback', True) and 'game' in r and untagged(r) and r['raw']['speed'] > 4:
            sessions[r['_sess']].append(r)
    print('session           n   aim sd az/el deg  release sd x/y m  strike%%  | replay strike%%, own scatter vs fixed %.0f/%.1f deg:' % REF_SIGMA)
    print('                                                                     |  spread 0.40/0.30 m      spread 0.60/0.48 m')
    cy = (ZONE_BOTTOM + ZONE_TOP) / 2
    for s, rs in sessions.items():
        if len(rs) < 15:
            continue
        res = []
        for sx, sy in ((0.40, 0.30), (0.60, 0.48)):
            for fixed in (False, True):
                k = 0
                for r in rs:
                    f = r['funnel']
                    sg = REF_SIGMA if fixed else f['sigma_before']
                    zx = max(-4.0, min(4.0, (f['az'] - f['mu_before'][0]) / sg[0]))
                    zy = max(-4.0, min(4.0, (f['el'] - f['mu_before'][1]) / sg[1]))
                    k += is_strike(zx * sx, cy + zy * sy)
                res.append(100 * k / len(rs))
        print('%s %4d   %4.1f / %4.1f       %.2f / %.2f       %3.0f%%   |  %3.0f%% vs %3.0f%%          %3.0f%% vs %3.0f%%' % (
            s, len(rs), sd([r['funnel']['az'] for r in rs]), sd([r['funnel']['el'] for r in rs]),
            sd([r['release_pos'][0] for r in rs]), sd([r['release_pos'][1] for r in rs]),
            100 * sum(bool(r['result'].get('strike')) for r in rs) / len(rs), *res))

    print('\n== 5. Deliberate vs accidental: a threshold on each gesture\'s own reading ==')
    tagged = [r for r in throws if not untagged(r) and 'wrist' in r and r['raw']['speed'] > 4 and r['_sess'] in TAGGED_PLAYER_A]
    normal = [r for r in throws if untagged(r) and 'wrist' in r and r['raw']['speed'] > 4 and freestyle(r)]
    gestures = {'big snap': 'arc', 'wrist twist': 'side', 'gyro roll': 'gyro', 'low arm': 'low'}
    for t in (1.0, 1.5, 2.0, 2.5):
        parts = []
        for g, k in gestures.items():
            rs = [r for r in tagged if r['tag'] == g]
            parts.append('%s caught %2.0f%% / false %2.0f%%' % (g, 100 * sum(features(r)[k] > t for r in rs) / max(1, len(rs)),
                                                             100 * sum(features(r)[k] > t for r in normal) / len(normal)))
        anyf = 100 * sum(any(features(r)[k] > t for k in gestures.values()) for r in normal) / len(normal)
        print('  T=%.1f sd  %s | ordinary throws called something: %.0f%%' % (t, '  '.join(parts), anyf))
    slow = [r for r in tagged if r['tag'] == 'slow']
    for th in (0.15, 0.25, 0.35):
        print('  slow: below %.0f%% of usual speed: caught %.0f%% / false %.0f%%' % (100 * (1 - th), 100 * sum(features(r)['slowness'] > th for r in slow) / max(1, len(slow)),
              100 * sum(features(r)['slowness'] > th for r in normal) / len(normal)))

    print('\n== 6. Seven-way classifier on the wrist readings (player A tagged, leave-one-out) ==')
    keys = ('arc', 'side', 'gyro', 'low', 'slowness', 'stiff')
    sample = [r for r in throws if r.get('tag') in ('normal', 'big snap', 'wrist twist', 'gyro roll', 'low arm', 'slow', 'stiff wrist')
              and 'wrist' in r and r['raw']['speed'] > 4 and r['_sess'] in TAGGED_PLAYER_A]
    X = [[features(r)[k] for k in keys] for r in sample]
    scale = [sd([x[i] for x in X]) or 1.0 for i in range(len(keys))]
    X = [[x[i] / scale[i] for i in range(len(keys))] for x in X]
    Y = [r['tag'] for r in sample]
    conf = collections.Counter()
    for i in range(len(sample)):
        cents = {}
        for t in set(Y):
            pts = [X[j] for j in range(len(sample)) if j != i and Y[j] == t]
            cents[t] = [st.mean(p[k] for p in pts) for k in range(len(keys))]
        conf[(Y[i], min(cents, key=lambda t: sum((X[i][k] - cents[t][k]) ** 2 for k in range(len(keys)))))] += 1
    tags = sorted(set(Y))
    print('  %-12s' % 'tag \\ called' + ''.join('%8s' % t[:7] for t in tags) + '   right')
    for t in tags:
        n = sum(conf[(t, u)] for u in tags)
        print('  %-12s' % t + ''.join('%8d' % conf[(t, u)] for u in tags) + '   %3.0f%%' % (100 * conf[(t, t)] / n))
    print('  overall %.0f%% (chance %.0f%%)' % (100 * sum(conf[(t, t)] for t in tags) / len(sample), 100 / len(tags)))

    print('\n== 7. Game pitches far off the plate ==')
    pe = [e for e in events if e.get('kind') == 'pitch']
    print('pitch events %d: %s' % (len(pe), dict(collections.Counter(e.get('outcome') for e in pe).most_common())))
    reached = [r for r in throws if 'game' in r and r['result'].get('reached') and r['result'].get('plate')]
    print('logged game throws more than 0.8 m to either side: %.1f%%' % (100 * sum(abs(r['result']['plate'][0]) > 0.8 for r in reached) / max(1, len(reached))))



def sign_cell(balls, strikes, outs, third_on, rng):
    """CatcherSigns.call_pitch's choice of spot (the pitch type does not matter here)."""
    no_dirt = third_on and outs < 2
    if balls >= 3:
        cell = rng.choice(['low-away', 'mid-away', 'middle'])
    elif strikes == 2 and not no_dirt:
        cell = 'chase-low-away' if rng.random() < 0.7 else 'chase-high'
    elif strikes > balls:
        cell = rng.choice(['low-away', 'low-in', 'mid-away'])
    elif balls > strikes:
        cell = rng.choice(['mid-away', 'mid-in', 'low-away', 'middle'])
    else:
        cell = rng.choice(['low-away', 'mid-away', 'high-in', 'low-in', 'mid-in'])
    if no_dirt and cell.startswith('low'):
        cell = 'mid-away'
    return cell


def cell_target(cell, side=1.0):
    """CatcherSigns.cell_target for a batter on `side` (+1 a right-hander)."""
    away, inside = -side * SIGN_IN_OUT, side * SIGN_IN_OUT
    table = {'low-away': (away, SIGN_LOW), 'low-in': (inside, SIGN_LOW), 'low-mid': (0.0, SIGN_LOW),
             'mid-away': (away, SIGN_MID), 'mid-in': (inside, SIGN_MID), 'middle': (0.0, SIGN_MID),
             'high-away': (away, SIGN_HIGH), 'high-in': (inside, SIGN_HIGH), 'high-mid': (0.0, SIGN_HIGH),
             'chase-low-away': (-side * 0.40, 0.30), 'chase-high': (0.0, 1.48), 'chase-away': (-side * 0.45, SIGN_MID)}
    return table.get(cell, (0.0, SIGN_MID))


def squeeze(z, knee):
    """Beyond `knee` sd a miss grows at 0.4 the rate (HumanPitcher.squeeze_miss)."""
    if knee <= 0 or abs(z) <= knee:
        return z
    return math.copysign(knee + 0.4 * (abs(z) - knee), z)


def replay_command(rs, glove, reference, spread, knee, seed=7):
    """Logged aim readings through one funnel. reference 0 = your own scatter, 1 = the fixed REF_SIGMA, between =
    geometric. Returns (in the zone, near the called spot, would hit a right-handed batter, plate sd x, plate sd y)."""
    rng = random.Random(seed)
    zone = near = far = 0
    xs, ys = [], []
    for r in rs:
        f, g = r['funnel'], r['game']
        cell = sign_cell(int(g.get('balls', 0)), int(g.get('strikes', 0)), int(g.get('outs', 0)), bool((g.get('bases') or [0, 0, 0])[2]), rng)
        cx, cy = cell_target(cell) if glove else (0.0, (ZONE_BOTTOM + ZONE_TOP) / 2)
        own = f['sigma_before']
        sig = [own[i] ** (1.0 - reference) * REF_SIGMA[i] ** reference for i in (0, 1)]
        zx = squeeze(max(-4.0, min(4.0, (f['az'] - f['mu_before'][0]) / sig[0])), knee)
        zy = squeeze(max(-4.0, min(4.0, (f['el'] - f['mu_before'][1]) / sig[1])), knee)
        x = max(-2.0, min(2.0, cx + zx * spread[0]))
        y = max(0.0, min(2.6, cy + zy * spread[1]))
        zone += is_strike(x, y)
        tx, ty = cell_target(cell)
        near += math.hypot(x - tx, y - ty) <= SIGN_NEAR
        far += 0.62 <= x <= 1.28 and 0.25 <= y <= 1.60     # at a right-handed batter's body (before he dodges)
        xs.append(x - cx)
        ys.append(y - cy)
    n = max(1, len(rs))
    return 100 * zone / n, 100 * near / n, 100 * far / n, sd(xs), sd(ys)


def command_section(throws):
    print('\n== 8. Command model replay (untagged game throws; the spot is what the catcher would have called) ==')
    sessions = collections.defaultdict(list)
    for r in throws:
        f = r.get('funnel')
        if f and not f.get('fallback', True) and 'game' in r and untagged(r) and r['raw']['speed'] > 4:
            sessions[r['_sess']].append(r)
    sessions = {s: rs for s, rs in sessions.items() if len(rs) >= 40}
    models = [
        ('shipped Standard: zone centre, own scatter, 0.40/0.30', False, 0.0, (0.40, 0.30), 0.0),
        ('shipped Pro:      zone centre, own scatter, 0.60/0.48', False, 0.0, (0.60, 0.48), 0.0),
        ('Casual now:   centre, own scatter, 0.28/0.20, knee 1.5', False, 0.0, (0.28, 0.20), 1.5),
        ('Standard now: glove, halfway,     0.30/0.24, knee 1.5', True, 0.5, (0.30, 0.24), 1.5),
        ('Pro now:      glove, fixed,       0.34/0.28, knee 1.5', True, 1.0, (0.34, 0.28), 1.5),
    ]
    names = sorted(sessions)
    print('  %-56s' % 'model' + ''.join('  %-22s' % n[5:] for n in names))
    print('  %-56s' % '' + ''.join('  %-22s' % 'zone/near/hbp%  sd x/y' for _ in names))
    for label, glove, ref, spread, knee in models:
        cells = []
        for n in names:
            z, nr, fa, sx, sy = replay_command(sessions[n], glove, ref, spread, knee)
            cells.append('%3.0f/%3.0f/%3.1f  %.2f/%.2f' % (z, nr, fa, sx, sy))
        every = [r for n in names for r in sessions[n]]
        z, nr, fa, sx, sy = replay_command(every, glove, ref, spread, knee)
        print('  %-56s' % label + ''.join('  %-22s' % c for c in cells) + '  all: %3.0f/%3.0f/%3.1f' % (z, nr, fa))
    print('  own aim scatter per session (deg): ' + ', '.join('%s %.1f/%.1f' % (n[5:], sd([r['funnel']['az'] for r in sessions[n]]), sd([r['funnel']['el'] for r in sessions[n]])) for n in names))


def grip_section(throws):
    print('\n== 9. Grip pitches ==')
    gp = [r for r in throws if r.get('grip')]
    if not gp:
        print('  none logged yet (Options > Pitch choice: Grip)')
        return
    by = collections.defaultdict(list)
    for r in gp:
        by[r['grip']['grip']].append(r['grip'])
    print('  %-12s %4s  %7s  %8s  %s' % ('grip', 'n', 'action', 'movement', 'quality'))
    for g, xs in sorted(by.items(), key=lambda kv: -len(kv[1])):
        q = collections.Counter(x['quality'] for x in xs)
        print('  %-12s %4d  %+7.2f  %7.0f%%  %s' % (g, len(xs), st.mean(x['action'] for x in xs), 100 * st.mean(x['movement'] for x in xs), dict(q.most_common())))


if __name__ == '__main__':
    if '--command' in sys.argv:
        command_section(load('throws_*.jsonl'))
    else:
        main()
        command_section(load('throws_*.jsonl'))
        grip_section(load('throws_*.jsonl'))
