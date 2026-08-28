library(readxl)
library(dplyr)

# Read the sheet, treating the first row as data, not header
raw <- read_excel("../Data to feed into our model.xlsx", sheet = 1, col_names = FALSE)

# Manually set nicer column names
names(raw) <- c("Year", "Employed", "Unemployed", "UnempRate", 
                "Population", "RealGDPGrowth",
                "Tax_R0_70001", "Tax_70k_350k", 
                "Tax_350k_500k", "Tax_500k_plus")

# Drop the first row (it contains the text labels like "Number of people employed")
df <- raw[-1, ]

# Convert to numeric
df <- df %>% 
  mutate(across(everything(), as.numeric))

# Rows where tax shares are known
known <- df %>% filter(!is.na(Tax_70k_350k))

# Rows where tax shares are missing (likely 1994–2012)
missing <- df %>% filter(is.na(Tax_70k_350k))

nrow(known)   # ~13 years (2013–2025)
nrow(missing) # ~19 years (1994–2012)

# Fit models using Year + unemployment rate
m_mid <- lm(Tax_70k_350k ~ Year + UnempRate, data = known)
m_upper <- lm(Tax_350k_500k ~ Year + UnempRate, data = known)
m_top <- lm(Tax_500k_plus ~ Year + UnempRate, data = known)


summary(m_mid)
summary(m_upper)
summary(m_top)

pred_mid   <- predict(m_mid,   newdata = missing)
pred_upper <- predict(m_upper, newdata = missing)
pred_top   <- predict(m_top,   newdata = missing)

pred_missing <- missing %>%
  mutate(
    Tax_R0_70001 = 0,
    Tax_70k_350k  = pmax(pred_mid,   0),
    Tax_350k_500k = pmax(pred_upper, 0),
    Tax_500k_plus = pmax(pred_top,   0)
  ) %>%
  rowwise() %>%
  mutate(
    total = Tax_R0_70001 + Tax_70k_350k + Tax_350k_500k + Tax_500k_plus,
    Tax_70k_350k  = Tax_70k_350k  / total,
    Tax_350k_500k = Tax_350k_500k / total,
    Tax_500k_plus = Tax_500k_plus / total
  ) %>%
  ungroup()

df_filled <- bind_rows(known, pred_missing) %>%
  arrange(Year)

library(writexl)
write_xlsx(df_filled, "../data_with_imputed_tax_shares2.xlsx")
