#!/usr/bin/env python3
"""Reproducible *synthetic* food-waste-risk training examples for PantryPulse.

This creates scenario-based labels, NOT observed food-waste events or empirical probabilities.
Requires Python 3 standard library only.
"""
from __future__ import annotations
import csv, math, random
from collections import Counter
from pathlib import Path

SEED = 20261022
TARGET_PER_LABEL = 400
CATEGORIES = {
    # category: (plausible storage locations, (quantity unit, typical unit-specific quantity ranges))
    'Fruits': (('Fridge', 'Pantry'), [('pieces',(1,12)), ('kg',(0.2,3.0))]),
    'Vegetables': (('Fridge','Pantry','Freezer'), [('pieces',(1,10)),('kg',(0.15,3.0))]),
    'Dairy': (('Fridge','Freezer'), [('L',(0.25,2.0)),('ml',(150,1000)),('g',(100,1000))]),
    'Meat & Seafood': (('Fridge','Freezer'), [('kg',(0.2,2.0)),('g',(150,1200))]),
    'Bakery': (('Pantry','Fridge','Freezer'), [('packs',(1,4)),('pieces',(1,12)),('g',(100,800))]),
    'Grains & Pantry': (('Pantry','Fridge'), [('kg',(0.25,5.0)),('g',(100,1000)),('packs',(1,4))]),
    'Beverages': (('Pantry','Fridge'), [('L',(0.33,3.0)),('ml',(200,1500)),('packs',(1,6))]),
    'Other': (('Pantry','Fridge','Freezer'), [('packs',(1,5)),('pieces',(1,8)),('g',(100,900))]),
}
CAT_ADJ = {
    'Fruits': 0.19, 'Vegetables': 0.22, 'Dairy': 0.27,
    'Meat & Seafood': 0.33, 'Bakery': 0.27,
    'Grains & Pantry': -0.20, 'Beverages': -0.12, 'Other': 0.02,
}
HEADERS = ['category','storageType','daysUntilExpiry','quantityValue','quantityUnit','historyEventCount','historicalWasteRate','riskLabel']

def sample(rng: random.Random) -> dict:
    cat = rng.choice(list(CATEGORIES))
    stores, unit_options = CATEGORIES[cat]
    storage = rng.choice(stores)
    unit, (lo, hi) = rng.choice(unit_options)
    qty = rng.uniform(lo,hi)
    if unit in ('pieces','packs'):
        qty = int(round(qty))
        qty = max(1, qty)
    else:
        qty = round(qty, 2)
    # Vary by more than just the day threshold; include boundary cases.
    days = rng.choice([0,1,2,3,4,5,6,7,10,14,21,30,45,60,90,120]) if rng.random()<0.53 else rng.randint(0, 120)
    # History=0 represents cold start, and exactly zero reported waste rate then means *unknown*.
    events = 0 if rng.random() < 0.24 else rng.randint(1, 30)
    if events == 0:
        waste_count, waste_rate = 0, 0.0
    else:
        # This is hypothetical event frequency, not a measured household rate.
        p = rng.betavariate(1.7, 5.2)
        waste_count = sum(rng.random() < p for _ in range(events))
        waste_rate = round(waste_count / events, 4)
    # Relative quantity ratio is unit-specific; do not directly compare g, L, pieces.
    typical = (lo + hi) / 2
    quantity_ratio = qty / typical
    # Expert-inspired *illustrative*, non-empirical scoring rules.
    if days <= 1: expiry_score = 1.98
    elif days <= 3: expiry_score = 1.25
    elif days <= 6: expiry_score = 0.68
    elif days <= 14: expiry_score = 0.14
    elif days <= 30: expiry_score = -0.42
    else: expiry_score = -1.05
    storage_adj = {'Freezer':-0.55, 'Fridge':-0.04, 'Pantry':0.10}[storage]
    quantity_adj = 0.42 * max(-0.8, min(0.8, math.log(max(0.08,quantity_ratio))))
    history_adj = 0 if events==0 else 0.90*(waste_rate - 0.18)*min(1.0,events/10)
    # Noise makes synthetic labels imperfect and avoids pure cut-off memorisation.
    score = expiry_score + CAT_ADJ[cat] + storage_adj + quantity_adj + history_adj + rng.gauss(0,0.25)
    label = 'High' if score > 1.27 else 'Low' if score < -0.02 else 'Medium'
    return {
        'category':cat,'storageType':storage,'daysUntilExpiry':days,
        'quantityValue': f'{float(qty):.2f}', 'quantityUnit':unit,
        'historyEventCount':events,'historicalWasteRate':f'{waste_rate:.4f}',
        'riskLabel':label,
    }

def main() -> None:
    rng = random.Random(SEED)
    buckets = {lab:[] for lab in ('Low','Medium','High')}
    signatures = set()
    iterations=0
    while any(len(buckets[lab])<TARGET_PER_LABEL for lab in buckets):
        iterations+=1
        if iterations>250000:
            raise RuntimeError('Sampler could not complete the requested class balance')
        row = sample(rng)
        label=row['riskLabel']
        if len(buckets[label]) >= TARGET_PER_LABEL:
            continue
        signature=tuple(row[k] for k in HEADERS[:-1])
        if signature in signatures:
            continue
        signatures.add(signature)
        buckets[label].append(row)
    # Per-class splitting preserves 1/3 distribution in each set.
    split_rows={k:[] for k in ('train','validation','test')}
    for label,rows in buckets.items():
        rng.shuffle(rows)
        split_rows['train'].extend(rows[:280])
        split_rows['validation'].extend(rows[280:340])
        split_rows['test'].extend(rows[340:400])
    outdir=Path(__file__).resolve().parent/'datasets'
    outdir.mkdir(exist_ok=True)
    for split,rows in split_rows.items():
        rng.shuffle(rows)
        with (outdir/f'{split}.csv').open('w', newline='', encoding='utf-8') as f:
            writer=csv.DictWriter(f, fieldnames=HEADERS)
            writer.writeheader()
            writer.writerows(rows)
        print(f'{split}: {len(rows)} rows; class counts {dict(Counter(r["riskLabel"] for r in rows))}')
    print(f'Total: {sum(map(len, split_rows.values()))}; seed={SEED}')

if __name__=='__main__':
    main()
