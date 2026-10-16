__kernel void add_one(__global int *d_vals, const int N) {
  int i = get_global_id(0);
  if (i < N) {
    d_vals[i] += 1;
  }
}