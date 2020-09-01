struct Object { int i; };

void *malloc(unsigned long size);

int main() {
    struct Object *obj1 = malloc(sizeof(struct Object));
    struct Object *obj2 = malloc(sizeof(struct Object));
    if (!obj1 || !obj2) {
        return -1;
    }
    obj1->i = 10;
    obj2->i = 20;
    return 0;
}