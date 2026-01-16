#!/usr/bin/env python3

import sys

from matplotlib.animation import FuncAnimation
import matplotlib.pyplot as plt
import numpy as np

# argument parsing (sys.argv does include the script name)
if len(sys.argv) < 4:
    print(f'Usage: {sys.argv[0]} data.in data.out data.gif')
    sys.exit(1)
point_file = sys.argv[1]
centroid_file = sys.argv[2]
gif_file = sys.argv[3]

# read input data
points = np.loadtxt(point_file)
centroids = np.loadtxt(centroid_file)

# initalise plot objects
fig, ax = plt.subplots()
fig.set_tight_layout(True)
ax.set_xlabel('x')
ax.set_ylabel('y')

# scatter persistent points (not animated)
ax.plot(points[:, 0], points[:, 1], 'b+', markeredgewidth=0.5, markersize=4)

# initialise object which holds animated centroid data
lines = ax.plot([], [], 'rx', markeredgewidth=1, markersize=8)

# corresponding update function for centroid animation
def update(iteration, num_centroids, num_iterations):
    print(f'Animating Iteration {iteration:02}/{num_iterations:02}...')

    ax.set_title(f'K-Means Clusters (Iteration {iteration:02})')

    start, end = iteration * num_centroids, (iteration + 1) * num_centroids
    lines[0].set_data(centroids[start:end, 1], centroids[start:end, 2])

    return lines, ax

# determine the size of the dataset
num_rows = np.size(centroids[:, 0])
num_iterations = int(np.max(centroids[:, 0]))
num_centroids = int(num_rows / (num_iterations + 1))

# create the animated plot
animation = FuncAnimation(fig, update, fargs=(num_centroids, num_iterations), frames=np.arange(num_iterations + 1))
animation.save(gif_file, writer='imagemagick')
