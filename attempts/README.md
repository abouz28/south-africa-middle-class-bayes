# Development history

Three approaches tried before the final method in `../analysis.R`. They are kept
because the choice of what to impute, and how, is the main judgment call in this
project, and these show the alternatives that were tested and set aside.

Run them from inside this directory; the file paths are relative to it.

```r
setwd("attempts")
source("Attempt 3.R")
```

Attempts 1 and 2 emit `NAs introduced by coercion` warnings. These are real and
expected: both read `Data to feed into our model.xlsx` with `col_names = FALSE` and
coerce every column to numeric, so any non-numeric cell in that older spreadsheet
becomes `NA`. The scripts still complete. This is left as-is rather than patched,
since these are archived dead ends and the warning is accurately reporting a
limitation of the input they were written against.

## Attempt 1: impute the tax-paid shares

Reads `Data to feed into our model.xlsx`. Fits `tax share ~ Year + UnempRate` on the
observed years and back-casts the missing ones, pinning the lowest bracket to zero and
renormalizing.

Set aside because it imputes the wrong quantity. The share of tax *paid* by a bracket
is not the share of *people* in it, and the project needs the latter. The lowest
bracket pays almost no tax by construction, so this method carries no information
about the largest group in the population.

## Attempt 2: Attempt 1 plus a wider middle class

Same imputation as Attempt 1, then converts shares to head counts using the employed
population and defines the middle class as `R70k-350k` **plus** `R350k-500k`.

Set aside for the same reason as Attempt 1, but note the definition difference: the
final analysis treats `R350k-500k` as upper income, not middle. This attempt also
scales by `Employed` rather than `Population`, which excludes the unemployed from the
denominator entirely. In a country with unemployment as high as South Africa's, that
choice moves the answer substantially.

## Attempt 3: quadratic year trend

Reads `Bayes Project Data.xlsx` and switches to imputing the population shares
directly, which is the right target. Fits `population share ~ poly(Year, 2)`.

Set aside because the quadratic is fit on only 13 observed years and then extrapolated
19 years backwards, where a second-order term diverges fast and has no economic
justification. The final method regresses on `Year + tax-paid share` instead, so the
back-cast is anchored to a real observed covariate rather than to curvature in the
trend line.

## What the final version does

`../analysis.R` keeps Attempt 3's target, the population shares, but replaces the
quadratic year trend with `Year + tax-paid share`, so the back-cast is anchored to an
observed covariate rather than to curvature in a fitted line. It then adds the
Beta-Binomial layer that turns each yearly point estimate into a posterior with
credible intervals.

There was a fourth intermediate script that reached this same frequentist
specification without the Bayesian layer. It is not kept here, because `analysis.R`
reproduces it in full.
