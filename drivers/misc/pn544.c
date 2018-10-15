/*
 * Copyright (C) 2010 Trusted Logic S.A.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA
 *
 */

#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/slab.h>
#include <linux/init.h>
#include <linux/list.h>
#include <linux/i2c.h>
#include <linux/irq.h>
#include <linux/jiffies.h>
#include <linux/uaccess.h>
#include <linux/delay.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/platform_device.h>
#include <linux/gpio.h>
#include <linux/miscdevice.h>
#include <linux/spinlock.h>
#include <linux/pn544.h>
#include <linux/of_gpio.h>
#include <linux/wakelock.h>

#define PN544_NAME "pn544"

#define MAX_BUFFER_SIZE	512
#define GPIO_SHIFT(x) (((x-902) < 0)?0:(x-902))

struct pn544_dev {
	wait_queue_head_t read_wq;
	struct mutex read_mutex;
	struct i2c_client *client;
	struct miscdevice pn544_device;
	int ven_gpio;
	int firm_gpio;
	int irq_gpio;
	bool irq_enabled;
	bool IsPrbsTestMode;
	spinlock_t irq_enabled_lock;
	unsigned int pn544_sys_info;
	atomic_t balance_wake_irq;
	struct wake_lock normal_wakelock; /*wake lock for interrupt event*/
};

#define DEBUG_BIT			BIT(0)
#define IRQ_GPIO_BIT		BIT(1)
#define DEFAULT_INFO_VALUE	(0x00)
#define I2C_RETRY_TIME		0

static ssize_t pn544_info_show(struct device *dev,
		struct device_attribute *attr, char *buf)
{
	struct pn544_dev *pn544_dev = dev_get_drvdata(dev);

	if (!pn544_dev) {
		pr_err("%s: invalid device data!\n", __func__);
		return -EIO;
	}

	/*Dump interrupt PIN GPIO State*/
	if (pn544_dev->pn544_sys_info & IRQ_GPIO_BIT)
		pr_info("%s:IRQ GPIO State: %d\n", __func__,
			gpio_get_value(pn544_dev->irq_gpio));

	return snprintf(buf, PAGE_SIZE, "INFO_Setting: 0x%02X, IRQ_GPIO: %s\n",
			pn544_dev->pn544_sys_info,
			gpio_get_value(pn544_dev->irq_gpio) ? "High" : "Low");

}

static ssize_t pn544_info_store(struct device *dev,
		struct device_attribute *attr, const char *buf, size_t count)
{
	struct pn544_dev *pn544_dev = dev_get_drvdata(dev);
	int ret = 0;
	unsigned long val = 0;

	if (!pn544_dev) {
		pr_err("%s: invalid device data!\n", __func__);
		return -EIO;
	}

	ret = kstrtoul(buf, 10, &val);
	if (ret) {
		pr_err("%s: Get buffer data error! (%d)\n", __func__, ret);
		return ret;
	}

	/*Get new settings value*/
	pn544_dev->pn544_sys_info = val;

	return count;
}

DEVICE_ATTR(info, 0644, pn544_info_show, pn544_info_store);

static struct attribute *pn544_attributes[] = {
	&dev_attr_info.attr,
	NULL
};

static const struct attribute_group pn544_attr_group = {
	.attrs = pn544_attributes,
};

static void pn544_disable_irq(struct pn544_dev *pn544_dev)
{
	unsigned long flags;

	spin_lock_irqsave(&pn544_dev->irq_enabled_lock, flags);
	if (pn544_dev->irq_enabled) {
		disable_irq_nosync(pn544_dev->client->irq);
		pn544_dev->irq_enabled = false;
	}
	spin_unlock_irqrestore(&pn544_dev->irq_enabled_lock, flags);
}

static irqreturn_t pn544_dev_irq_handler(int irq, void *dev_id)
{
	struct pn544_dev *pn544_dev = dev_id;

	pn544_disable_irq(pn544_dev);

	/* Wake up waiting readers */
	wake_up(&pn544_dev->read_wq);

	/* hold a wakelock
	 * prevent suspend for 5 seconds
	 */
	wake_lock_timeout(&pn544_dev->normal_wakelock, 5 * HZ);

	return IRQ_HANDLED;
}

static ssize_t pn544_dev_read(struct file *filp, char __user *buf,
		size_t count, loff_t *offset)
{
	struct pn544_dev *pn544_dev = filp->private_data;
	char tmp[MAX_BUFFER_SIZE];
	int ret = 0x00;
	int retry = 0;

	if (count > MAX_BUFFER_SIZE)
		count = MAX_BUFFER_SIZE;

	pr_debug("%s: reading %zu bytes.\n", __func__, count);

	if (pn544_dev != NULL && pn544_dev->IsPrbsTestMode == true) {
		pr_info("%s: In Test Mode, ignore...\n", __func__);
	return 0;
	}

	mutex_lock(&pn544_dev->read_mutex);
	/* Check GPIO Value, if low we start to wait,
	 * else trigger read via i2c bus
	 */
	if (!gpio_get_value(pn544_dev->irq_gpio)) {
		if (filp->f_flags & O_NONBLOCK) {
			pr_info("%s: Return because of filp->f_flags & O_NONBLOCK...\n",
				__func__);
			ret = -EAGAIN;
			goto fail;
		}

		while (1) {
			pn544_dev->irq_enabled = true;
			enable_irq(pn544_dev->client->irq);
			ret = wait_event_interruptible(pn544_dev->read_wq,
					!pn544_dev->irq_enabled);
			pn544_disable_irq(pn544_dev);

			if (ret)
				goto fail;

			if (gpio_get_value(pn544_dev->irq_gpio) || ret == 0x00)
				break;

			pr_info("%s: continous wait for reading\n", __func__);
		}
	}

	/*Check if GPIO high and ready to operate*/
	if (atomic_read(&pn544_dev->balance_wake_irq) != 1) {
		pr_err("%s: NFC not power on!", __func__);
		ret = -EIO;
		goto fail;
	}

	/* Read data */
	ret = i2c_master_recv(pn544_dev->client, tmp, count);

	while (ret < 0 && retry < I2C_RETRY_TIME) {
		pr_err("%s: read data bus err! retry: %d\n", __func__, retry);
		retry++;
		ret = i2c_master_recv(pn544_dev->client, tmp, count);
	}
	mutex_unlock(&pn544_dev->read_mutex);

	if (ret < 0) {
		pr_err("%s: i2c_master_recv returned %d\n", __func__, ret);
		goto free_memory;
	}
	if (ret > count) {
		pr_err("%s: received too many bytes from i2c (%d)\n",
			__func__, ret);
		return -EIO;
		goto free_memory;
	}
	if (copy_to_user(buf, tmp, ret)) {
		pr_warn("%s : failed to copy to user space\n", __func__);
		return -EFAULT;
		goto free_memory;
	}

free_memory:
	kfree(tmp);
	return ret;

fail:
	mutex_unlock(&pn544_dev->read_mutex);
	return ret;
}

static ssize_t pn544_dev_write(struct file *filp, const char __user *buf,
		size_t count, loff_t *offset)
{
	struct pn544_dev *pn544_dev;
	char tmp[MAX_BUFFER_SIZE];
	int ret;
	int retry = 0;

	pn544_dev = filp->private_data;

	if (count > MAX_BUFFER_SIZE)
		count = MAX_BUFFER_SIZE;

	if (copy_from_user(tmp, buf, count)) {
		pr_err("%s: failed to copy from user space\n", __func__);
		return -EFAULT;
		goto free_memory;
	}

	pr_debug("%s: writing %zu bytes.\n", __func__, count);

	/*Check if GPIO high and ready to operate*/
	if (atomic_read(&pn544_dev->balance_wake_irq) != 1) {
		pr_err("%s: NFC not power on!", __func__);
		return -EIO;
		goto free_memory;
	}

	/* Write data */
	ret = i2c_master_send(pn544_dev->client, tmp, count);
	while (ret < 0 && retry < I2C_RETRY_TIME) {
		pr_err("%s: write data bus error!, retry: %d\n",
			__func__, retry);
		ret = i2c_master_send(pn544_dev->client, tmp, count);
		retry++;
	}
	if (ret != count) {
		pr_err("%s : i2c_master_send returned %d\n", __func__, ret);
		ret = -EIO;
	}

	/*Workaround for PN547C2 standby mode, when detect i2c error*/
	if (ret < 0) {
		pr_info("%s: Waiting 1ms to wakup NXP PN547C2 from standby...\n",
			__func__);
		usleep(1000 * 1); //wait for standby to wakeup
	}

free_memory:
	kfree(tmp);
	return ret;
}

static int pn544_dev_open(struct inode *inode, struct file *filp)
{

	struct pn544_dev *pn544_dev = container_of(filp->private_data,
		struct pn544_dev, pn544_device);

	filp->private_data = pn544_dev;

	pr_debug("%s: %d,%d\n", __func__, imajor(inode), iminor(inode));

	return 0;
}

static long pn544_dev_ioctl(struct file *filp, unsigned int cmd,
		unsigned long arg)
{
	struct pn544_dev *pn544_dev = filp->private_data;

	switch (cmd) {
	case PN544_SET_PWR:
		if (arg == 2) {
			/* power on with firmware download (requires hw reset)
			 */
			pr_info("%s: power on with firmware\n", __func__);
			gpio_set_value(pn544_dev->ven_gpio, 1);
			gpio_set_value(pn544_dev->firm_gpio, 1);
			msleep(20);
			gpio_set_value(pn544_dev->ven_gpio, 0);
			msleep(50);
			gpio_set_value(pn544_dev->ven_gpio, 1);
			msleep(100);

			if (atomic_read(&pn544_dev->balance_wake_irq) == 0) {
				atomic_set(&pn544_dev->balance_wake_irq, 1);
				irq_set_irq_wake(pn544_dev->client->irq, 1);
				pr_info("%s: set irq wake enable\n", __func__);
			}

		} else if (arg == 1) {
			/* power on */
			pr_info("%s: power on\n", __func__);
			gpio_set_value(pn544_dev->firm_gpio, 0);
			gpio_set_value(pn544_dev->ven_gpio, 1);
			msleep(100);

			if (atomic_read(&pn544_dev->balance_wake_irq) == 0) {
				atomic_set(&pn544_dev->balance_wake_irq, 1);
				irq_set_irq_wake(pn544_dev->client->irq, 1);
				pr_info("%s: set irq wake enable\n", __func__);
			}

		} else if (arg == 0) {
			if (atomic_read(&pn544_dev->balance_wake_irq) == 1) {
				atomic_set(&pn544_dev->balance_wake_irq, 0);
				irq_set_irq_wake(pn544_dev->client->irq, 0);
				pr_info("%s: set irq wake disable\n", __func__);
			}
			pn544_dev->IsPrbsTestMode = false;

			/* power off */
			pr_info("%s: power off\n", __func__);
			gpio_set_value(pn544_dev->firm_gpio, 0);
			gpio_set_value(pn544_dev->ven_gpio, 0);
			msleep(100);

		} else if (arg == 3) {
			pn544_dev->IsPrbsTestMode = true;
			pr_info("%s: enable PRBS test mode!\n", __func__);

		} else {
			pr_info("%s: bad arg %lx\n", __func__, arg);
			return -EINVAL;
		}
	break;

	default:
		pr_info("%s: bad ioctl %u\n", __func__, cmd);
		return -EINVAL;
	}

	return 0;
}

static const struct file_operations pn544_dev_fops = {
	.owner	= THIS_MODULE,
	.llseek	= no_llseek,
	.read	= pn544_dev_read,
	.write	= pn544_dev_write,
	.open	= pn544_dev_open,
	.unlocked_ioctl = pn544_dev_ioctl,
	.compat_ioctl = pn544_dev_ioctl,
};

static int pn544_probe(struct i2c_client *client,
		const struct i2c_device_id *id)
{
	int ret;
	struct pn544_dev *pn544_dev;
	struct device_node *np = client->dev.of_node;

	pr_info("%s: pn544 probe\n", __func__);

	pn544_dev = kzalloc(sizeof(*pn544_dev), GFP_KERNEL);
	if (pn544_dev == NULL) {
		dev_err(&client->dev,
				"failed to allocate memory for module data\n");
		ret = -ENOMEM;
		goto err_exit;
	}
	pn544_dev->irq_gpio = of_get_named_gpio(np, "nxp,irq-gpio", 0);
	pn544_dev->ven_gpio = of_get_named_gpio(np, "nxp,vengpio", 0);
	pn544_dev->firm_gpio = of_get_named_gpio(np, "nxp,firmgpio", 0);

	pr_info("%s: [test]IRQ(%d), VEN(%d), FIRM(%d)\n",
		__func__, GPIO_SHIFT(pn544_dev->irq_gpio),
		GPIO_SHIFT(pn544_dev->ven_gpio),
		GPIO_SHIFT(pn544_dev->firm_gpio));

	if (pn544_dev->irq_gpio < 0 || pn544_dev->ven_gpio < 0
		|| pn544_dev->firm_gpio < 0) {
		pr_err("%s: [ERR]IRQ(%d), VEN(%d), FIRM(%d)\n",
			__func__, GPIO_SHIFT(pn544_dev->irq_gpio),
			GPIO_SHIFT(pn544_dev->ven_gpio),
			GPIO_SHIFT(pn544_dev->firm_gpio));
		ret = -EIO;
		goto err_exit;
	}

	//test mode flag
		pn544_dev->IsPrbsTestMode = false;

	//IRQ
	ret = gpio_request(pn544_dev->irq_gpio, "nfc_int");
	if (ret) {
		pr_err("gpio_nfc_int request error\n");
		ret = -ENODEV;
		goto err_exit;
	}
	client->irq = gpio_to_irq(pn544_dev->irq_gpio);
	gpio_direction_input(pn544_dev->irq_gpio);

	//VEN
	ret = gpio_request(pn544_dev->ven_gpio, "nfc_ven");
	if (ret) {
		pr_err("gpio_nfc_ven request error\n");
		ret = -ENODEV;
		goto err_exit;
	}
	gpio_direction_output(pn544_dev->ven_gpio, 0);

	//FIRM
	ret = gpio_request(pn544_dev->firm_gpio, "nfc_firm");
	if (ret) {
		pr_err("gpio_nfc_firm request error\n");
		ret = -ENODEV;
		goto err_exit;
	}
	gpio_direction_output(pn544_dev->firm_gpio, 0);
	if (!i2c_check_functionality(client->adapter, I2C_FUNC_I2C)) {
		pr_err("%s: need I2C_FUNC_I2C\n", __func__);
		ret =	-ENODEV;
		goto err_exit;
	}

	pn544_dev->client = client;

	/*Initialize counter of wake_irq*/
	atomic_set(&pn544_dev->balance_wake_irq, 0);

	/* init mutex and queues */
	init_waitqueue_head(&pn544_dev->read_wq);
	mutex_init(&pn544_dev->read_mutex);
	spin_lock_init(&pn544_dev->irq_enabled_lock);

	/* initial wakelock */
	wake_lock_init(&pn544_dev->normal_wakelock, WAKE_LOCK_SUSPEND,
		"pn547_transaction_wakelock");

	pn544_dev->pn544_device.minor = MISC_DYNAMIC_MINOR;
	pn544_dev->pn544_device.name = PN544_NAME;
	pn544_dev->pn544_device.fops = &pn544_dev_fops;

	ret = misc_register(&pn544_dev->pn544_device);
	if (ret) {
		pr_err("%s: misc_register failed\n", __FILE__);
		goto err_misc_register;
	}

	/* request irq.	the irq is set whenever the chip has data available
	 * for reading.	it is cleared when all data has been read.
	 */
	pr_info("%s: requesting IRQ %d\n", __func__, client->irq);
	pn544_dev->irq_enabled = true;

	ret = request_irq(client->irq, pn544_dev_irq_handler, IRQF_TRIGGER_HIGH,
		client->name, pn544_dev);
	if (ret) {
		dev_err(&client->dev, "request_irq failed\n");
		goto err_request_irq_failed;
	}

	pr_info("%s: disable IRQ\n", __func__);
	pn544_disable_irq(pn544_dev);
	i2c_set_clientdata(client, pn544_dev);

	pn544_dev->pn544_sys_info = DEFAULT_INFO_VALUE;
	ret = sysfs_create_group(&client->dev.kobj, &pn544_attr_group);
	if (ret) {
		pr_err("%s: Register device attr error! (%d)\n", __func__, ret);
		goto err_request_irq_failed;
	}

	return 0;

err_request_irq_failed:
	misc_deregister(&pn544_dev->pn544_device);
err_misc_register:
	mutex_destroy(&pn544_dev->read_mutex);
err_exit:
	if (pn544_dev != NULL) {
		gpio_free(pn544_dev->irq_gpio);
		gpio_free(pn544_dev->ven_gpio);
		gpio_free(pn544_dev->firm_gpio);
		kfree(pn544_dev);
	}
	return ret;
}

static int pn544_remove(struct i2c_client *client)
{
	struct pn544_dev *pn544_dev;

	pn544_dev = i2c_get_clientdata(client);
	free_irq(client->irq, pn544_dev);
	misc_deregister(&pn544_dev->pn544_device);
	mutex_destroy(&pn544_dev->read_mutex);
	wake_lock_destroy(&pn544_dev->normal_wakelock);
	gpio_free(pn544_dev->irq_gpio);
	gpio_free(pn544_dev->ven_gpio);
	gpio_free(pn544_dev->firm_gpio);
	kfree(pn544_dev);

	return 0;
}

static const struct i2c_device_id pn544_id[] = {
	{ PN544_NAME, 0 },
	{ }
};

static const struct of_device_id pn544_match_table[] = {
	{ .compatible = "nxp,pn544",},
	{ },
};

static struct i2c_driver pn544_driver = {
	.id_table	= pn544_id,
	.probe		= pn544_probe,
	.remove		= pn544_remove,
	.driver = {
		.owner	= THIS_MODULE,
		.of_match_table = pn544_match_table,
		.name	= PN544_NAME,
	},
};

module_i2c_driver(pn544_driver);

MODULE_AUTHOR("Sylvain Fonteneau");
MODULE_DESCRIPTION("NFC PN544 driver");
MODULE_LICENSE("GPL");
