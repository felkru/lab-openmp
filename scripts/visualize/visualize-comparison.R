#!/usr/bin/env Rscript

##############################
# libraries
##############################
suppressPackageStartupMessages(library(ggplot2))
suppressPackageStartupMessages(library(scales))
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(stringr))
suppressPackageStartupMessages(library(argparse))
suppressPackageStartupMessages(library(Hmisc))

##############################
# command line parsing
##############################
parser <- ArgumentParser(description = "Visualize contents of one or more csv files containing the collected benchmark results of one or more code versions")
parser$add_argument("-csvs", "--csv-files", type = "character", nargs = "+", action="store", required = TRUE, help = "one or more csv files containing the results to visualize; required csv columns are: task, version, num_threads, size, run")
parser$add_argument("-col", "--column-name", type = "character", nargs = 1, action="store", required = TRUE, help = "the column name of the metric to visualize")
parser$add_argument("-metric", "--metric-name", type = "character", nargs = 1, action="store", required = TRUE, help = "the readable metric name displayed in the plot")
parser$add_argument("-unit", "--metric-unit", type = "character", nargs = 1, action="store", required = TRUE, help = "the readable metric unit displayed in the plot")
parser$add_argument("-conf", "--confidence-level", type = "double", nargs = 1, action="store", default = 0.95, help = "the confidence interval around the mean displayed in the plot (default: %(default)s)")
parser$add_argument("-inv", "--invert-speedup", action="store_true", help = "invert the speedup calculated from the given metric (default: %(default)s)")
args <- parser$parse_args()

csv_files <- args$csv_files
column_name <- args$column_name
metric_name <- args$metric_name
metric_unit <- args$metric_unit
confidence_level <- args$confidence_level
invert_speedup <- args$invert_speedup

##############################
# data import & transform
##############################
df <- data.frame()
for (csv_file in csv_files) {
  df.tmp <- read.csv(csv_file)
  df <- rbind(df, df.tmp)
}

df <-
  df %>%
  mutate(
    size = factor(
      size, ordered = TRUE,
      levels = c("small", "large"),
      labels = c("Small Problem Size", "Large Problem Size")
    )
  ) %>%
  group_by(task, version, num_threads, size)

# disable message about output grouping to not cause confusion
options(dplyr.summarise.inform = FALSE)
df.median <-
  df %>%
  summarise(median = median(get(column_name))) %>%
  ungroup() %>%
  arrange(task, version, size, num_threads) %>%
  group_by(task, version, size) %>%
  mutate(speedup = if_else(rep(invert_speedup, length(unique(df$num_threads))), median / median[1], median[1] / median)) %>%
  mutate(efficiency = speedup / num_threads)
options(dplyr.summarise.inform = TRUE)

num_executions <- length(unique(df$run))
num_versions <- length(unique(df$version))
task <- df$task[1]

##############################
# visualization
##############################
output_dir <- file.path(getwd(), "comparison")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

ggplot(df.median, aes(x = num_threads, y = median, group = version, colour = version)) +
  facet_wrap(~ size, scales = "free_y") +
  geom_line(size = 2) +
  geom_point(size = 4) +
  labs(colour = "Code Version") +
  xlab("#Threads") +
  ylab(str_interp("${metric_name} (${metric_unit})")) +
  ggtitle(str_interp("Median ${metric_name} over ${num_executions} Executions of Task ${task}")) +
  ggpresent::theme_presentation() +
  scale_x_continuous(trans = "log2", breaks = ggpresent::trans_breaks_log2()) +
  scale_y_continuous(trans = "log2", breaks = ggpresent::trans_breaks_log2()) +
  scale_colour_manual(values = ggpresent::palette_presentation())

for (dev in c("pdf", "png")) {
  ggpresent::save_presentation(path = output_dir, filename = paste(column_name, "absolute", dev, sep = "."))
}

ggplot(df.median, aes(x = num_threads, y = speedup, group = version, colour = version)) +
  facet_wrap(~ size) +
  # add line as reference for the ideal speedup
  stat_function(fun = log2, colour = "grey", geom = "line", size = 2) +
  geom_line(size = 2) +
  geom_point(size = 4) +
  labs(colour = "Code Version") +
  xlab("#Threads") +
  ylab("Speedup") +
  ggtitle(str_interp("Speedup for the Median ${metric_name} over ${num_executions} Executions of Task ${task}")) +
  ggpresent::theme_presentation() +
  scale_x_continuous(trans = "log2", breaks = ggpresent::trans_breaks_log2()) +
  scale_y_continuous(trans = "log2", breaks = ggpresent::trans_breaks_log2()) +
  scale_colour_manual(values = ggpresent::palette_presentation()) +
  coord_cartesian(ylim = c(1, max(df.median$num_threads)))

for (dev in c("pdf", "png")) {
  ggpresent::save_presentation(path = output_dir, filename = paste(column_name, "speedup", dev, sep = "."))
}

ggplot(df.median, aes(x = num_threads, y = efficiency, group = version, colour = version)) +
  facet_wrap(~ size) +
  geom_line(size = 2) +
  geom_point(size = 4) +
  labs(colour = "Code Version") +
  xlab("#Threads") +
  ylab("Parallel Efficiency") +
  ggtitle(str_interp("Parallel Efficiency for the Median ${metric_name} over ${num_executions} Executions of Task ${task}")) +
  ggpresent::theme_presentation() +
  scale_x_continuous(trans = "log2", breaks = ggpresent::trans_breaks_log2()) +
  scale_colour_manual(values = ggpresent::palette_presentation()) +
  coord_cartesian(ylim = c(0, 1))

for (dev in c("pdf", "png")) {
  ggpresent::save_presentation(path = output_dir, filename = paste(column_name, "efficiency", dev, sep = "."))
}

ggplot(df, aes(x = num_threads, y = get(column_name), group = version, colour = version)) +
  facet_wrap(~ size, scales="free_y") +
  stat_summary(geom = "point", fun = mean, shape = 18, size = 4, position = position_dodge(width = 1 / num_versions)) +
  stat_summary(geom = "errorbar", fun.data = mean_cl_normal, fun.args = list(conf.int = confidence_level), size = 1, position = position_dodge(width = 1 / num_versions)) +
  labs(colour = "Code Version") +
  xlab("#Threads") +
  ylab(str_interp("${metric_name} (${metric_unit})")) +
  ggtitle(str_interp("${confidence_level * 100}% CIs for the Mean ${metric_name} over ${num_executions} Executions of Task ${task}")) +
  ggpresent::theme_presentation() +
  scale_x_continuous(trans = "log2", breaks = ggpresent::trans_breaks_log2()) +
  scale_y_continuous(trans = "log2", breaks = ggpresent::trans_breaks_log2()) +
  scale_colour_manual(values = ggpresent::palette_presentation())

for (dev in c("pdf", "png")) {
  ggpresent::save_presentation(path = output_dir, filename = paste(column_name, "confidence-interval", dev, sep = "."))
}

##############################
# cleanup
##############################
# necessary for non-interactive execution
ggpresent::cleanup_devpdf()

