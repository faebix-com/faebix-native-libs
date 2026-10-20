# Copyright 2026 faebix
# SPDX-License-Identifier: Apache-2.0
#
# Links the staged static libraries of one ABI into a shared library.
# STAGE_DIR is the folder scripts/build-android.sh fills (include/ and lib/).

cmake_minimum_required(VERSION 3.15)
project(linkcheck LANGUAGES C CXX)

if(NOT STAGE_DIR)
  message(FATAL_ERROR "Set STAGE_DIR to a staged ABI folder.")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(linkcheck SHARED linkcheck.cc)
target_include_directories(linkcheck PRIVATE ${STAGE_DIR}/include ${STAGE_DIR}/include/piex)
target_compile_options(linkcheck PRIVATE -fvisibility=hidden)
target_link_libraries(linkcheck PRIVATE
  ${STAGE_DIR}/lib/libpiex.a
  ${STAGE_DIR}/lib/libjpeg.a)
# Keep the symbols of the static libraries out of the export table and drop
# unused code, as an app library would.
target_link_options(linkcheck PRIVATE
  -Wl,--exclude-libs,ALL
  -Wl,--gc-sections
  -Wl,--no-undefined)
