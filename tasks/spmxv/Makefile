
TASK := spmxv
SRCDIRS := . utils
SRCEXT := cpp
SOURCES := $(wildcard $(addsuffix /*.${SRCEXT}, ${SRCDIRS}))
OBJECTS := $(SOURCES:%.${SRCEXT}=%.o)
DEPENDENCIES := $(OBJECTS:%.o=%.d)
EXECUTABLE := ${TASK}.exe
DIRNAME := $(notdir ${CURDIR})

# MAT_DIR needs to be set according to your local file placement
MAT_DIR := input-matrix

CXX ?= icpc
COMPILER = ${CXX}
FLAGS_OPENMP ?= -qopenmp
FLAGS = -g ${FLAGS_OPENMP}
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

run-small: REP ?= 100000
run-small: release
	OMP_NUM_THREADS=${NTHREADS} ./${EXECUTABLE} -t ${NTHREADS} -f ${MAT_DIR}/mat_dim_59319.txt -r ${REP}

run-large: REP ?= 10000
run-large: release
	OMP_NUM_THREADS=${NTHREADS} ./${EXECUTABLE} -t ${NTHREADS} -f ${MAT_DIR}/mat_dim_493039.txt -r ${REP}

# fast testing
.PHONY: test-small test-large
test-small:
	$(MAKE) run-small REP=1000
test-large:
	$(MAKE) run-large REP=100
# fast testing

# prints out the usage of the command line feature
help: build
	./${EXECUTABLE} -h

archive: clean
	find . -maxdepth 1 -type f -exec tar --transform 's|^|${DIRNAME}-group-${GROUP}/|g' -cvzf ${DIRNAME}-group-${GROUP}.tar.gz {} +

.PHONY: clean build debug release run-small run-large archive help
clean:
	${RM} ${EXECUTABLE}
	${RM} ${OBJECTS}
	${RM} ${DEPENDENCIES}

-include ${DEPENDENCIES}
