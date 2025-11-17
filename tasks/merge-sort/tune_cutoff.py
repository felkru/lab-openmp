#!/usr/bin/env python3
"""
Find optimal cutoff using binary search - runs INSIDE allocated SLURM job

Usage: srun [slurm-args] python tune_cutoff.py
"""

import re
import os
import subprocess
from pathlib import Path
from dataclasses import dataclass
from typing import List
import statistics


@dataclass
class BenchmarkResult:
    cutoff: int
    times: List[float]
    
    @property
    def mean(self) -> float:
        return statistics.mean(self.times)
    
    @property
    def stdev(self) -> float:
        return statistics.stdev(self.times) if len(self.times) > 1 else 0.0
    
    @property
    def score(self) -> float:
        """Lower is better. Mean + small variance penalty"""
        return self.mean + 0.1 * self.stdev


def update_cutoff(cutoff: int, cpp_file: Path) -> None:
    """Update cutoff value in main.cpp"""
    content = cpp_file.read_text()
    new_content = re.sub(r'if \(size >= \d+\)', f'if (size >= {cutoff})', content)
    cpp_file.write_text(new_content)


def run_benchmark(cutoff: int, task_dir: Path, num_iter: int = 3) -> BenchmarkResult:
    """Compile and run benchmark for given cutoff"""
    cpp_file = task_dir / "main.cpp"
    update_cutoff(cutoff, cpp_file)
    
    # Rebuild
    subprocess.run(["make", "clean", "build"], cwd=task_dir, check=True, 
                   capture_output=True)
    
    # Run multiple iterations
    times = []
    for i in range(num_iter):
        result = subprocess.run(
            ["make", "run-large"],
            cwd=task_dir,
            env={**os.environ, "NTHREADS": "96"},
            capture_output=True,
            text=True,
            check=True
        )
        
        # Extract time: "done, took X.XXX sec"
        matches = re.findall(r'took (\d+\.\d+)', result.stdout)
        if matches:
            times.append(float(matches[0]))
    
    return BenchmarkResult(cutoff, times)


def binary_search_cutoff(
    min_cutoff: int = 1000,
    max_cutoff: int = 100000,
    tolerance: int = 2000
) -> BenchmarkResult:
    """Binary search for optimal cutoff"""
    
    task_dir = Path(__file__).parent
    results = []
    
    while max_cutoff - min_cutoff > tolerance:
        mid = (min_cutoff + max_cutoff) // 2
        
        print(f"\n{'='*60}")
        print(f"Testing range [{min_cutoff}, {max_cutoff}]")
        print(f"{'='*60}")
        
        for cutoff in [min_cutoff, mid, max_cutoff]:
            if not any(r.cutoff == cutoff for r in results):
                print(f"\n→ Testing cutoff={cutoff}...")
                result = run_benchmark(cutoff, task_dir)
                results.append(result)
                print(f"  Times: {[f'{t:.3f}' for t in result.times]}")
                print(f"  Mean: {result.mean:.3f}s, Stdev: {result.stdev:.3f}s, Score: {result.score:.3f}")
        
        # Find best in current range
        current = [r for r in results if min_cutoff <= r.cutoff <= max_cutoff]
        current.sort(key=lambda r: r.score)
        best = current[0]
        
        print(f"\n✓ Current best: cutoff={best.cutoff} (mean={best.mean:.3f}s)")
        
        # Adjust search range based on where best is
        if best.cutoff == min_cutoff:
            max_cutoff = mid
        elif best.cutoff == max_cutoff:
            min_cutoff = mid
        else:
            # Narrow around the best
            range_size = max_cutoff - min_cutoff
            min_cutoff = max(min_cutoff, best.cutoff - range_size // 4)
            max_cutoff = min(max_cutoff, best.cutoff + range_size // 4)
    
    # Return overall best
    results.sort(key=lambda r: r.score)
    return results[0]


def main():
    print("Starting cutoff optimization on allocated node...")
    print(f"Testing on large problem (999,999,999 elements), 3 iterations per cutoff\n")
    
    best = binary_search_cutoff()
    
    print(f"\n{'='*60}")
    print(f"OPTIMAL CUTOFF FOUND: {best.cutoff}")
    print(f"Mean time: {best.mean:.3f}s ± {best.stdev:.3f}s")
    print(f"{'='*60}\n")
    
    # Set to optimal
    cpp_file = Path(__file__).parent / "main.cpp"
    update_cutoff(best.cutoff, cpp_file)
    print(f"✓ Updated main.cpp to use cutoff={best.cutoff}")


if __name__ == "__main__":
    main()