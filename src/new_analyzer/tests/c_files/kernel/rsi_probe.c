#define u8 unsigned char
#define u16 unsigned short
#define u32 unsigned int
#define s8 char
#define s16 short
#define s32 int
#define bool char
#define true 1
#define false 0

#define GFP_KERNEL 100
#define ENOMEM 1024
#define EINVAL 1023

#define ERR_ZONE                        0  /* For Error Msgs             */
#define INFO_ZONE                       1  /* For General Status Msgs    */
#define INIT_ZONE                       2  /* For Driver Init Seq Msgs   */
#define MGMT_TX_ZONE                    3  /* For TX Mgmt Path Msgs      */
#define MGMT_RX_ZONE                    4  /* For RX Mgmt Path Msgs      */
#define DATA_TX_ZONE                    5  /* For TX Data Path Msgs      */
#define DATA_RX_ZONE                    6  /* For RX Data Path Msgs      */
#define FSM_ZONE                        7  /* For State Machine Msgs     */
#define ISR_ZONE                        8  /* For Interrupt Msgs         */

#define FSM_CARD_NOT_READY              0
#define FSM_BOOT_PARAMS_SENT            1
#define FSM_EEPROM_READ_MAC_ADDR        2
#define FSM_RESET_MAC_SENT              3
#define FSM_RADIO_CAPS_SENT             4
#define FSM_BB_RF_PROG_SENT             5
#define FSM_MAC_INIT_DONE               6

#define RSI_MAX_VIFS                    1
#define NUM_EDCA_QUEUES                 4
#define IEEE80211_ADDR_LEN              6
#define FRAME_DESC_SZ                   16
#define MIN_802_11_HDR_LEN              24

#define DATA_QUEUE_WATER_MARK           400
#define MIN_DATA_QUEUE_WATER_MARK       300
#define MULTICAST_WATER_MARK            200
#define MAC_80211_HDR_FRAME_CONTROL     0
#define WME_NUM_AC                      4
#define NUM_SOFT_QUEUES                 5
#define MAX_HW_QUEUES                   8
#define INVALID_QUEUE                   0xff
#define MAX_CONTINUOUS_VO_PKTS          8
#define MAX_CONTINUOUS_VI_PKTS          4

/* Queue information */
#define RSI_WIFI_MGMT_Q                 0x4
#define RSI_WIFI_DATA_Q                 0x5
#define IEEE80211_MGMT_FRAME            0x00
#define IEEE80211_CTL_FRAME             0x04

#define IEEE80211_QOS_TID               0x0f
#define IEEE80211_NONQOS_TID            16

#define MAX_DEBUGFS_ENTRIES             4

#define TID_TO_WME_AC(_tid) (      \
	((_tid) == 0 || (_tid) == 3) ? BE_Q : \
	((_tid) < 3) ? BK_Q : \
	((_tid) < 6) ? VI_Q : \
	VO_Q)

#define WME_AC(_q) (    \
	((_q) == BK_Q) ? IEEE80211_AC_BK : \
	((_q) == BE_Q) ? IEEE80211_AC_BE : \
	((_q) == VI_Q) ? IEEE80211_AC_VI : \
	IEEE80211_AC_VO)

struct mutex {
    int i;
};

#define atomic_t int

#define wait_queue_head_t char

struct completion {};

struct sk_buff_head {};

struct ieee80211_tx_queue_params {};

#define IEEE80211_NUM_BANDS 1024

#define __le16 short

struct ieee80211_supported_band {};

void kfree(void *);

void *kzalloc(unsigned long size, int flags);

struct urb {
    void *transfer_buffer;
};

struct usb_interface {
    void *dev;
};

struct version_info {
	u16 major;
	u16 minor;
	u16 release_num;
	u16 patch_num;
} __packed;

struct skb_info {
	s8 rssi;
	u32 flags;
	u16 channel;
	s8 tid;
	s8 sta_id;
};

enum edca_queue {
	BK_Q,
	BE_Q,
	VI_Q,
	VO_Q,
	MGMT_SOFT_Q
};

struct security_info {
	bool security_enable;
	u32 ptk_cipher;
	u32 gtk_cipher;
};

struct wmm_qinfo {
	s32 weight;
	s32 wme_params;
	s32 pkt_contended;
	s32 txop;
};

struct transmit_q_stats {
	u32 total_tx_pkt_send[NUM_EDCA_QUEUES + 1];
	u32 total_tx_pkt_freed[NUM_EDCA_QUEUES + 1];
};

struct vif_priv {
	bool is_ht;
	bool sgi;
	u16 seq_start;
};

struct rsi_event {
	atomic_t event_condition;
	wait_queue_head_t event_queue;
};

struct rsi_thread {
	void (*thread_function)(void *);
	struct completion completion;
	struct task_struct *task;
	struct rsi_event event;
	atomic_t thread_done;
};

struct cqm_info {
	s8 last_cqm_event_rssi;
	int rssi_thold;
	u32 rssi_hyst;
};

struct rsi_hw;

struct rsi_common {
	struct rsi_hw *priv;
	struct vif_priv vif_info[RSI_MAX_VIFS];

	bool mgmt_q_block;
	struct version_info driver_ver;
	struct version_info fw_ver;

	struct rsi_thread tx_thread;
	struct sk_buff_head tx_queue[NUM_EDCA_QUEUES + 1];
	/* Mutex declaration */
	struct mutex mutex;
	/* Mutex used between tx/rx threads */
	struct mutex tx_rxlock;
	u8 endpoint;

	/* Channel/band related */
	u8 band;
	u8 channel_width;

	u16 rts_threshold;
	u16 bitrate_mask[2];
	u32 fixedrate_mask[2];

	u8 rf_reset;
	struct transmit_q_stats tx_stats;
	struct security_info secinfo;
	struct wmm_qinfo tx_qinfo[NUM_EDCA_QUEUES];
	struct ieee80211_tx_queue_params edca_params[NUM_EDCA_QUEUES];
	u8 mac_addr[IEEE80211_ADDR_LEN];

	/* state related */
	u32 fsm_state;
	bool init_done;
	u8 bb_rf_prog_count;
	bool iface_down;

	/* Generic */
	u8 channel;
	u8 *rx_data_pkt;
	u8 mac_id;
	u8 radio_id;
	u16 rate_pwr[20];
	u16 min_rate;

	/* WMM algo related */
	u8 selected_qnum;
	u32 pkt_cnt;
	u8 min_weight;

	/* bgscan related */
	struct cqm_info cqm_info;

	bool hw_data_qs_blocked;
};

struct rsi_hw {
	struct rsi_common *priv;
	struct ieee80211_hw *hw;
	struct ieee80211_vif *vifs[RSI_MAX_VIFS];
	struct ieee80211_tx_queue_params edca_params[NUM_EDCA_QUEUES];
	struct ieee80211_supported_band sbands[IEEE80211_NUM_BANDS];

	struct device *device;
	u8 sc_nvifs;

	void *rsi_dev;
	int (*host_intf_read_pkt)(struct rsi_hw *adapter, u8 *pkt, u32 len);
	int (*host_intf_write_pkt)(struct rsi_hw *adapter, u8 *pkt, u32 len);
	int (*check_hw_queue_status)(struct rsi_hw *adapter, u8 q_num);
	int (*rx_urb_submit)(struct rsi_hw *adapter);
	int (*determine_event_timeout)(struct rsi_hw *adapter);
};

#define USB_INTERNAL_REG_1           0x25000
#define RSI_USB_READY_MAGIC_NUM      0xab
#define FW_STATUS_REG                0x41050012

#define USB_VENDOR_REGISTER_READ     0x15
#define USB_VENDOR_REGISTER_WRITE    0x16
#define RSI_USB_TX_HEAD_ROOM         128

#define MAX_RX_URBS                  1
#define MAX_BULK_EP                  8
#define MGMT_EP                      1
#define DATA_EP                      2

struct rsi_91x_usbdev {
	struct rsi_thread rx_thread;
	u8 endpoint;
	struct usb_device *usbdev;
	struct usb_interface *pfunction;
	struct urb *rx_usb_urb[MAX_RX_URBS];
	u8 *tx_buffer;
	__le16 bulkin_size;
	u8 bulkin_endpoint_addr;
	__le16 bulkout_size[MAX_BULK_EP];
	u8 bulkout_endpoint_addr[MAX_BULK_EP];
	u32 tx_blk_size;
	u8 write_fail;
};

int rsi_rx_urb_submit(struct rsi_hw *adapter);

int rsi_usb_check_queue_status(struct rsi_hw *adapter, u8 q_num);

int rsi_usb_host_intf_write_pkt(struct rsi_hw *adapter, u8 *pkt, u32 len);

void rsi_usb_rx_thread(struct rsi_common *common);

int rsi_usb_event_timeout(struct rsi_hw *adapter);

void rsi_deinit_usb_interface(struct rsi_hw *adapter);
int rsi_usb_device_init(struct rsi_common *common);
struct rsi_hw *rsi_91x_init();

void rsi_91x_deinit(struct rsi_hw *adapter)
{
	struct rsi_common *common = adapter->priv;
	u8 ii;

	rsi_dbg(INFO_ZONE, "%s: Performing deinit os ops\n", __func__);

	rsi_kill_thread(&common->tx_thread);

	for (ii = 0; ii < NUM_SOFT_QUEUES; ii++)
		skb_queue_purge(&common->tx_queue[ii]);

	common->init_done = false;

	kfree(common);
	kfree(adapter->rsi_dev);
	kfree(adapter);
}

int rsi_init_usb_interface(struct rsi_hw *adapter,
				  struct usb_interface *pfunction)
{
	struct rsi_91x_usbdev *rsi_dev;
	struct rsi_common *common = adapter->priv;
	int status;

	rsi_dev = kzalloc(sizeof(*rsi_dev), GFP_KERNEL);
	if (!rsi_dev)
		return -ENOMEM;

	adapter->rsi_dev = rsi_dev;
	rsi_dev->usbdev = interface_to_usbdev(pfunction);

	if (rsi_find_bulk_in_and_out_endpoints(pfunction, adapter))
		return -EINVAL;

	adapter->device = &pfunction->dev;
	usb_set_intfdata(pfunction, adapter);

	common->rx_data_pkt = kmalloc(2048, GFP_KERNEL);
	if (!common->rx_data_pkt) {
		rsi_dbg(ERR_ZONE, "%s: Failed to allocate memory\n",
			__func__);
		return -ENOMEM;
	}

	rsi_dev->tx_buffer = kmalloc(2048, GFP_KERNEL);
	if (!rsi_dev->tx_buffer) {
		status = -ENOMEM;
		goto fail_tx;
	}
	rsi_dev->rx_usb_urb[0] = usb_alloc_urb(0, GFP_KERNEL);
	if (!rsi_dev->rx_usb_urb[0]) {
		status = -ENOMEM;
		goto fail_rx;
	}
	rsi_dev->rx_usb_urb[0]->transfer_buffer = adapter->priv->rx_data_pkt;
	rsi_dev->tx_blk_size = 252;

	/* Initializing function callbacks */
	adapter->rx_urb_submit = rsi_rx_urb_submit;
	adapter->host_intf_write_pkt = rsi_usb_host_intf_write_pkt;
	adapter->check_hw_queue_status = rsi_usb_check_queue_status;
	adapter->determine_event_timeout = rsi_usb_event_timeout;

	rsi_init_event(&rsi_dev->rx_thread.event);
	status = rsi_create_kthread(common, &rsi_dev->rx_thread,
				    rsi_usb_rx_thread, "RX-Thread");
	if (status) {
		rsi_dbg(ERR_ZONE, "%s: Unable to init rx thrd\n", __func__);
		goto fail_thread;
	}

#ifdef CONFIG_RSI_DEBUGFS
	/* In USB, one less than the MAX_DEBUGFS_ENTRIES entries is required */
	adapter->num_debugfs_entries = (MAX_DEBUGFS_ENTRIES - 1);
#endif

	rsi_dbg(INIT_ZONE, "%s: Enabled the interface\n", __func__);
	return 0;

fail_thread:
	usb_free_urb(rsi_dev->rx_usb_urb[0]);
fail_rx:
	kfree(rsi_dev->tx_buffer);
fail_tx:
	kfree(common->rx_data_pkt);
	return status;
}

int rsi_probe(struct usb_interface *pfunction,
		     const struct usb_device_id *id)
{
	struct rsi_hw *adapter;
	struct rsi_91x_usbdev *dev;
	u16 fw_status;
	int status;

	rsi_dbg(INIT_ZONE, "%s: Init function called\n", __func__);

	adapter = rsi_91x_init();
	if (!adapter) {
		rsi_dbg(ERR_ZONE, "%s: Failed to init os intf ops\n",
			__func__);
		return -ENOMEM;
	}

	status = rsi_init_usb_interface(adapter, pfunction);
	if (status) {
		rsi_dbg(ERR_ZONE, "%s: Failed to init usb interface\n",
			__func__);
		goto err;
	}

	rsi_dbg(ERR_ZONE, "%s: Initialized os intf ops\n", __func__);

	dev = (struct rsi_91x_usbdev *)adapter->rsi_dev;

	status = rsi_usb_reg_read(dev->usbdev, FW_STATUS_REG, &fw_status, 2);
	if (status)
		goto err1;
	else
		fw_status &= 1;

	if (!fw_status) {
		status = rsi_usb_device_init(adapter->priv);
		if (status) {
			rsi_dbg(ERR_ZONE, "%s: Failed in device init\n",
				__func__);
			goto err1;
		}

		status = rsi_usb_reg_write(dev->usbdev,
					   USB_INTERNAL_REG_1,
					   RSI_USB_READY_MAGIC_NUM, 1);
		if (status)
			goto err1;
		rsi_dbg(INIT_ZONE, "%s: Performed device init\n", __func__);
	}

	status = rsi_rx_urb_submit(adapter);
	if (status)
		goto err1;

	return 0;
err1:
	rsi_deinit_usb_interface(adapter);
err:
	rsi_91x_deinit(adapter);
	rsi_dbg(ERR_ZONE, "%s: Failed in probe...Exiting\n", __func__);
	return status;
}