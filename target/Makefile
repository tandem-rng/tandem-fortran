# Build and test the OpenMP target and do concurrent fills from the repository root:
# `make -f target/Makefile test`. The module is plain Fortran, so any compiler builds it. With
# gfortran -fopenmp the target regions run on the host, which is what CI uses. For a GPU:
#   nvfortran:  make -f target/Makefile test FC=nvfortran FFLAGS="-O2 -mp=gpu -stdpar=gpu -gpu=cc80"
#   flang:      make -f target/Makefile test FC=flang FFLAGS="-O2 -fopenmp --offload-arch=sm_80"
FC ?= gfortran
ifeq ($(origin FC),default)
FC := gfortran
endif
CC ?= cc
ifeq ($(origin CC),default)
CC := $(shell command -v clang >/dev/null 2>&1 && echo clang || echo cc)
endif
FFLAGS ?= -O2 -fopenmp -Wall -Wextra -Werror -std=f2018 -fimplicit-none
CFLAGS ?= -O2
LDLIBS ?= -lm
# nvfortran and flang name the module directory differently from gfortran.
ifneq (,$(findstring nvfortran,$(FC)))
MODDIR = -module $(B)
else
MODDIR = -J$(B)
endif
B ?= build/target

.PHONY: test bench clean

$(B):
	mkdir -p $@

$(B)/tandem.o: src/c/tandem.c src/c/tandem.h | $(B)
	$(CC) $(CFLAGS) -c -o $@ $<

$(B)/tandem_layout.o: src/c/tandem_layout.c src/c/tandem.h | $(B)
	$(CC) $(CFLAGS) -c -o $@ $<

$(B)/tandem_rng.o: src/tandem_rng.f90 | $(B)
	$(FC) $(FFLAGS) $(MODDIR) -c -o $@ $<

$(B)/tandem_rng_target.o: target/tandem_rng_target.f90 $(B)/tandem_rng.o
	$(FC) $(FFLAGS) $(MODDIR) -c -o $@ $<

OBJS := $(B)/tandem.o $(B)/tandem_layout.o $(B)/tandem_rng.o $(B)/tandem_rng_target.o

$(B)/test_target: target/test_target.f90 $(OBJS)
	$(FC) $(FFLAGS) $(MODDIR) -o $@ $< $(OBJS) $(LDLIBS)

$(B)/bench_target: target/bench_target.f90 $(OBJS)
	$(FC) $(FFLAGS) $(MODDIR) -o $@ $< $(OBJS) $(LDLIBS)

test: $(B)/test_target
	./$(B)/test_target

bench: $(B)/bench_target
	./$(B)/bench_target

clean:
	rm -rf $(B)
