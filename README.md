# Estimating South Africa's Middle-Income Population Share, 1994-2025

A Bayesian reconstruction of how South Africa's middle class has changed since the 1994
transition to democracy, combining income-tax-bracket aggregates from the South African
Revenue Service (SARS) with survey-based population data.

Written in R. Everything here is closed-form, so the full analysis runs in seconds with
no sampler and no convergence diagnostics.

## The problem

Population-by-income-bracket shares are only published for **2013-2025**. The 19 years
from **1994-2012**, the period spanning both the post-apartheid economic expansion and
the post-2008 stagnation, have no direct measurement. The two available data sources
pull in opposite directions: SARS tax-bracket data is precise but has no
individual-level context, while self-reported survey income is detailed but noisy.

The goal is to synthesize them into one coherent time series of middle-class size, with
an honest statement of how uncertain each year's estimate is.

## Approach

**1. Frequentist imputation (baseline).** For each of the four income brackets, a linear
model `population share ~ Year + tax-paid share` is fit on the 13 observed years
(2013-2025) and used to back-cast 1994-2012. Predictions are floored to avoid degenerate
zero-share brackets, then renormalized per year so the four brackets sum to 1.

**2. Conjugate Beta-Binomial update.** The middle-income share is modeled with a
`Beta(11, 9)` prior (mean 0.55, worth 20 pseudo-observations), reflecting the historical
expectation that roughly 55% of the population sits in the middle bracket. Each year's
imputed share is treated as a binomial observation with effective sample size
`n_eff = 80`, so the prior carries about 20% of the weight and the data about 80%:

```
k          = round(share * n_eff)
posterior  = Beta(11 + k, 9 + (n_eff - k))
```

Conjugacy makes the posterior analytic, so posterior means and 80% / 95% credible
intervals fall out directly for all 32 years, with no sampling required.

**3. Comparison.** Bayesian posterior means are benchmarked year by year against the
frequentist point estimates, to see where the prior matters and where it washes out.

## Results

| | 1994 | 2025 |
|---|---|---|
| Posterior mean | 0.771 | 0.49 |
| 95% credible interval | 0.683 to 0.847 | 0.393 to 0.587 |

- The middle-income share **declines steadily** across the period, with the drop
  concentrated after the mid-2000s.
- Across the reconstructed years (1994-2012) the two approaches differ by **4.4
  percentage points** on average, peaking at 5.7 pp in 1995. The frequentist linear model
  systematically *overestimates* the early-period share.
- After 2013, where real data exists, the gap narrows to **1.2 pp**, smallest in 2018 at
  0.2 pp, as the likelihood overwhelms the prior. That is the behaviour you want: the
  prior does work where the data is thin and gets out of the way where it isn't.
- Mean middle-income share by era: **0.728** across the imputed years, **0.551** across
  the observed years.
- Credible intervals are widest in the early years, making the cost of reconstruction
  explicit in a way the frequentist point estimates cannot.

Both statistical philosophies tell the same story. The Bayesian version tells it with the
uncertainty attached.

![Middle-income share over time](figures/Middle%20Income%20Population%20Share.png)

## Repository layout

```
analysis.R                  main analysis, start here
data/
  raw/                      source spreadsheets, never modified by any script
  processed/                imputed datasets and the final presented figures
figures/                    generated charts
attempts/                   three approaches tried and set aside, with a note on why
```

| Path | Description |
|---|---|
| `analysis.R` | **Main analysis.** Full pipeline: load, clean, impute, define income groups, plot, Beta-Binomial model, comparison table |
| `data/raw/Bayes Project Data.xlsx` | **Primary input.** Year, employment, population, real GDP growth, tax-paid shares, population shares by bracket |
| `data/raw/Data to feed into our model.xlsx` | Earlier input, read only by the scripts in `attempts/` |
| `data/processed/Bayes Project Data Final.xlsx` | The final numbers as presented, carrying the derived columns built on top of the primary input |
| `data/processed/Bayes_Project3.xlsx` | Imputed dataset written by the frequentist stage of `analysis.R`'s method |
| `data/processed/Bayes_Project2.xlsx`, `data_with_imputed_tax_shares2.xlsx`, `Bayes_Project_with_imputed_shares_and_middle_class.xlsx` | Outputs from the archived attempts, kept so results are browsable without running R |
| `figures/*.png` | Generated charts |
| `attempts/` | Superseded approaches. See `attempts/README.md` |

## Running it

```r
# from the repository root
source("analysis.R")
```

All paths in `analysis.R` are relative to the repository root. The scripts in
`attempts/` are relative to `attempts/`, so run those from inside that directory.

Requires: `readxl`, `dplyr`, `tidyr`, `writexl`, `ggplot2`, `scales`, `knitr`.

Runs clean with no warnings on current `dplyr` and `ggplot2`.

## Scope and future work

The model implemented here applies an analytic conjugate Beta-Binomial update to each
year independently. Conjugacy is what makes it fast and fully reproducible: every
posterior mean and credible interval is a closed-form expression.

The project was originally scoped around something larger, a *dynamic hierarchical*
model that pools information across years through a Markov-chain time link, fit by MCMC.
That version is not implemented here. The practical difference: this model treats each
year independently, so it smooths toward the prior rather than toward neighbouring
years, and year-to-year volatility in the imputed series passes through undamped.

Extending to the dynamic hierarchical specification (pooled year-over-year structure
with a random-walk prior on the middle-income share, fit in Stan) is the natural next
step, and would tighten the early-period intervals that currently lean hardest on the
prior.

## Attribution

This was a two-person project for a Bayesian Analysis course. This repository contains
the modeling and R implementation, which was my half of the work. The presentation
materials prepared by my project partner are not included here.
