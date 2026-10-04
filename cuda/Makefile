# Build and test the GPU module: `make -f cuda/Makefile test` from the repository root, or
# `pixi run -e cuda test-cuda`. fpm cannot compile CUDA, so this builds the whole stack.
# make's built-in FC is f77.
ifeq ($(origin FC),default)
FC := gfortran
endif
# clang compiles the vendored C where it exists, and cc, usually gcc, is the fallback.
ifeq ($(origin CC),default)
CC := $(shell command -v clang >/dev/null 2>&1 && echo clang || echo cc)
endif
NVCC ?= nvcc
ARCH ?= -arch=sm_80
FFLAGS ?= -O2 -Wall -Wextra -Werror -std=f2018 -fimplicit-none
CFLAGS ?= -O2
NVCCFLAGS ?= -std=c++17 -O3 $(ARCH) -Xcompiler -Wall,-Wextra
B := build/cuda

# nvcc needs a host compiler it knows; a conda toolchain names one through CXX.
ifdef CXX
NVCCFLAGS += -ccbin $(CXX)
endif
# Binaries find the CUDA runtime that belongs to the nvcc that built them, also inside a
# conda environment.
NVCC_LIB := $(dir $(realpath $(shell command -v $(NVCC))))../lib
LDLIBS := -L$(NVCC_LIB) -Wl,-rpath,$(NVCC_LIB) -lcudart -lstdc++ -lm

OBJS := $(B)/tandem.o $(B)/tandem_layout.o $(B)/tandem_rng.o $(B)/tandem_cuda_fill.o $(B)/tandem_rng_cuda.o

.PHONY: build test bench test-device bench-device clean

build: $(B)/test_cuda $(B)/bench_cuda

$(B):
	mkdir -p $@

$(B)/tandem.o: src/c/tandem.c src/c/tandem.h | $(B)
	$(CC) $(CFLAGS) -c -o $@ $<

$(B)/tandem_layout.o: src/c/tandem_layout.c src/c/tandem.h | $(B)
	$(CC) $(CFLAGS) -c -o $@ $<

$(B)/tandem_cuda_fill.o: src/c/tandem_cuda_fill.cu src/c/tandem.cuh src/c/tandem/core.hpp | $(B)
	$(NVCC) $(NVCCFLAGS) -Isrc/c -c -o $@ $<

$(B)/tandem_rng.o: src/tandem_rng.f90 | $(B)
	$(FC) $(FFLAGS) -J$(B) -c -o $@ $<

$(B)/tandem_rng_cuda.o: cuda/tandem_rng_cuda.f90 $(B)/tandem_rng.o
	$(FC) $(FFLAGS) -J$(B) -c -o $@ $<

$(B)/vectors.o: test/vectors.f90 | $(B)
	$(FC) $(FFLAGS) -J$(B) -c -o $@ $<

$(B)/cross.o: test/cross.f90 | $(B)
	$(FC) $(FFLAGS) -J$(B) -c -o $@ $<

$(B)/test_cuda: cuda/test_cuda.f90 $(B)/vectors.o $(B)/cross.o $(OBJS)
	$(FC) $(FFLAGS) -J$(B) -o $@ $< $(B)/vectors.o $(B)/cross.o $(OBJS) $(LDLIBS)

$(B)/bench_cuda: cuda/bench_cuda.f90 $(OBJS)
	$(FC) $(FFLAGS) -J$(B) -o $@ $< $(OBJS) $(LDLIBS)

test: $(B)/test_cuda
	./$(B)/test_cuda

bench: $(B)/bench_cuda
	./$(B)/bench_cuda

# Device-side draws in CUDA Fortran kernels need nvfortran (NVIDIA HPC SDK), whose module
# files differ from gfortran's, so these objects live in their own directory.
NVFORTRAN ?= nvfortran
NVFFLAGS ?= -cuda -gpu=cc80 -O2 -Mstandard
N := $(B)/nvfortran
NOBJS := $(B)/tandem.o $(B)/tandem_layout.o $(B)/tandem_cuda_fill.o $(N)/tandem_rng.o $(N)/tandem_rng_cuda.o \
	$(N)/tandem_rng_device.o $(N)/tandem_rng_cuda_arrays.o $(N)/vectors.o $(N)/cross.o

$(N):
	mkdir -p $@

$(N)/tandem_rng.o: src/tandem_rng.f90 | $(N)
	$(NVFORTRAN) $(NVFFLAGS) -module $(N) -c -o $@ $<

$(N)/tandem_rng_cuda.o: cuda/tandem_rng_cuda.f90 $(N)/tandem_rng.o
	$(NVFORTRAN) $(NVFFLAGS) -module $(N) -c -o $@ $<

$(N)/tandem_rng_device.o: cuda/tandem_rng_device.cuf | $(N)
	$(NVFORTRAN) $(NVFFLAGS) -module $(N) -c -o $@ $<

$(N)/tandem_rng_cuda_arrays.o: cuda/tandem_rng_cuda_arrays.cuf $(N)/tandem_rng_cuda.o
	$(NVFORTRAN) $(NVFFLAGS) -module $(N) -c -o $@ $<

$(N)/vectors.o: test/vectors.f90 | $(N)
	$(NVFORTRAN) $(NVFFLAGS) -module $(N) -c -o $@ $<

$(N)/cross.o: test/cross.f90 | $(N)
	$(NVFORTRAN) $(NVFFLAGS) -module $(N) -c -o $@ $<

$(N)/test_device: cuda/test_device.cuf $(NOBJS)
	$(NVFORTRAN) $(NVFFLAGS) -module $(N) -o $@ $< $(NOBJS) -lstdc++ -lm

test-device: $(N)/test_device
	./$(N)/test_device

$(N)/bench_device: cuda/bench_device.cuf $(NOBJS)
	$(NVFORTRAN) $(NVFFLAGS) -module $(N) -o $@ $< $(NOBJS) -lstdc++ -lm

bench-device: $(N)/bench_device
	./$(N)/bench_device

clean:
	rm -rf $(B)
