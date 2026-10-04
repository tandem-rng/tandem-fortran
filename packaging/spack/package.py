# Recipe for a Spack package repository. It is not submitted to spack-packages yet.
from spack_repo.builtin.build_systems.generic import Package

from spack.package import *


class TandemFortran(Package):
    """Fortran bindings for the Tandem8x32 random number generator."""

    homepage = "https://github.com/tandem-rng/tandem-fortran"
    git = "https://github.com/tandem-rng/tandem-fortran.git"

    license("Apache-2.0")

    # No releases exist. A release adds
    # version("X.Y.Z", sha256="...", url="https://github.com/tandem-rng/tandem-fortran/archive/refs/tags/vX.Y.Z.tar.gz")
    version("main", branch="main")

    # The GPU modules need nvfortran and nvcc, and fpm cannot build them, so no cuda variant.
    depends_on("c", type="build")
    depends_on("fortran", type="build")
    # fpm links OpenMP with the build compiler, which fails with gfortran under Apple clang.
    depends_on("fpm~openmp", type="build")

    def install(self, spec, prefix):
        fpm = Executable(spec["fpm"].prefix.bin.fpm)
        fpm(
            "install",
            "--profile", "release",
            "--prefix", prefix,
            "--compiler", spack_fc,
            "--c-compiler", spack_cc,
        )

    @run_after("install")
    def check_install(self):
        if self.run_tests:
            Executable(self.spec["fpm"].prefix.bin.fpm)(
                "test", "--compiler", spack_fc, "--c-compiler", spack_cc
            )
