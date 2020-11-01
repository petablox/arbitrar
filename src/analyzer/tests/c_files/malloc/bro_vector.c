#define NULL 0

struct BroVector {
  int something;
};

struct BroVector *
__bro_vector_new(void)
	{
	struct BroVector *rec;

	if (! (rec = calloc(1, sizeof(struct BroVector))))
		return NULL;

	return rec;
	}