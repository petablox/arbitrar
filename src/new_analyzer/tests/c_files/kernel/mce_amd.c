#define u8 char
#define u16 short
#define bool char

#define NULL 0

#define ENODEV -1000
#define ENOMEM -1010

#define GFP_KERNEL 10
#define X86_VENDOR_AMD 20

struct cpuinfo_x86 {
	int x86_vendor;
	int x86;
	int x86_model;
};

struct amd_decoder_ops {
	bool (* mc0_mce)(u16, u8);
	bool (* mc1_mce)(u16, u8);
	bool (* mc2_mce)(u16, u8);
};

struct notifier_block {

};

bool k8_mc0_mce(u16 ec, u8 xec);

bool k8_mc1_mce(u16 ec, u8 xec);

bool k8_mc2_mce(u16 ec, u8 xec);

bool f10h_mc0_mce(u16 ec, u8 xec);

bool f12h_mc0_mce(u16 ec, u8 xec);

bool f15h_mc0_mce(u16 ec, u8 xec);

bool f15h_mc1_mce(u16 ec, u8 xec);

bool f15h_mc2_mce(u16 ec, u8 xec);

bool f16h_mc2_mce(u16 ec, u8 xec);

bool cat_mc0_mce(u16 ec, u8 xec);

bool cat_mc1_mce(u16 ec, u8 xec);

void mce_register_decode_chain(struct notifier_block *);

void *kzalloc(int size, int flag);

int printk(const char * format, ...);

void kfree(void *);

void pr_info(const char *);

struct notifier_block amd_mce_dec_nb;

struct cpuinfo_x86 boot_cpu_data;

struct amd_decoder_ops *fam_ops;

int xec_mask;

int mce_amd_init(void) {
	struct cpuinfo_x86 *c = &boot_cpu_data;

	if (c->x86_vendor != X86_VENDOR_AMD)
		return -ENODEV;

	fam_ops = kzalloc(sizeof(struct amd_decoder_ops), GFP_KERNEL);
	if (!fam_ops)
		return -ENOMEM;

	switch (c->x86) {
	case 0xf:
		fam_ops->mc0_mce = k8_mc0_mce;
		fam_ops->mc1_mce = k8_mc1_mce;
		fam_ops->mc2_mce = k8_mc2_mce;
		break;

	case 0x10:
		fam_ops->mc0_mce = f10h_mc0_mce;
		fam_ops->mc1_mce = k8_mc1_mce;
		fam_ops->mc2_mce = k8_mc2_mce;
		break;

	case 0x11:
		fam_ops->mc0_mce = k8_mc0_mce;
		fam_ops->mc1_mce = k8_mc1_mce;
		fam_ops->mc2_mce = k8_mc2_mce;
		break;

	case 0x12:
		fam_ops->mc0_mce = f12h_mc0_mce;
		fam_ops->mc1_mce = k8_mc1_mce;
		fam_ops->mc2_mce = k8_mc2_mce;
		break;

	case 0x14:
		fam_ops->mc0_mce = cat_mc0_mce;
		fam_ops->mc1_mce = cat_mc1_mce;
		fam_ops->mc2_mce = k8_mc2_mce;
		break;

	case 0x15:
		xec_mask = c->x86_model == 0x60 ? 0x3f : 0x1f;

		fam_ops->mc0_mce = f15h_mc0_mce;
		fam_ops->mc1_mce = f15h_mc1_mce;
		fam_ops->mc2_mce = f15h_mc2_mce;
		break;

	case 0x16:
		xec_mask = 0x1f;
		fam_ops->mc0_mce = cat_mc0_mce;
		fam_ops->mc1_mce = cat_mc1_mce;
		fam_ops->mc2_mce = f16h_mc2_mce;
		break;

	default:
		printk("Huh? What family is it: 0x%x?!\n", c->x86);
		kfree(fam_ops);
		fam_ops = NULL;
	}

	pr_info("MCE: In-kernel MCE decoding enabled.\n");

	mce_register_decode_chain(&amd_mce_dec_nb);

	return 0;
}