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

void run(int x, struct lock *l) {
  void *a = malloc(0); 
  if (x != 0)
    mutex_lock(l);
  if (x != 0)
    mutex_unlock(l);
} 
