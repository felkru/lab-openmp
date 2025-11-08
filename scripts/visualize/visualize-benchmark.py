import argparse
import polars as pl
import matplotlib.pyplot as plt
import os

parser = argparse.ArgumentParser(description="Visualize contents of a csv file containing the collected benchmark results")
parser.add_argument("-csv", "--csv-file", 
                    required=True, 
                    help="the csv file containing the results to visualize; required csv columns are: task, version, num_threads, size, run")
parser.add_argument("-col", "--column-name",
                    required=True,
                    help="the column name of the metric to visualize")
parser.add_argument("-m", "--metric-name",
                    required=True,
                    help="the readable metric name displayed in the plot")
parser.add_argument("-ni", "--no-ideal",
                    action="store_true",
                    help="flag indicating not to draw the ideal scaling curve")
parser.add_argument("-i", "--invert-ideal",
                    action="store_true",
                    help="invert the scaling curve for the metric so that ideal=num_threads*v[0] instead of ideal=v[0]/num_threads")
parser.add_argument("-o", "--output",
                    required=False,
                    help="Output file to write plots to (default: <folder of csv input file>/plot.png)")
parser.add_argument("-d", "--deviation",
                    action="store_true",
                    help="draw deviation intervals on data points")
parser.add_argument("-agg", "--aggregation",
                    default="avg",
                    choices=["avg", "med"],
                    help="aggregation method to use for plotting metric (default avg)")
args = parser.parse_args()

outfile = args.output or os.path.join(os.path.dirname(args.csv_file), "plot.png")

df = pl.read_csv(args.csv_file)
match args.aggregation:
    case "med":
        mode = "Median"
        df_small = df.filter(pl.col("size") == "small").group_by("num_threads").agg(pl.col(args.column_name).median()).sort("num_threads")
        df_large = df.filter(pl.col("size") == "large").group_by("num_threads").agg(pl.col(args.column_name).median()).sort("num_threads")
    case "avg":
        mode = "Average"
        df_small = df.filter(pl.col("size") == "small").group_by("num_threads").agg(pl.col(args.column_name).mean()).sort("num_threads")
        df_large = df.filter(pl.col("size") == "large").group_by("num_threads").agg(pl.col(args.column_name).mean()).sort("num_threads")

min_small = df.filter(pl.col("size") == "small").group_by("num_threads").agg(pl.col(args.column_name).min()).sort("num_threads")
max_small = df.filter(pl.col("size") == "small").group_by("num_threads").agg(pl.col(args.column_name).max()).sort("num_threads")
min_large = df.filter(pl.col("size") == "large").group_by("num_threads").agg(pl.col(args.column_name).min()).sort("num_threads")
max_large = df.filter(pl.col("size") == "large").group_by("num_threads").agg(pl.col(args.column_name).max()).sort("num_threads")

e_small = [df_small[args.column_name] - min_small[args.column_name],
           max_small[args.column_name] - df_small[args.column_name]]

e_large = [df_large[args.column_name] - min_large[args.column_name],
           max_large[args.column_name] - df_large[args.column_name]]

xt_s = [1] + [x for x in range(12, 97, 12)]
xt_l = [1] + [x for x in range(12, 97, 12)]

# TODO: how to account for errorbars on edge of plot?
xlim_s = (df_small["num_threads"][0], df_small["num_threads"][-1]) 
xlim_l = (df_large["num_threads"][0], df_large["num_threads"][-1])

fig, ax = plt.subplots(2,2, figsize=(12,10))
ax[0,0].grid()
ax[0,1].grid()
ax[1,0].grid()
ax[1,1].grid()

# Plot for small problem size
ref_small = df_small[args.column_name][0]
n0_s = df_small["num_threads"][0]

if not args.no_ideal:
    if args.invert_ideal:
        ideal_s = [ref_small * (n / n0_s) for n in df_small["num_threads"]]
    else:
        ideal_s = [ref_small / (n / n0_s) for n in df_small["num_threads"]]

    speedup_ideal_s = [n / n0_s for n in df_small["num_threads"]]

    ax[0,0].plot(df_small["num_threads"], ideal_s, color="grey")
    ax[1,0].plot(df_small["num_threads"], speedup_ideal_s, color="grey")

ax[0,0].set_title(f"Small Problem Size ({mode})")
ax[0,0].set_xlabel("Number of threads")
ax[0,0].set_ylabel(args.metric_name)
ax[0,0].set_xticks(xt_s)
ax[0,0].set_xlim(xlim_s)
if args.deviation:
    ax[0,0].errorbar(df_small["num_threads"], df_small[args.column_name], 
                     yerr=e_small, color="red", ecolor="lightcoral", capsize=2.0)
else:
    ax[0,0].plot(df_small["num_threads"], df_small[args.column_name], color="red")

# Speedup small problem size
ax[1,0].set_title("Speedup for Small Problem Size")
ax[1,0].set_xlabel("Number of threads")
ax[1,0].set_ylabel("Speedup")
ax[1,0].set_xticks(xt_s)
ax[1,0].set_xlim(xlim_s)

if args.invert_ideal:
    speedup_small = [v/ref_small for v in df_small[args.column_name]]
else:
    speedup_small = [ref_small/v for v in df_small[args.column_name]]

ax[1,0].plot(df_small["num_threads"], speedup_small, color="red")


# Plot for large problem size
ref_large = df_large[args.column_name][0]
n0_l = df_large["num_threads"][0]

if not args.no_ideal:
    if args.invert_ideal:
        ideal_l = [ref_large * (n / n0_l) for n in df_large["num_threads"]]
    else:
        ideal_l = [ref_large / (n / n0_l) for n in df_large["num_threads"]]
        
    speedup_ideal_l = [n / n0_l for n in df_large["num_threads"]]

    ax[0,1].plot(df_large["num_threads"], ideal_l, color="grey")
    ax[1,1].plot(df_large["num_threads"], speedup_ideal_l, color="grey")

ax[0,1].set_title(f"Large Problem Size ({mode})")
ax[0,1].set_xlabel("Number of threads")
ax[0,1].set_ylabel(args.metric_name)
ax[0,1].set_xticks(xt_l)
ax[0,1].set_xlim(xlim_l)
if args.deviation:
    ax[0,1].errorbar(df_large["num_threads"], df_large[args.column_name], 
                     yerr=e_large, color="red", ecolor="lightcoral", capsize=2.0)
else:
    ax[0,1].plot(df_large["num_threads"], df_large[args.column_name], color="red")

# Speedup large problem size
ax[1,1].set_title("Speedup for Large Problem Size")
ax[1,1].set_xlabel("Number of threads")
ax[1,1].set_ylabel("Speedup")
ax[1,1].set_xticks(xt_l)
ax[1,1].set_xlim(xlim_l)

if args.invert_ideal:
    speedup_large = [v/ref_large for v in df_large[args.column_name]]
else:
    speedup_large = [ref_large/v for v in df_large[args.column_name]]

ax[1,1].plot(df_large["num_threads"], speedup_large, color="red")


fig.tight_layout()
fig.savefig(outfile, dpi=200)