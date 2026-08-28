library(readxl)
library(dplyr)
library(writexl)

df <- read_excel("../Data to feed into our model.xlsx", col_names = FALSE)

names(df) <- c(
  "Year", "Employed", "Unemployed", "UnempRate",
  "Population", "RealGDPGrowth",
  "Tax_R0_70001", "Tax_70k_350k",
  "Tax_350k_500k", "Tax_500k_plus"
)

# Then drop the label row
df <- df[-1, ]

# Make sure numeric columns are actually numeric
share_cols <- c("Tax_R0_70001", "Tax_70k_350k", "Tax_350k_500k", "Tax_500k_plus")

df <- df %>%
  mutate(
    across(
      c(Employed, Unemployed, UnempRate, Population, RealGDPGrowth, all_of(share_cols)),
      as.numeric
    )
  )

# If shares are in % form (e.g., 59.12), convert to proportions (0.5912)
df <- df %>%
  mutate(
    across(
      all_of(share_cols),
      ~ ifelse(!is.na(.) & . > 1, . / 100, .)
    )
  )

## 2. Split into known vs missing tax-share years ----
# (Assuming 2013–2025 have real values, 1994–2012 are NA)
known   <- df %>% filter(!is.na(Tax_70k_350k))
missing <- df %>% filter(is.na(Tax_70k_350k))

## 3. Fit linear models: share ~ Year + UnempRate ----
m_mid   <- lm(Tax_70k_350k   ~ Year + UnempRate, data = known)
m_upper <- lm(Tax_350k_500k  ~ Year + UnempRate, data = known)
m_top   <- lm(Tax_500k_plus  ~ Year + UnempRate, data = known)

summary(m_mid)
summary(m_upper)
summary(m_top)

## 4. Predict missing shares (for 1994–2012) ----
pred_missing <- missing %>%
  mutate(
    # Keep lowest bracket at 0 if that's what you observe in known years
    Tax_R0_70001 = 0,
    
    # Raw predictions from the models
    Tax_70k_350k   = predict(m_mid,   newdata = missing),
    Tax_350k_500k  = predict(m_upper, newdata = missing),
    Tax_500k_plus  = predict(m_top,   newdata = missing)
  ) %>%
  # Enforce non-negative shares
  mutate(
    Tax_70k_350k   = pmax(Tax_70k_350k,   0),
    Tax_350k_500k  = pmax(Tax_350k_500k,  0),
    Tax_500k_plus  = pmax(Tax_500k_plus,  0)
  ) %>%
  # Rescale within each year so all four shares sum to 1
  rowwise() %>%
  mutate(
    total_share = Tax_R0_70001 + Tax_70k_350k + Tax_350k_500k + Tax_500k_plus,
    Tax_R0_70001 = Tax_R0_70001 / total_share,
    Tax_70k_350k = Tax_70k_350k / total_share,
    Tax_350k_500k = Tax_350k_500k / total_share,
    Tax_500k_plus = Tax_500k_plus / total_share
  ) %>%
  ungroup()

## 5. Combine back with known data to get full tax-share series ----
df_filled <- known %>%
  bind_rows(pred_missing) %>%
  arrange(Year)

## 6. Convert shares into counts per bracket ----
df_counts <- df_filled %>%
  mutate(
    # Number of employed people in each bracket
    n_R0_70001   = Employed * Tax_R0_70001,
    n_70k_350k   = Employed * Tax_70k_350k,
    n_350k_500k  = Employed * Tax_350k_500k,
    n_500k_plus  = Employed * Tax_500k_plus
  )

## 7. Define "middle class" ----
df_final <- df_counts %>%
  mutate(
    middle_class_count = n_70k_350k + n_350k_500k,
    
    # Shares as proportions
    middle_class_share_population = middle_class_count / Population,
    middle_class_share_employed   = middle_class_count / Employed,
  )

## 8. Save results for plotting / Excel / further analysis ----
write_xlsx(df_final, "../Bayes_Project_with_imputed_shares_and_middle_class.xlsx")
