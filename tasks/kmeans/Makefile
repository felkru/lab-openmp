SHELL := /usr/local_rwth/bin/zsh
TASK := kmeans
SRCDIRS := .
SRCEXT := cpp
SOURCES := $(wildcard $(addsuffix /*.${SRCEXT}, ${SRCDIRS}))
OBJECTS := $(SOURCES:%.${SRCEXT}=%.o)
DEPENDENCIES := $(OBJECTS:%.o=%.d)
EXECUTABLE := ${TASK}.exe
DIRNAME := $(notdir ${CURDIR})

# INPUT_DIR needs to be set according to your local file placement
INPUT_DIR := input

CXX ?= clang++
COMPILER = ${CXX}
FLAGS_OPENMP_OFFLOAD ?= -fopenmp -fopenmp-targets=nvptx64-nvidia-cuda -Xopenmp-target -march=sm_90
FLAGS = -std=c++14 -g ${FLAGS_OPENMP_OFFLOAD}
FLAGS_FAST = -O3
FLAGS_DEBUG = -O0 -Wall -Wextra
INCLUDES = $(addprefix -I, ${SRCDIRS})
LDLIBS =

NTHREADS ?= 1
GROUP ?= X

# set default build target
build: release

# build for debugging
debug: FLAGS += ${FLAGS_DEBUG}
debug: ${EXECUTABLE}

# build for performance
release: FLAGS += ${FLAGS_FAST}
release: ${EXECUTABLE}

${EXECUTABLE}: ${OBJECTS}
	${COMPILER} ${FLAGS} -o $@ $^ ${LDLIBS}

%.o: %.${SRCEXT}
	${COMPILER} ${INCLUDES} -MMD -MP ${FLAGS} -c -o $@ $<

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
	module load Python && ./utils/make-gif.py ${INPUT_DIR}/large.in memory.out clusters.gif

archive: clean
	find . -maxdepth 1 -type f -exec tar --transform 's|^|${DIRNAME}-group-${GROUP}/|g' -cvzf ${DIRNAME}-group-${GROUP}.tar.gz {} +

.PHONY: clean build debug release run-small run-mid run-large vis-small vis-mid vis-large archive
clean:
	${RM} ${EXECUTABLE}
	${RM} ${OBJECTS}
	${RM} ${DEPENDENCIES}
	${RM} *.out *.gif

-include ${DEPENDENCIES}
