/*
 * SPDX-License-Identifier: MIT
 *
 * Sweep every reachable GPIO looking for the PCA9555 interrupt line.
 *
 * The single-pin version of this probe watched P0.31 -- what the porting
 * guide's alias table publishes as PCA9555 INT on the left half -- and saw
 * zero edges across a session of typing, with the line sitting high on the
 * internal pull-up throughout. Either the table is wrong for this hardware or
 * the trace is not populated. This widens the search to every pin that can be
 * watched without disturbing something.
 *
 * Polled, not interrupt-driven, and that is forced. The nRF52833 has eight
 * GPIOTE channels; asking for an edge interrupt on thirty-odd pins exhausts
 * them and most of the pins silently fail to arm. Reading the whole port with
 * gpio_port_get_raw() costs one register read per port and scales to every
 * pin at once. A 1 ms sample cannot miss the pulse either: INT stays asserted
 * until the input registers are read, which is the scanner's next pass, up to
 * 10 ms away.
 *
 * Every watched pin is pulled up. That matters for a sweep: a floating
 * high-impedance input picks up noise and would count edges that mean nothing,
 * whereas a pulled-up pin with nothing on it sits still. So a non-zero count
 * here is signal, not an artefact.
 *
 * Excluded, and why -- each of these would break something or need a change
 * outside the application region:
 *
 *   P0.04, P0.05   battery ADC and divider enable, driven by the board
 *   P0.11, P1.09   I2C SDA and SCL -- the key matrix itself
 *   P0.20          backlight PWM
 *   P0.18          nRESET
 *   P0.09, P0.10   NFC antenna pins. Usable as GPIO only via
 *                  CONFIG_NFCT_PINS_AS_GPIOS, which writes UICR -- outside
 *                  the application region this firmware confines itself to.
 *                  Both are published as LED outputs anyway.
 *   P0.00, P0.01   XL1/XL2. Unused here (the board runs the RC oscillator)
 *                  but not worth grabbing on a maybe.
 */

#define DT_DRV_COMPAT nocfree_behavior_int_probe

#include <zephyr/device.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/init.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/sys/atomic.h>

#include <drivers/behavior.h>
#include <dt-bindings/zmk/hid_usage.h>
#include <dt-bindings/zmk/hid_usage_pages.h>
#include <zmk/behavior.h>
#include <zmk/behavior_queue.h>
#include <zmk/hid.h>

LOG_MODULE_REGISTER(nocfree_int_probe, CONFIG_ZMK_LOG_LEVEL);

#define TAP_MS 15
#define SAMPLE_MS 1
#define P0_PINS 32
/*
 * The pin the vendor's porting guide names as the left half's PCA9555 INT, and
 * that the factory firmware attaches a FALLING interrupt to. Its level is
 * reported directly: with the scan period widened, a line that is genuinely
 * wired should still be sitting LOW when the report is typed, because nothing
 * has read the expanders yet to clear it.
 */
#define FOCUS_PIN 31

/* Counters exported by the instrumented kscan driver. */
extern volatile uint32_t nocfree_kscan_int_fires;
extern volatile uint32_t nocfree_kscan_arm_ok;
extern volatile int32_t nocfree_kscan_arm_err;
extern volatile uint32_t nocfree_kscan_fallback_scans;
extern volatile uint32_t nocfree_kscan_late_int;
extern volatile int32_t nocfree_kscan_int_logical;
#define P1_PINS 10

#define P0_EXCLUDE                                                                                 \
    (BIT(0) | BIT(1) | BIT(4) | BIT(5) | BIT(9) | BIT(10) | BIT(11) | BIT(18) | BIT(20))
#define P0_MASK (~(uint32_t)P0_EXCLUDE)
/*
 * Pins to COUNT but never CONFIGURE.
 *
 * The kscan driver owns the INT pin and configures it GPIO_ACTIVE_LOW so its
 * logical reads mean "asserted". This module's SYS_INIT runs at APPLICATION,
 * after the driver's POST_KERNEL init, so arming the pin here with plain
 * GPIO_INPUT | GPIO_PULL_UP silently clears that invert bit -- and the driver
 * then reads an idle line as asserted, never parks on the interrupt, and
 * falls back to polling. Measured: g1 w1, logical and raw both high on a line
 * that is active low.
 *
 * A diagnostic that reconfigures what it is measuring is worse than none.
 * gpio_port_get_raw() reads the whole port regardless of who configured it,
 * so the counting below is unaffected by not touching this pin.
 */
#define P0_ARM_EXCLUDE (BIT(FOCUS_PIN))
#define P0_ARM_MASK (P0_MASK & ~(uint32_t)P0_ARM_EXCLUDE)
#define P1_MASK ((uint32_t)BIT_MASK(P1_PINS) & ~(uint32_t)BIT(9))

static const struct device *port0;
static const struct device *port1;
static uint16_t counts0[P0_PINS];
static uint16_t counts1[P1_PINS];
static atomic_t sweep_live;

static void arm_port(const struct device *port, uint32_t mask, uint8_t pins, const char *name) {
    for (uint8_t p = 0; p < pins; p++) {
        if (!(mask & BIT(p))) {
            continue;
        }
        int err = gpio_pin_configure(port, p, GPIO_INPUT | GPIO_PULL_UP);
        if (err) {
            LOG_WRN("%s.%02u will not configure as input: %d", name, p, err);
        }
    }
}

static void count_changes(uint32_t changed, uint16_t *counts, uint8_t pins) {
    for (uint8_t p = 0; p < pins; p++) {
        if ((changed & BIT(p)) && counts[p] < UINT16_MAX) {
            counts[p]++;
        }
    }
}

static void sweep_thread(void *a, void *b, void *c) {
    ARG_UNUSED(a);
    ARG_UNUSED(b);
    ARG_UNUSED(c);

    gpio_port_value_t v0 = 0, v1 = 0;

    (void)gpio_port_get_raw(port0, &v0);
    if (port1) {
        (void)gpio_port_get_raw(port1, &v1);
    }

    uint32_t prev0 = (uint32_t)v0, prev1 = (uint32_t)v1;

    atomic_set(&sweep_live, 1);

    while (true) {
        k_sleep(K_MSEC(SAMPLE_MS));

        if (gpio_port_get_raw(port0, &v0) == 0) {
            const uint32_t now = (uint32_t)v0;
            count_changes((now ^ prev0) & P0_MASK, counts0, P0_PINS);
            prev0 = now;
        }

        if (port1 && gpio_port_get_raw(port1, &v1) == 0) {
            const uint32_t now = (uint32_t)v1;
            count_changes((now ^ prev1) & P1_MASK, counts1, P1_PINS);
            prev1 = now;
        }
    }
}

K_THREAD_STACK_DEFINE(sweep_stack, 768);
static struct k_thread sweep_tcb;

static int probe_init(void) {
    port0 = DEVICE_DT_GET(DT_NODELABEL(gpio0));
    port1 = DEVICE_DT_GET(DT_NODELABEL(gpio1));

    if (!device_is_ready(port0)) {
        LOG_ERR("gpio0 not ready; sweep inactive");
        port0 = NULL;
        return 0;
    }
    if (!device_is_ready(port1)) {
        LOG_WRN("gpio1 not ready; sweeping port 0 only");
        port1 = NULL;
    }

    arm_port(port0, P0_ARM_MASK, P0_PINS, "P0");
    if (port1) {
        arm_port(port1, P1_MASK, P1_PINS, "P1");
    }

    k_thread_create(&sweep_tcb, sweep_stack, K_THREAD_STACK_SIZEOF(sweep_stack), sweep_thread,
                    NULL, NULL, NULL, K_LOWEST_APPLICATION_THREAD_PRIO, 0, K_NO_WAIT);
    k_thread_name_set(&sweep_tcb, "int sweep");
    return 0;
}

SYS_INIT(probe_init, APPLICATION, CONFIG_APPLICATION_INIT_PRIORITY);

#if DT_HAS_COMPAT_STATUS_OKAY(DT_DRV_COMPAT)

struct int_probe_config {
    uint8_t tap_ms;
};

#define USAGE_1 HID_USAGE_KEY_KEYBOARD_1_AND_EXCLAMATION
#define USAGE_0 HID_USAGE_KEY_KEYBOARD_0_AND_RIGHT_PARENTHESIS
#define USAGE_A HID_USAGE_KEY_KEYBOARD_A
#define USAGE_SPACE HID_USAGE_KEY_KEYBOARD_SPACEBAR

static uint32_t encode(uint16_t usage) { return ZMK_HID_USAGE(HID_USAGE_KEY, usage); }
static uint32_t digit_usage(uint8_t d) {
    return d == 0 ? encode(USAGE_0) : encode(USAGE_1 + d - 1);
}
static uint32_t letter_usage(char l) { return encode(USAGE_A + (l - 'a')); }

static int queue_tap(const struct zmk_behavior_binding_event *event, uint32_t keycode,
                     uint8_t tap_ms) {
    struct zmk_behavior_binding binding = {.behavior_dev = "key_press", .param1 = keycode};
    int err = zmk_behavior_queue_add(event, binding, true, tap_ms);

    if (err < 0) {
        return err;
    }
    return zmk_behavior_queue_add(event, binding, false, tap_ms);
}

static int queue_number(const struct zmk_behavior_binding_event *event, uint32_t v, uint8_t tap) {
    uint32_t div = 1;

    while (v / div >= 10) {
        div *= 10;
    }
    while (div > 0) {
        int err = queue_tap(event, digit_usage((v / div) % 10), tap);

        if (err < 0) {
            return err;
        }
        div /= 10;
    }
    return 0;
}

static int queue_word(const struct zmk_behavior_binding_event *event, const char *w, uint8_t tap) {
    for (const char *c = w; *c; c++) {
        int err = (*c == ' ') ? queue_tap(event, encode(USAGE_SPACE), tap)
                              : queue_tap(event, letter_usage(*c), tap);
        if (err < 0) {
            return err;
        }
    }
    return 0;
}

/*
 * Report the three busiest pins and nothing else. The behaviour queue holds 64
 * entries and every character costs two, so a full listing would be truncated
 * mid-number and unreadable. Three is enough: if the INT line is reachable at
 * all, it is the only thing moving.
 *
 *   int none            nothing moved anywhere
 *   int p15e42 q3e7     P0.15 changed 42 times, P1.03 seven times
 */
static int on_keymap_binding_pressed(struct zmk_behavior_binding *binding,
                                     struct zmk_behavior_binding_event event) {
    const struct device *dev = zmk_behavior_get_binding(binding->behavior_dev);
    const uint8_t tap = ((const struct int_probe_config *)dev->config)->tap_ms;

    if (port0 == NULL || atomic_get(&sweep_live) == 0) {
        (void)queue_word(&event, "int dead", tap);
        return ZMK_BEHAVIOR_OPAQUE;
    }

    /*
     * f  ISR firings -- zero means the interrupt never reaches the CPU
     * g  the LOGICAL level the driver reads, via gpio_pin_get_dt()
     * w  the RAW physical level, read here independently
     * s  transitions this module's own 1 ms sweep has counted on the pin
     *
     * The pair g and w is the question. The line is active low, so an idle
     * line is raw 1 and should read logical 0. g1 w1 together means the
     * ACTIVE_LOW inversion is not being applied and the driver believes an
     * idle line is asserted -- which would explain everything. g1 w0 means
     * the pin really is held low and the fault is elsewhere.
     *
     * s is the cross-check: an independent measurement path on the same pin.
     * A healthy line transitions as keys are pressed, so s should climb.
     */
    const int raw = gpio_pin_get_raw(port0, FOCUS_PIN);

    if (queue_word(&event, "f", tap) < 0 ||
        queue_number(&event, nocfree_kscan_int_fires, tap) < 0 ||
        queue_word(&event, " g", tap) < 0 ||
        queue_number(&event, nocfree_kscan_int_logical < 0 ? 9u
                                 : (uint32_t)nocfree_kscan_int_logical, tap) < 0 ||
        queue_word(&event, " w", tap) < 0 ||
        queue_number(&event, raw < 0 ? 9u : (uint32_t)raw, tap) < 0 ||
        queue_word(&event, " s", tap) < 0 ||
        queue_number(&event, counts0[FOCUS_PIN], tap) < 0) {
        LOG_WRN("Behavior queue full, line truncated");
    }
    return ZMK_BEHAVIOR_OPAQUE;
}

static int on_keymap_binding_released(struct zmk_behavior_binding *binding,
                                      struct zmk_behavior_binding_event event) {
    return ZMK_BEHAVIOR_OPAQUE;
}

static const struct behavior_driver_api behavior_int_probe_driver_api = {
    .binding_pressed = on_keymap_binding_pressed,
    .binding_released = on_keymap_binding_released,
#if IS_ENABLED(CONFIG_ZMK_BEHAVIOR_METADATA)
    .get_parameter_metadata = zmk_behavior_get_empty_param_metadata,
#endif
};

#define IP_INST(n)                                                                                 \
    static const struct int_probe_config int_probe_config_##n = {                                  \
        .tap_ms = DT_INST_PROP_OR(n, tap_ms, TAP_MS),                                              \
    };                                                                                             \
    BEHAVIOR_DT_INST_DEFINE(n, NULL, NULL, NULL, &int_probe_config_##n, POST_KERNEL,               \
                            CONFIG_KERNEL_INIT_PRIORITY_DEFAULT,                                   \
                            &behavior_int_probe_driver_api);

DT_INST_FOREACH_STATUS_OKAY(IP_INST)

#endif /* DT_HAS_COMPAT_STATUS_OKAY(DT_DRV_COMPAT) */
