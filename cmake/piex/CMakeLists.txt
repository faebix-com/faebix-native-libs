# Copyright 2026 faebix
# SPDX-License-Identifier: Apache-2.0
#
# CMake build for piex. Upstream ships only a gyp file (third_party/piex/piex.gyp);
# this file builds the same sources into one static library. The piex sources
# themselves are not changed.

cmake_minimum_required(VERSION 3.15)
project(piex LANGUAGES CXX)

if(NOT PIEX_SOURCE_DIR)
  message(FATAL_ERROR "Set PIEX_SOURCE_DIR to the piex source tree.")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(piex STATIC
  ${PIEX_SOURCE_DIR}/src/piex.cc
  ${PIEX_SOURCE_DIR}/src/piex_cr3.cc
  ${PIEX_SOURCE_DIR}/src/tiff_parser.cc
  ${PIEX_SOURCE_DIR}/src/binary_parse/cached_paged_byte_array.cc
  ${PIEX_SOURCE_DIR}/src/binary_parse/range_checked_byte_ptr.cc
  ${PIEX_SOURCE_DIR}/src/image_type_recognition/image_type_recognition_lite.cc
  ${PIEX_SOURCE_DIR}/src/tiff_directory/tiff_directory.cc
)
# The headers include each other as "src/...", relative to the source root.
target_include_directories(piex PUBLIC ${PIEX_SOURCE_DIR})
target_compile_options(piex PRIVATE -Wsign-compare -Wunused-parameter)

install(TARGETS piex ARCHIVE DESTINATION lib)
install(DIRECTORY ${PIEX_SOURCE_DIR}/src/
  DESTINATION include/piex/src
  FILES_MATCHING PATTERN "*.h")
