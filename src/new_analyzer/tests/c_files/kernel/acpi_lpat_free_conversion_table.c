void kfree(void *ptr);

struct acpi_lpat_conversion_table {
    void *lpat;
};

void acpi_lpat_free_conversion_table(struct acpi_lpat_conversion_table *lpat_table) {
	if (lpat_table) {
		kfree(lpat_table->lpat);
		kfree(lpat_table);
	}
}