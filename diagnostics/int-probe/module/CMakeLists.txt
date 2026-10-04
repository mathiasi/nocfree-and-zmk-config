# SPDX-License-Identifier: MIT

if(CONFIG_NOCFREE_INT_PROBE)
  zephyr_library()
  zephyr_library_sources(src/int_probe.c)
  # zmk/behavior.h and friends live in ZMK's application include directory,
  # which ZMK adds to its own target as PRIVATE.
  zephyr_library_include_directories(${APPLICATION_SOURCE_DIR}/include)
endif()
