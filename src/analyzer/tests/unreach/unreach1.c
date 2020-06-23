#include <stdlib.h>

struct lock {
	int i;
};

static void mutex_lock(struct lock *l) {
	l->i = 1;
}

static void mutex_unlock(struct lock *l) {
	l->i = 0;
}

int main(int argc, char **argv) {
  mutex_lock(NULL);
  if (argc < 2) {
    exit(1);
  }
  mutex_unlock(NULL);
  return argc;
}
