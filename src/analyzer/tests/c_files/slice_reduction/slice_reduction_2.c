struct Object {
    int i;
    char *str;
};

struct AnotherObject {};

void f(struct Object *);

void g(int, struct Object *);

struct Object *h(int);

void x();

struct AnotherObject *y(char bool);

void z(int);

void b(struct Object *obj) {
    obj->i = 0;
    obj->str = "asdadf";
    f(&obj);
}

void c(struct Object *obj) {
    g(3, &obj);
    struct Object *obj2 = h(5);
}

int a() {
    struct Object obj;
    b(&obj);
    c(&obj);
}