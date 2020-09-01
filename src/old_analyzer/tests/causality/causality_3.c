#define bool char

struct Object1 { bool b; };
struct Object2 { int i; char *str; };

void kfree(void *);

int main() {
  struct Object1 obj1_1;
  struct Object1 obj1_2;
  struct Object2 obj2_1;

  kfree(&obj1_1);
  kfree(&obj1_2);
  kfree(&obj2_1);
}