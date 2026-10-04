# Known nvfortran 25.3 defects

- `select rank` does not compile, and a `bind(C)` dummy procedure is called wrongly, so
  the code selects among specific procedures instead.
- `-O2` miscompiles the step function of `tandem_rng_target` when it updates the elements of
  its `h(4)` argument in place, in offloaded code only. It uses scalar temporaries instead.
- `c_loc` and `c_devloc` of an assumed-rank argument of rank 2 and up return the address of
  the element at index zero in every dimension, not of the first element. With its GPU flags,
  a C descriptor of the argument is wrong too. The device array fills therefore have one
  specific per rank, and the host fills of rank 2 and up stop with an error under nvfortran.
  Fill a rank 1 pointer to the array there, `p(1:size(a)) => a`.
