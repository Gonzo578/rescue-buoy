/*
 * Copyright (c) 2026 Ralf Hochhausen
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Increment 1: prove out the toolchain, the dev container and the board by
 * logging "Hello World!" to the serial console and blinking an LED at 1 Hz.
 */

#include <errno.h>

#include <zephyr/kernel.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(main, LOG_LEVEL_INF);

/* Half a period on, half a period off -> 1 Hz. */
#define BLINK_PERIOD_MS 500U

/* Resolved from the led0 alias, which the board overlay provides. */
static const struct gpio_dt_spec led = GPIO_DT_SPEC_GET(DT_ALIAS(led0), gpios);

int main(void)
{
	int ret;

	LOG_INF("Hello World! %s", CONFIG_BOARD_TARGET);

	if (!gpio_is_ready_dt(&led)) {
		LOG_ERR("LED device %s is not ready", led.port->name);
		return -ENODEV;
	}

	ret = gpio_pin_configure_dt(&led, GPIO_OUTPUT_INACTIVE);
	if (ret < 0) {
		LOG_ERR("Failed to configure LED pin (%d)", ret);
		return ret;
	}

	LOG_INF("Blinking LED on %s pin %u every %u ms",
		led.port->name, led.pin, BLINK_PERIOD_MS);

	while (1) {
		ret = gpio_pin_toggle_dt(&led);
		if (ret < 0) {
			LOG_ERR("Failed to toggle LED (%d)", ret);
			return ret;
		}

		k_msleep(BLINK_PERIOD_MS);
	}

	return 0;
}
