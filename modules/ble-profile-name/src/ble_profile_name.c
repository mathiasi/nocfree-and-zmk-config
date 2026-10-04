/*
 * SPDX-License-Identifier: MIT
 *
 * Name the advertised Bluetooth device after the active profile.
 *
 * ZMK advertises CONFIG_BT_DEVICE_NAME for every profile, so all five slots
 * look like one device to a host and there is no way to tell which one you
 * are pairing. The factory firmware names them per slot ("NocFree & BLE3"),
 * and this restores that.
 *
 * Profiles are numbered from 1 here, not 0, so the name matches the key that
 * selects it: Fn+1 selects ZMK profile 0 and advertises "... BLE1".
 *
 * zmk_ble_set_device_name() does the work -- it sets the name, stops
 * advertising if it is running, and restarts it so the new name is actually
 * in the advertising data. Renaming only affects what a host records when it
 * pairs; an existing pairing keeps the name it was stored under.
 */

#include <stdio.h>

#include <zephyr/kernel.h>
#include <zephyr/init.h>
#include <zephyr/logging/log.h>

#include <zmk/ble.h>
#include <zmk/event_manager.h>
#include <zmk/events/ble_active_profile_changed.h>

LOG_MODULE_REGISTER(nocfree_ble_name, CONFIG_ZMK_LOG_LEVEL);

/* bt_set_name() copies the string, but keep the buffer static anyway: it is
 * written from a work queue and is not worth putting on that stack. */
static char name_buf[CONFIG_BT_DEVICE_NAME_MAX + 1];

static void apply_name(uint8_t index) {
    /* snprintf truncates rather than overflowing if BT_DEVICE_NAME is long
     * enough that the suffix does not fit in BT_DEVICE_NAME_MAX. */
    snprintf(name_buf, sizeof(name_buf), "%s BLE%u", CONFIG_BT_DEVICE_NAME, index + 1U);

    int err = zmk_ble_set_device_name(name_buf);
    if (err) {
        LOG_ERR("Failed to set device name to %s (err %d)", name_buf, err);
        return;
    }

    LOG_DBG("Advertising as %s", name_buf);
}

static int on_profile_changed(const zmk_event_t *eh) {
    const struct zmk_ble_active_profile_changed *ev = as_zmk_ble_active_profile_changed(eh);

    if (ev == NULL) {
        return ZMK_EV_EVENT_BUBBLE;
    }

    apply_name(ev->index);

    return ZMK_EV_EVENT_BUBBLE;
}

ZMK_LISTENER(nocfree_ble_name, on_profile_changed);
ZMK_SUBSCRIPTION(nocfree_ble_name, zmk_ble_active_profile_changed);

/* ZMK raises a profile-changed event during its own BLE init, which covers
 * the normal boot. This is a belt-and-braces pass for the case where that
 * ordering ever changes: it runs after ZMK's BLE init at the same level, and
 * a failure here is logged and ignored rather than blocking startup. */
static int nocfree_ble_name_init(void) {
    int index = zmk_ble_active_profile_index();

    if (index < 0) {
        LOG_DBG("No active profile yet; leaving the name to the event");
        return 0;
    }

    apply_name((uint8_t)index);

    return 0;
}

SYS_INIT(nocfree_ble_name_init, APPLICATION, CONFIG_APPLICATION_INIT_PRIORITY);
