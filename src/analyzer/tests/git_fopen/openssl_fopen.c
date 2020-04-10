void *openssl_fopen(char *, char *);

void exit(int);

void fwrite(void *, char *);

void fclose(void *);

void good_1() {
  void *in;
  in = openssl_fopen("temp.txt", "w");
  if (!in) return;
  fwrite(in, "asdfasdfadsfasdf");
  fclose(in);
}

void bad_5() {
  void *in;
  in = openssl_fopen("temp.txt", "w");
}

void bad_4() {
  void *in;
  in = openssl_fopen("temp.txt", "w");
  if (!in) {
    fwrite(in, "asdfasf"); // Cannot write with null file pointer
  }
  fclose(in);
}

void bad_3() {
  void *in;
  in = openssl_fopen("temp.txt", "w");
  if (!in) {
    fclose(in); // Cannot close null file pointer
  }
  fclose(in);
}

void bad_2() {
  void *in;
  in = openssl_fopen("temp.txt", "w");
  if (!in) {
    exit(1);
  }
  // Doesn't close file
}

void bad_1() {
  void *in;
  in = openssl_fopen("temp.txt", "w");
  // Doesn't check file pointer
  fwrite(in, "asdfadfs");
  fclose(in);
}
