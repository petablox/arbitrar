#define uint16_t short
#define uint32_t int
#define false 0
#define true 1
#define bool char
#define NULL 0
#define EINVAL 1000
#define GFP_KERNEL 10000

struct table_entry {
  uint16_t value;
  int smio_low;
};

struct pp_atomctrl_voltage_table {
  int mask_low;
  int phase_delay;
  int count;
  struct table_entry *entries;
};

void kfree(void *p);
void memcpy(void *src, void *dst, int size);
void *kzalloc(int size, int gfp);

int phm_trim_voltage_table(struct pp_atomctrl_voltage_table *vol_table)
{
	uint32_t i, j;
	uint16_t vvalue;
	bool found = false;
	struct pp_atomctrl_voltage_table *table;

	// PP_ASSERT_WITH_CODE((NULL != vol_table),
	// 		"Voltage Table empty.", return -EINVAL);

	table = kzalloc(sizeof(struct pp_atomctrl_voltage_table), GFP_KERNEL);

	if (NULL == table)
		return -EINVAL;

	table->mask_low = vol_table->mask_low;
	table->phase_delay = vol_table->phase_delay;

	for (i = 0; i < vol_table->count; i++) {
		vvalue = vol_table->entries[i].value;
		found = false;

		for (j = 0; j < table->count; j++) {
			if (vvalue == table->entries[j].value) {
				found = true;
				break;
			}
		}

		if (!found) {
			table->entries[table->count].value = vvalue;
			table->entries[table->count].smio_low =
					vol_table->entries[i].smio_low;
			table->count++;
		}
	}

	memcpy(vol_table, table, sizeof(struct pp_atomctrl_voltage_table));
	kfree(table);

	return 0;
}