
TASK := merge-sort
SRCDIRS := .
SRCEXT := cpp
SOURCES := $(wildcard $(addsuffix /*.${SRCEXT}, ${SRCDIRS}))
OBJECTS := $(SOURCES:%.${SRCEXT}=%.o)
DEPENDENCIES := $(OBJECTS:%.o=%.d)
EXECUTABLE := ${TASK}.exe
DIRNAME := $(notdir ${CURDIR})

CXX ?= icpc
COMPILER = ${CXX}
FLAGS_OPENMP ?= -qopenmp
FLAGS = -g ${FLAGS_OPENMP}
FLAGS_FAST = -O3 -march=native -xHost -qopt-report=3 -Wno-deprecated-declarations -DENABLE_BRANCHLESS -DENABLE_HUGE_PAGES
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

run-small: release
	OMP_NUM_THREADS=$(NTHREADS) ./${EXECUTABLE} 9999999

run-mid: release
	OMP_NUM_THREADS=$(NTHREADS) ./${EXECUTABLE} 99999999
	
run-large: release
	OMP_NUM_THREADS=$(NTHREADS) ./${EXECUTABLE} 999999999

archive: clean
	find . -maxdepth 1 -type f -exec tar --transform 's|^|${DIRNAME}-group-${GROUP}/|g' -cvzf ${DIRNAME}-group-${GROUP}.tar.gz {} +

.PHONY: clean build debug release run-small run-large archive
clean:
	${RM} ${EXECUTABLE}
	${RM} ${OBJECTS}
	${RM} ${DEPENDENCIES}

-include ${DEPENDENCIES}
