cmake_minimum_required(VERSION 3.22)

project(duchamp_fp_compat LANGUAGES C CXX)

add_library(duchamp_fp_compat SHARED
    duchamp_fp_compat.cpp
)

set_target_properties(duchamp_fp_compat PROPERTIES
    CXX_STANDARD 20
    CXX_STANDARD_REQUIRED ON
)

target_link_libraries(duchamp_fp_compat
    binder_ndk
    log
    dl
)

# Runs once at boot; keeps native custom-icon storage owned by its real app UID.
add_executable(duchamp_fod_icon_prepare duchamp_fod_icon_prepare.c)
target_compile_options(duchamp_fod_icon_prepare PRIVATE -Wall -Wextra -Werror)
target_link_options(duchamp_fod_icon_prepare PRIVATE -Wl,-z,relro,-z,now)

target_link_libraries(duchamp_fod_icon_prepare log)
