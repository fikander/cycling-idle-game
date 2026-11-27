# Ultra Idle Cycling: design doc

Status: draft for the prototype, November 2026.

## Pitch

You're an ultra-distance cyclist on an endless road through cel-shaded landscapes. The game sits open in the corner of your screen while you do other things. Every few minutes you glance over and decide: shift gears, change cadence, eat, drink, stop at the next shop or ride on. Good decisions mean more kilometres. Kilometres buy better kit, and the rider gets fitter just by riding.

## Core loop

1. **Ride.** The rider holds your chosen gear and cadence. The road keeps changing under them: climbs, descents, heat at midday.
2. **Check in.** Something has drifted. You're grinding up a climb in too big a gear, the bottles are empty, or the glycogen bar is sliding toward a bonk. Fix it.
3. **Shop.** Shops come up every 25 to 45 km. Plan a stop to refill bottles and buy food. Later, buy upgrades.
4. **Get better.** Distance earns coins. Riding trains the body. Upgrades and training let you go further between check-ins, which is the real idle reward.

The tension: **riding harder is faster but burns carbs faster than the gut can replace them.** Pacing is the skill.

## Time

Game time runs 10x faster than real time (`time_scale`), so one real minute is ten game minutes and a 15-minute demo session is about 2.5 game hours, roughly 55 to 65 km.

The game is meant to be left open. No offline progress is planned for the prototype. If the window is closed, the ride pauses.

## Rider model

All numbers live in `config/tuning.json`. The simulation is `sim/rider_sim.gd`.

### Speed and power

Speed comes from cadence and gear: `speed = cadence × (chainring / cog) × wheel circumference`. The power needed to hold that speed comes from real cycling physics: rolling resistance, gravity on the slope, and air drag.

- If the rider has the power, they hold the speed.
- If not, they're **grinding**: they push as hard as they can and the cadence drops. Grinding is slow, burns carbs fast and tires the muscles.
- If the road drops away faster than the gear, they **coast** for free.

The rider can deliver up to `ftp × capacity × effort_cap` watts. Capacity is the rider's current condition, from 1.0 when fresh down to 0.15 when wrecked.

### Gears and cadence

The bike starts with a 34/50 chainring and an 11 to 32 cassette.

- **Cadence efficiency** peaks at about 88 rpm. Spinning faster or slower wastes energy and costs more carbs.
- **Torque**: big gear plus low cadence means high force per pedal stroke. That builds **muscle fatigue**, which recovers slowly.
- A gear that's right on the flat is wrong on the climb. This is why check-ins matter, and why the auto-shift upgrade is valuable.

### Carbs (glycogen)

- Glycogen store: 450 g, starting at 430 g.
- Burn rate depends on power and on what share comes from carbs vs fat. Easy riding is mostly fat. Hard riding is mostly carbs. At about 55 % of FTP the rider burns roughly what the gut can absorb (about 50 to 60 g per hour). Ride harder and you're running a deficit.
- Food goes into the **gut** first and is absorbed at 60 g per hour, more as the gut trains. Eating more than the gut holds (90 g) gives a 10 % penalty, so you can't just eat everything at once.
- Below 15 % glycogen the rider **bonks** and capacity falls toward 50 %.

| Food | Carbs | Price |
|---|---|---|
| Gel | 25 g | 6 |
| Bar | 40 g | 8 |
| Banana | 27 g | 4 |
| Rice cake | 35 g | 5 |

The rider starts with 4 pocket slots.

### Water

- Sweat rate rises with power and with temperature above 16 °C. Temperature follows the time of day (peak mid-afternoon) and the biome (mountains are cooler, coast is warmer).
- Two 0.75 L bottles to start. Each drink is a 150 ml sip.
- Up to 1.5 % body-weight water loss is free. Beyond that capacity drops 7 % per percent. At 6 % the rider **collapses** and rests for 2 game hours.

### Fatigue

- **General fatigue** builds with intensity (steeply, `intensity^2.5`) and recovers when riding easy or resting. At 100 the rider collapses from exhaustion.
- **Muscle fatigue** builds from high torque (grinding, wrong gears) and recovers when the legs spin easily.
- Both reduce capacity.

## Progression

### Training: the rider gets better by riding

Each stat gains XP from the matching activity. Level is `floor(sqrt(xp / 0.5))`, so early levels come quickly and later ones slow down.

| Stat | Trained by | Effect per level |
|---|---|---|
| Endurance | Time spent above 50 % FTP | +2 % FTP |
| Stamina | Time on the bike | −4 % general fatigue build-up |
| Strength | Riding under high torque | −5 % muscle fatigue build-up |
| Gut | Carbs absorbed | +4 g per hour absorption |
| Cooling | Sweating in the heat | −3 % sweat rate |

### Shops and upgrades (step 2)

Shops sell food and refill water for free. Planned upgrades, roughly in unlock order:

- **Kit:** saddle bag (+pocket slots), third bottle cage, bigger bottles, aero bars (lower CdA), lighter wheels, better tyres (lower Crr), wider-range cassette.
- **Automation (the idle upgrades):** auto-drink, auto-eat, electronic auto-shift, "stop at shop when low". These let you check in less often without losing distance, which is what makes an idle game feel rewarding.
- **Consumables:** drink mix (carbs in the bottle), salt tabs, caffeine gel (short-term capacity boost).

### Landscapes

The road runs in 80 km segments, each in one biome, blended at the borders:

| Biome | Terrain | Notes |
|---|---|---|
| Fields | Flat | The first segment is always fields |
| Hills | Rolling, short steep climbs | More coins per km |
| Coast | Gentle, warm | Thirstier |
| Mountains | Long climbs, cool | Most coins per km |

The road is generated from a seed, so it's the same every time and the renderer can draw exactly what the simulation rides.

## Demo and paid content (step 3)

- The free demo ends after about 15 minutes of play, around the second shop. That gives enough time to feel a bonk, a shop stop and a level-up.
- Paid content (more biomes, shop tiers, the automation upgrades) ships as a **separate Godot content pack (.pck)** that is only downloaded after purchase. The free build doesn't contain it, so there's nothing in it to unlock by hacking.
- For real protection the pack has to be served by a small server that checks the store receipt (Apple, Google, Steam) before handing out a signed, short-lived download link. The Vercel project could host this. In the prototype the purchase is a stub.

## What the first pacing run shows

`docs/pacing_baseline.txt` holds the output of `tools/simulate.gd`. It simulates players with different check-in habits for 2 real hours.

| Player | km after 15 min | km after 2 h | Time bonked |
|---|---|---|---|
| Never checks in | 63 | 290 | 53 %, plus 2 collapses |
| Every 5 min | 56 | 362 | 36 % |
| Every 20 min | 63 | 339 | 71 % |
| Every 20 min with all automation | 65 | 374 | 47 % |

What this tells us:

- **Paying attention pays off** after the first half hour, by about 25 % over 2 hours. Early on, an attentive player is slightly slower because they ride at a sensible pace instead of at the starting gear. We want the first 15 minutes to reward attention too, probably through a fresher start, a visible early climb and an early cheap upgrade.
- **Food supply becomes the limit after about 1 real hour.** With only 4 pocket slots even careful players run dry between shops. This is good. It makes the first upgrade (the saddle bag) feel essential.
- **Muscle fatigue builds up for anyone without auto-shift**, because the gear set at the last check-in is wrong for the next climb. This makes auto-shift a strong mid-game upgrade. It may be too punishing and needs tuning.
- Nobody sleeps yet. Real ultra riders do, and a sleep mechanic could be a nice "come back later" moment.

## Open questions

1. Should the rider eat and drink a little on their own when unattended, so a forgotten game doesn't end in a collapse?
2. Should there be a separate **effort** control (easy, steady, hard) as well as cadence and gears? It would be clearer for casual players.
3. Should progress continue while the app is closed (classic idle), or is "the window must stay open" fine?
4. How long is the paid game? One long ride across a continent with an end, or endless?

## Code layout

```
config/tuning.json    all balance numbers
sim/bike_physics.gd   power, speed, gears (pure functions)
sim/terrain.gd        seeded endless road, biomes, temperature, shops
sim/rider_sim.gd      the full game state and step(dt), save/load
tools/simulate.gd     headless pacing simulation
tests/run_tests.gd    unit tests
```
