# SPDX-License-Identifier: MIT

if(CONFIG_NOCFREE_BLE_PROFILE_NAME)
  zephyr_library()
  zephyr_library_sources(src/ble_profile_name.c)
  # zmk/ble.h and the event headers live in ZMK's application include
  # directory, which ZMK adds to its own target as PRIVATE. Modules only
  # inherit app/module/include, so add it back.
  zephyr_library_include_directories(${APPLICATION_SOURCE_DIR}/include)
endif()
