SHELL := /usr/local_rwth/bin/zsh
TASK := kmeans
SRCDIRS := .
SRCEXT := cu
SOURCES := main.cu
OBJECTS := $(SOURCES:%.${SRCEXT}=%.o)
DEPENDENCIES := $(OBJECTS:%.o=%.d)
EXECUTABLE := ${TASK}.exe
DIRNAME := $(notdir ${CURDIR})

# INPUT_DIR needs to be set according to your local file placement
INPUT_DIR := input

# CUDA compiler
NVCC := nvcc
HOST_COMPILER ?= g++

# CUDA flags
CUDA_ARCH := -arch=sm_90                    # Target H100 GPU Hopper architecture
NVCC_FLAGS := -std=c++14 -Xcompiler -fopenmp $(CUDA_ARCH)  # C++14 standard, pass -fopenmp to host compiler
NVCC_FLAGS_FAST := -O3                     
NVCC_FLAGS_DEBUG := -G -g -O0 -Xcompiler -Wall  # -G: device debug info, -g: host debug, -O0: no optimization

INCLUDES := $(addprefix -I, ${SRCDIRS})
LDLIBS := -lgomp -lcublas

NTHREADS ?= 1
GROUP ?= X

# set default build target
build: release

# build for debugging
debug: NVCC_FLAGS += ${NVCC_FLAGS_DEBUG}
debug: ${EXECUTABLE}

# build for performance
release: NVCC_FLAGS += ${NVCC_FLAGS_FAST}
release: ${EXECUTABLE}

${EXECUTABLE}: ${OBJECTS}
	${NVCC} ${NVCC_FLAGS} -o $@ $^ ${LDLIBS}

%.o: %.${SRCEXT}
	${NVCC} ${INCLUDES} ${NVCC_FLAGS} -c -o $@ $<

input-large: ${INPUT_DIR}/large.in

${INPUT_DIR}/large.in: ${INPUT_DIR}/gen_input.py
	module load Python && python ${INPUT_DIR}/gen_input.py --file input/large.in --k ${NCENTERS} --n ${NPOINTS} --dim_x ${DIM} --dim_y ${DIM}

run-small: NPOINTS = 1000
run-small: DIM = 100
run-small: NCENTERS ?= 5
run-small: NITERS ?= 20
run-small: release
	OMP_NUM_THREADS=${NTHREADS} ./${EXECUTABLE} ${INPUT_DIR}/small.in ${DIM} ${NPOINTS} ${NCENTERS} ${NITERS}

run-mid: NPOINTS = 1000000
run-mid: DIM = 100
run-mid: NCENTERS ?= 5000
run-mid: NITERS ?= 50
run-mid: release
	OMP_NUM_THREADS=${NTHREADS} ./${EXECUTABLE} ${INPUT_DIR}/mid.in ${DIM} ${NPOINTS} ${NCENTERS} ${NITERS}

run-large: NPOINTS = 100000000
run-large: DIM = 1000
run-large: NCENTERS ?= 50000
run-large: NITERS ?= 100
run-large: release input-large
	OMP_NUM_THREADS=${NTHREADS} ./${EXECUTABLE} ${INPUT_DIR}/large.in ${DIM} ${NPOINTS} ${NCENTERS} ${NITERS}

vis-small:
	module load Python && ./utils/make-gif.py ${INPUT_DIR}/small.in memory.out clusters.gif

vis-mid:
	module load Python && ./utils/make-gif.py ${INPUT_DIR}/mid.in memory.out clusters.gif

vis-large:
	module load Python && ./utils/make-gif-large.py ${INPUT_DIR}/large.in memory.out clusters.gif

archive: clean
	find . -maxdepth 1 -type f -exec tar --transform 's|^|${DIRNAME}-group-${GROUP}/|g' -cvzf ${DIRNAME}-group-${GROUP}.tar.gz {} +

.PHONY: clean build debug release run-small run-mid run-large vis-small vis-mid vis-large archive
clean:
	${RM} ${EXECUTABLE}
	${RM} ${OBJECTS}
	${RM} ${DEPENDENCIES}
	-${RM} *.out *.gif 2>/dev/null || true

-include ${DEPENDENCIES}
