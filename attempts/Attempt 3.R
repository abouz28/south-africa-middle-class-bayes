library(readxl)
library(writexl)
library(dplyr)
library(stringr)

## 1. Read the Excel file ----
df_raw <- read_excel("../Bayes Project Data.xlsx", sheet = 1)

# Take a quick look at the column names
names(df_raw)

df <- df_raw %>% 
  # drop the empty column that read as "Unnamed: 10" or similar
  select(-starts_with("Unnamed")) %>%
  # give nicer names for later modeling
  rename(
    Tax_R0_70001      = `R0-R70 001`,
    Tax_70k_350k      = `R70 001 to R350 000`,
    Tax_350k_500k     = `R350 001 to R500 000`,
    Tax_500k_plus     = `R500 000 above`,
    Pop_R0_70001      = `R0-R70 001 (p)`,
    Pop_70k_350k      = `R70 001 to R350 000 (p)`,
    Pop_350k_500k     = `R350 001 to R500 000 (p)`,
    Pop_500k_plus     = `R500 000 above (p)`
  )

df <- df %>%
  mutate(
    across(
      # everything except Year should be numeric, but this is harmless if it already is
      c(Employed, Unemployed, UnempRate, Population, RealGDPGrowth,
        Tax_R0_70001, Tax_70k_350k, Tax_350k_500k, Tax_500k_plus,
        Pop_R0_70001, Pop_70k_350k, Pop_350k_500k, Pop_500k_plus),
      as.numeric
    )
  )

pop_share_cols <- c("Pop_R0_70001", "Pop_70k_350k", "Pop_350k_500k", "Pop_500k_plus")

# Rows where we know the population % (2013–2025)
known   <- df %>% filter(!is.na(Pop_R0_70001))

# Rows where we want to predict (1994–2012)
missing <- df %>% filter(is.na(Pop_R0_70001))

nrow(known)    # should be 13
nrow(missing)  # should be 19

## 4. Fit models: Share ~ poly(Year, 2) for each (p) column ----
models <- lapply(pop_share_cols, function(col) {
  form <- as.formula(paste(col, "~ poly(Year, 2, raw=TRUE)"))
  lm(form, data = known)
})

names(models) <- pop_share_cols


summary(models$Pop_70k_350k)

## 5. Predict population shares for missing years ----

# Get predictions for each share column
pred_list <- lapply(pop_share_cols, function(col) {
  predict(models[[col]], newdata = missing)
})
names(pred_list) <- pop_share_cols

# Turn into a data frame
pred_df <- as.data.frame(pred_list)

# 5a. Ensure no negative shares
pred_df[pred_df < 0] <- 0

# 5b. Rescale so the four shares sum to 1 for each year
row_sums <- rowSums(pred_df)
pred_df  <- pred_df / row_sums

## 6. Combine predictions with original data ----

# Put the predictions into the "missing" block
missing_filled <- missing %>%
  mutate(
    Pop_R0_70001  = pred_df$Pop_R0_70001,
    Pop_70k_350k  = pred_df$Pop_70k_350k,
    Pop_350k_500k = pred_df$Pop_350k_500k,
    Pop_500k_plus = pred_df$Pop_500k_plus
  )

# Re-combine with the known years and sort by Year
df_filled <- known %>%
  bind_rows(missing_filled) %>%
  arrange(Year)

df_filled %>%
  mutate(total_p = Pop_R0_70001 + Pop_70k_350k + Pop_350k_500k + Pop_500k_plus) %>%
  select(Year, total_p) %>%
  head(25)

write_xlsx(df_filled, "../Bayes_Project2.xlsx")
