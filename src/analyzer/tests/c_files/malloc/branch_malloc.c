int main() {
  int i = 0;
  void *ptr;
  if (i) {
    ptr = malloc(8);
  } else {
    ptr = 0;
  }
  return ptr;
}


png_byte **row = png_malloc(png_ptr, buf_size);
if (!row) {
  return ERR;
}
row[0] = PNG_FILTER_VALUE_NONE;

png_byte **row = png_malloc(png_ptr, buf_size);
row[0] = PNG_FILTER_VALUE_NONE;