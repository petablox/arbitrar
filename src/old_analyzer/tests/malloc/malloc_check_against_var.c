struct obj {
    struct obj *child;
    int length;
};

void *malloc(int size);

void caller(struct obj *o) {
    struct obj *ptr = malloc(10);
    if (ptr >= o->child) {
        return;
    }
    ptr->length = 10;
    return;
}