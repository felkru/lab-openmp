import random
import argparse

def generate_k_points(k, x, y):
    # Generate k random points in a 2D plane
    points = [(random.uniform(0, x), random.uniform(0, y)) for _ in range(k)]
    return points

def generate_n_points_around_k(k_points, n, x, y, spread):
    # Generate n points randomly around the k points, equally distributed
    n_per_k = n // len(k_points)
    remaining_points = n % len(k_points)

    x_s = x * spread
    y_s = y * spread

    all_points = []

    for point in k_points:
        for _ in range(n_per_k):
            x_offset = random.uniform(-x_s, x_s)
            y_offset = random.uniform(-y_s, y_s)
            new_point = (abs(min(point[0] + x_offset, x)), abs(min(point[1] + y_offset, y)))
            all_points.append(new_point)

    # Distribute remaining points
    for i in range(remaining_points):
        point = k_points[i % len(k_points)]
        x_offset = random.uniform(-x_s, x_s)
        y_offset = random.uniform(-y_s, y_s)
        new_point = (abs(min(point[0] + x_offset, x)), abs(min(point[1] + y_offset, y)))
        all_points.append(new_point)

    return all_points

def write_points_to_file(points, filename):
    with open(filename, 'w') as f:
        for point in points:
            f.write(f"{point[0]} {point[1]}\n")

def main():
    parser = argparse.ArgumentParser(description="Generate points on a 2D plane.")
    parser.add_argument('--k', type=int, help="Number of initial centroids", default=5)
    parser.add_argument('--n', type=int, help="Number of random points to generate around the initial centroids", default=25)
    parser.add_argument('--dim_x', type=int, help="Range of the x-axis starting from zero", default=100)
    parser.add_argument('--dim_y', type=int, help="Range of the y-axis starting from zero", default=100)
    parser.add_argument('--rel_spread', type=float, help="Spread around points relative to grid dimensions", default=0.1)
    parser.add_argument('--file', type=str, help="Name of the output file", default="points.in")

    args = parser.parse_args()

    k = args.k
    n = args.n

    random.seed(42)

    # Generate points
    k_points = generate_k_points(k, args.dim_x, args.dim_y)
    all_points = generate_n_points_around_k(k_points, n, args.dim_x, args.dim_y, args.rel_spread)

    # Write points to file
    write_points_to_file(all_points, args.file)

    print(f"Generated {n} points around {k} centroids. Written to {args.file}.")

if __name__ == "__main__":
    main()
