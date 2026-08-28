############################################################
## 0. Libraries
############################################################

library(readxl)
library(dplyr)
library(tidyr)
library(writexl)
library(ggplot2)
library(scales)
library(knitr)

############################################################
## 1. Read & rename the Excel data
############################################################

df <- read_excel("Bayes Project Data.xlsx", sheet = 1)

# Give clear column names (15 columns total)
names(df) <- c(
  "Year", "Employed", "Unemployed", "UnempRate", "Population",
  "RealGDPGrowth",
  "Tax_R0_70001", "Tax_70k_350k", "Tax_350k_500k", "Tax_500k_plus",
  "Extra_col",      # column 11 we don't really use
  "Pop_R0_70001", "Pop_70k_350k", "Pop_350k_500k", "Pop_500k_plus"
)

############################################################
## 2. Basic cleaning: make sure numeric columns are numeric
############################################################

percent_cols <- c(
  "Tax_R0_70001", "Tax_70k_350k", "Tax_350k_500k", "Tax_500k_plus",
  "Pop_R0_70001", "Pop_70k_350k", "Pop_350k_500k", "Pop_500k_plus"
)

df <- df %>%
  mutate(
    across(
      c(Employed, Unemployed, UnempRate, Population, RealGDPGrowth,
        all_of(percent_cols)),
      as.numeric
    )
  )

# If the percent columns are stored as whole percents (e.g. 63.5, not 0.635),
# uncomment the next block once. If they are already proportions, leave this off.
# df <- df %>%
#   mutate(
#     across(all_of(percent_cols), ~ .x / 100)
#   )

############################################################
## 3. Impute missing Pop% by bracket using Tax% and Year
############################################################

pop_share_cols <- c("Pop_R0_70001", "Pop_70k_350k", "Pop_350k_500k", "Pop_500k_plus")

# Years with observed population shares (2013–2025)
known   <- df %>% filter(!is.na(Pop_R0_70001))
# Years with missing population shares (1994–2012)
missing <- df %>% filter(is.na(Pop_R0_70001))

nrow(known)   # should be 13
nrow(missing) # should be 19

## 3a. Fit models: Pop% = f(Year, TaxPaid%) for each bracket

tax_cols <- c("Tax_R0_70001", "Tax_70k_350k", "Tax_350k_500k", "Tax_500k_plus")
names(tax_cols) <- pop_share_cols  # map Pop% col -> Tax% col

models <- lapply(pop_share_cols, function(pop_col) {
  tax_col <- tax_cols[[pop_col]]
  form <- as.formula(paste(pop_col, "~ Year +", tax_col))
  lm(form, data = known)
})
names(models) <- pop_share_cols

# Optional: look at one model
# summary(models$Pop_70k_350k)

## 3b. Predict Pop% for missing years, enforce floors & renormalize

# Small "floor" to avoid exact 0 for any bracket
min_obs <- known %>%
  summarise(across(all_of(pop_share_cols), \(x) min(x, na.rm = TRUE)))

pred_missing <- missing

for (pop_col in pop_share_cols) {
  tax_col <- tax_cols[[pop_col]]
  
  # Linear prediction
  pred <- predict(models[[pop_col]], newdata = missing)
  
  # Floor based on smallest observed value
  floor_val <- as.numeric(min_obs[[pop_col]]) * 0.5  # half of min observed
  floor_val <- max(floor_val, 0.0005)               # at least 0.05%
  
  pred <- pmax(pred, floor_val)
  pred <- pmin(pred, 1)  # cap at 100% (as proportion)
  
  pred_missing[[pop_col]] <- pred
}

# Renormalize so Pop% across 4 brackets sums to 1 for each year
pred_missing <- pred_missing %>%
  rowwise() %>%
  mutate(
    total_pop_share = sum(c_across(all_of(pop_share_cols))),
    across(all_of(pop_share_cols), ~ .x / total_pop_share)
  ) %>%
  ungroup()

############################################################
## 4. Combine known + imputed and save if you want
############################################################

df_filled <- known %>%
  bind_rows(pred_missing) %>%
  arrange(Year)

############################################################
## 5. Define income groups: Lower / Middle / Upper
############################################################

df_filled <- df_filled %>%
  mutate(
    Lower_pct  = Pop_R0_70001,
    Middle_pct = Pop_70k_350k,
    Upper_pct  = Pop_350k_500k + Pop_500k_plus
  )

# Convert to counts (people in each group)
df_filled <- df_filled %>%
  mutate(
    Lower_total  = Population * Lower_pct,
    Middle_total = Population * Middle_pct,
    Upper_total  = Population * Upper_pct
  )

############################################################
## 6. Frequentist-style visualizations (shares & totals)
############################################################

# Area plot of shares over time
df_plot <- df_filled %>%
  select(Year, Lower_pct, Middle_pct, Upper_pct) %>%
  pivot_longer(cols = -Year, names_to = "Group", values_to = "Share")

ggplot(df_plot, aes(x = Year, y = Share, fill = Group)) +
  geom_area(alpha = 0.85) +
  scale_fill_manual(
    values = c(
      Lower_pct  = "#ff9d76",
      Middle_pct = "#6ca0dd",
      Upper_pct  = "#c37aff"
    ),
    labels = c("Lower Income", "Middle Income", "Upper Income")
  ) +
  scale_y_continuous(labels = scales::percent_format()) +
  labs(
    title = "Income Distribution in South Africa (1994–2025)",
    y = "Population Share",
    x = "Year",
    fill = "Income Group"
  ) +
  theme_minimal(base_size = 14)

# Line plot: middle-class share over time
ggplot(df_filled, aes(x = Year, y = Middle_pct)) +
  geom_line(linewidth = 1.3, color = "#1f78b4") +
  geom_point(size = 2) +
  scale_y_continuous(labels = scales::percent_format()) +
  labs(
    title = "Middle Income Population Share (1994–2025)",
    y = "Middle Class (%)",
    x = "Year"
  ) +
  theme_minimal(base_size = 14)

# Line plot: number of people in each group
df_totals <- df_filled %>%
  select(Year, Lower_total, Middle_total, Upper_total) %>%
  pivot_longer(cols = -Year, names_to = "Group", values_to = "Total")

ggplot(df_totals, aes(x = Year, y = Total, color = Group)) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 2) +
  scale_y_continuous(labels = scales::comma) +
  scale_color_manual(
    values = c(
      Lower_total  = "#ff9d76",
      Middle_total = "#6ca0dd",
      Upper_total  = "#c37aff"
    ),
    labels = c("Lower Income", "Middle Income", "Upper Income")
  ) +
  labs(
    title = "Population by Income Group (Total People)",
    y = "Population (people)",
    x = "Year",
    color = "Income Group"
  ) +
  theme_minimal(base_size = 14)

# Stacked bar chart of shares
ggplot(df_plot, aes(x = factor(Year), y = Share, fill = Group)) +
  geom_bar(stat = "identity") +
  scale_y_continuous(labels = scales::percent) +
  scale_fill_manual(
    values = c(
      Lower_pct  = "#ff9d76",
      Middle_pct = "#6ca0dd",
      Upper_pct  = "#c37aff"
    )
  ) +
  labs(
    title = "Income Distribution (Stacked Bar)",
    x = "Year",
    y = "Share"
  ) +
  theme_minimal(base_size = 12) +
  theme(axis.text.x = element_text(angle = 90, vjust = 0.5))

############################################################
# 7. Bayesian model for the middle-income share
# BAYESIAN MIDDLE-INCOME SHARE: Beta(11, 9) PRIOR
# Uses an effective sample size so the prior has weight
# df_filled is assumed to already exist from our pipeline
# and to contain Middle_pct as a proportion (0–1).
############################################################
# --- 1. Set prior and effective sample size ----

prior_alpha <- 11   # Beta(11, 9)
prior_beta  <- 9
prior_n     <- prior_alpha + prior_beta   # = 20 pseudo-observations

n_eff <- 80  # effective sample size per year
#   Prior weight  = prior_n / (prior_n + n_eff)
#   Data weight   = n_eff   / (prior_n + n_eff)
#   With n_eff = 80, prior weight = 20%, data = 80%.

# --- 2. Build posterior for each year ----

middle_bayes <- df_filled %>%
  transmute(
    Year,
    mid_share = Middle_pct   # already in [0, 1]
  ) %>%
  mutate(
    # effective binomial "data"
    k       = round(mid_share * n_eff),    # middle-income "successes"
    n       = n_eff,                       # effective sample size
    
    # posterior parameters
    post_alpha = prior_alpha + k,
    post_beta  = prior_beta  + (n - k),
    
    # posterior summaries
    mean = post_alpha / (post_alpha + post_beta),
    l80  = qbeta(0.10, post_alpha, post_beta),
    u80  = qbeta(0.90, post_alpha, post_beta),
    l95  = qbeta(0.025, post_alpha, post_beta),
    u95  = qbeta(0.975, post_alpha, post_beta)
  )

# --- 3. Build comparison data (Bayes vs frequentist imputed line) ----
# frequentist line = the Middle_pct series we already have in df_filled

compare_mid <- df_filled %>%
  select(Year, freq_imputed = Middle_pct) %>%
  left_join(
    middle_bayes %>%
      select(Year, mean, l80, u80, l95, u95),
    by = "Year"
  )

# --- 4. Plot: Posterior mean & credible intervals vs frequentist series ----

ggplot(compare_mid, aes(x = Year)) +
  # 95% credible interval
  geom_ribbon(aes(ymin = l95, ymax = u95),
              fill = "#cce5ff", alpha = 0.4) +
  # 80% credible interval
  geom_ribbon(aes(ymin = l80, ymax = u80),
              fill = "#66a9ff", alpha = 0.4) +
  # Posterior mean
  geom_line(aes(y = mean, color = "Bayesian posterior mean"),
            linewidth = 1.2) +
  # Frequentist imputed middle share
  geom_line(aes(y = freq_imputed,
                color = "Linear-model imputed share"),
            linewidth = 1.1, linetype = "dashed") +
  scale_y_continuous(labels = scales::percent_format()) +
  scale_colour_manual(
    name   = NULL,
    values = c(
      "Bayesian posterior mean"     = "#003399",
      "Linear-model imputed share"  = "#ff7700"
    )
  ) +
  labs(
    title    = "Middle-income Share: Bayesian vs Frequentist Estimates",
    subtitle = paste0(
      "Prior: Beta(11, 9) with mean 0.55 and effective n = ",
      n_eff, " per year"
    ),
    x = "Year",
    y = "Middle-income share of population"
  ) +
  theme_minimal(base_size = 14)

# Combine Bayesian and frequentist results into one table
results <- compare_mid %>%
  select(Year, mean, l80, u80, l95, u95, freq_imputed)

# Compute differences
results <- results %>%
  mutate(
    diff = mean - freq_imputed,             # Bayesian - Frequentist
    abs_diff = abs(mean - freq_imputed)     # absolute difference
  )

# View results
print(results, n = 32)

# Step 2a: overall agreement between Bayesian and frequentist series
summary_diffs <- results %>%
  summarise(
    avg_abs_diff   = mean(abs_diff),
    max_abs_diff   = max(abs_diff),
    year_max_diff  = Year[which.max(abs_diff)],
    min_abs_diff   = min(abs_diff),
    year_min_diff  = Year[which.min(abs_diff)]
  )

print(summary_diffs)

summary_periods <- results %>%
  mutate(period = ifelse(Year <= 2012, "1994–2012 (imputed years)",
                         "2013–2025 (observed years)")) %>%
  group_by(period) %>%
  summarise(
    mean_middle_share = mean(mean),
    avg_abs_diff      = mean(abs_diff)
  )

print(summary_periods)

key_years <- results %>%
  filter(Year %in% c(1994, 2000, 2010, 2020, 2025)) %>%
  select(Year, mean, l95, u95, freq_imputed, diff)

print(key_years)

kable(
  results %>% 
    select(Year, 
           Bayesian_Mean = mean,
           CI95_Lower = l95,
           CI95_Upper = u95,
           Frequentist = freq_imputed,
           Difference = diff),
  digits = 3,
  caption = "Bayesian vs Frequentist Estimates of Middle-Income Share (1994–2025)"
)

