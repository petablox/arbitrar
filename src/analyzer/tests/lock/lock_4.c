typedef struct mutex_lock {
   int i;
} mutex_lock;

void lock(mutex_lock *lock) {
    lock->i = 0;
}

void unlock(mutex_lock *lock) {
    lock->i = 1;
}

void run(int i) {
    mutex_lock l;
    lock(&l);
    int b = 3;
    for (; i < 10; i++) {
        b += i;
    }
    unlock(&l);
}