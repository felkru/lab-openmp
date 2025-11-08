#!/usr/bin/env Rscript

##############################
# libraries
##############################
suppressPackageStartupMessages(library(ggplot2))
suppressPackageStartupMessages(library(scales))
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(stringr))
suppressPackageStartupMessages(library(gridExtra))
suppressPackageStartupMessages(library(argparse))

##############################
# command line parsing
##############################
parser <- ArgumentParser(description = "Visualize contents of a csv file containing the collected benchmark results")
parser$add_argument("-csv", "--csv-file", type = "character", nargs = 1, action="store", required = TRUE, help = "the csv file containing the results to visualize; required csv columns are: task, version, num_threads, size, run")
parser$add_argument("-col", "--column-name", type = "character", nargs = 1, action="store", required = TRUE, help = "the column name of the metric to visualize")
parser$add_argument("-metric", "--metric-name", type = "character", nargs = 1, action="store", required = TRUE, help = "the readable metric name displayed in the plot")
args <- parser$parse_args()

csv_file <- args$csv_file
column_name <- args$column_name
metric_name <- args$metric_name

##############################
# data import & transform
##############################
df <-
  read.csv(csv_file) %>%
  mutate(
    size = factor(
      size, ordered = TRUE,
      levels = c("small", "large"),
      labels = c("Small Problem Size", "Large Problem Size")
    )
  ) %>%
  group_by(task, version, num_threads, size) %>%
  mutate(
    zscore = scale(get(column_name)),
    is_normally_distributed = factor(
      shapiro.test(get(column_name))$p.value > 0.05,
      ordered = TRUE, levels = c(FALSE, TRUE)
    )
  )

num_executions <- length(unique(df$run))
task <- df$task[1]
version <- df$version[1]

##############################
# visualization
##############################
output_dir <- file.path(dirname(normalizePath(csv_file)), "plots")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

ggplot(df, aes(x = num_threads, y = zscore, group = num_threads, colour = is_normally_distributed)) +
  facet_wrap(~ size, nrow = 2, ncol = 1) +
  geom_violin() +
  geom_boxplot(width = 0.1) +
  stat_summary(geom = "point", fun = mean, shape = 18, size = 4) +
  labs(colour = "Normally\nDistributed?") +
  xlab("#Threads") +
  ylab(str_interp("Normalized ${metric_name} (zscore)")) +
  ggtitle(str_interp("${metric_name} Deviation over ${num_executions} Executions of Task ${task} (${version})")) +
  ggpresent::theme_presentation() +
  scale_x_continuous(trans = "log2", breaks = ggpresent::trans_breaks_log2()) +
  scale_colour_manual(values = c("#E41A1C", "#000000"), labels = c("No", "Yes"))

for (dev in c("pdf", "png")) {
  ggpresent::save_presentation(path = output_dir, filename = paste(column_name, "normalized-distribution", dev, sep = "."))
}

# disable message about output grouping to not cause confusion
options(dplyr.summarise.inform = FALSE)
table_data <-
  df %>%
  summarize(
    Median = round(median(get(column_name)), digits = 2),
    Mean = round(mean(get(column_name)), digits = 2),
    SD = round(sd(get(column_name)), digits = 2)
  ) %>%
  arrange(size, num_threads) %>%
  rename(Task = task, Version = version, "#Threads" = num_threads, "Problem Size" = size)
options(dplyr.summarise.inform = TRUE)

ggplot() +
  annotation_custom(
    grob = tableGrob(
      table_data,
      rows = NULL,
      theme = ttheme_default(
        core = list(fg_params = list(cex = 1.75, hjust = 1, x = 0.975)),
        colhead = list(fg_params = list(cex = 1.75))
      )
    )
  ) +
  ggpresent::theme_presentation()

for (dev in c("pdf", "png")) {
  ggpresent::save_presentation(path = output_dir, filename = paste(column_name, "table", dev, sep = "."))
}

##############################
# cleanup
##############################
# necessary for non-interactive execution
ggpresent::cleanup_devpdf()

