struct Object {
    int index;
    char *str;
};

void *kzalloc(int size);

void kfree(void *ptr);

int main() {
    struct Object *obj = (struct Object *) kzalloc(sizeof(struct Object));
    obj->index = 10;
    obj->str = (char *) kzalloc(100);
    obj->index += 100;
    kfree(obj);
}