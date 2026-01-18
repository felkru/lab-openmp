import sys

try:
    with open("memory_cpu_verify.out") as f1, open("memory_omp_verify.out") as f2:
        c1 = f1.readlines()
        c2 = f2.readlines()
        
    if len(c1) != len(c2):
        print(f"Line count mismatch: {len(c1)} vs {len(c2)}")
        sys.exit(1)
        
    for i, (l1, l2) in enumerate(zip(c1, c2)):
        p1 = l1.split()
        p2 = l2.split()
        for j in range(1, 3):
            v1 = float(p1[j])
            v2 = float(p2[j])
            if abs(v1 - v2) > 1e-2:
                print(f"Mismatch at line {i+1} col {j}: {v1} vs {v2}")
                sys.exit(1)
    print("Files match within tolerance")
    sys.exit(0)
except Exception as e:
    print(e)
    sys.exit(1)
