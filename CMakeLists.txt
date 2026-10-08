cmake_minimum_required(VERSION 3.24)

# ---------------------------------------------------------------------------
# env.json - the only machine-specific file in the repository
#
# It carries the CUDA toolkit root and the GPU's compute capability, plus the
# MSVC environment, the Windows SDK UCRT include directory and CMake's location.
# Reading it means a new machine only has to refresh that one file;
# scripts/sync-env.ps1 writes it from detection. The compute capability used to
# be pinned in CMakePresets.json and the CUDA paths in a .clangd file - both are
# gone, so nothing else needs editing per machine.
#
# This runs before project() on purpose: see the note on the cache entry below.
# ---------------------------------------------------------------------------
set(CUDALAB_CUDA_ARCH "120")
set(CUDALAB_CUDA_ROOT "")
set(CUDALAB_ENV_FILE "${CMAKE_CURRENT_SOURCE_DIR}/env.json")

if(EXISTS "${CUDALAB_ENV_FILE}")
    file(READ "${CUDALAB_ENV_FILE}" cudalab_env_json)

    string(JSON cudalab_arch_value ERROR_VARIABLE cudalab_arch_error
        GET "${cudalab_env_json}" cuda arch)
    if(NOT cudalab_arch_error AND cudalab_arch_value)
        set(CUDALAB_CUDA_ARCH "${cudalab_arch_value}")
    endif()

    string(JSON cudalab_root_value ERROR_VARIABLE cudalab_root_error
        GET "${cudalab_env_json}" cuda root)
    if(NOT cudalab_root_error AND cudalab_root_value AND EXISTS "${cudalab_root_value}")
        set(CUDALAB_CUDA_ROOT "${cudalab_root_value}")
    endif()
endif()

# This has to be set BEFORE project(). Enabling the CUDA language installs its
# own default for this cache entry, so a later `if(NOT DEFINED ...)` never fires
# and silently builds for the wrong architecture. Setting a cache entry does not
# overwrite an existing one, so an explicit -DCMAKE_CUDA_ARCHITECTURES=... on the
# command line still wins.
set(CMAKE_CUDA_ARCHITECTURES "${CUDALAB_CUDA_ARCH}" CACHE STRING "CUDA architectures to build for")

project(cudalab
    VERSION 1.0.0
    DESCRIPTION "CUDA lab - one executable target per demo"
    LANGUAGES CXX CUDA)

if(CUDALAB_CUDA_ROOT)
    set(CUDAToolkit_ROOT "${CUDALAB_CUDA_ROOT}")
    message(STATUS "cudalab: env.json -> CUDA arch ${CUDALAB_CUDA_ARCH}, toolkit ${CUDALAB_CUDA_ROOT}")
else()
    message(STATUS "cudalab: env.json missing or incomplete, using CUDA arch ${CUDALAB_CUDA_ARCH} (run scripts/sync-env.ps1)")
endif()

# Provides the imported CUDA::cudart target used below. The CUDA language
# support alone does not define it.
find_package(CUDAToolkit REQUIRED)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CUDA_STANDARD 17)
set(CMAKE_CUDA_STANDARD_REQUIRED ON)

# Emit compile_commands.json for Ninja/Makefile builds so clangd and other
# tooling can see exactly how each file is compiled.
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Debug CACHE STRING "Build type" FORCE)
endif()


# ---------------------------------------------------------------------------
# Compile settings shared by the shared library and every demo
# ---------------------------------------------------------------------------
function(cudalab_configure_target target has_cuda)
    target_compile_options(${target} PRIVATE
        # CUDA 13 headers contain non-ASCII bytes; without /utf-8 MSVC reports
        # C4819 on a CJK code page and the console fills with warnings.
        $<$<COMPILE_LANGUAGE:CXX>:/utf-8>
        $<$<COMPILE_LANGUAGE:CUDA>:-Xcompiler=/utf-8>
        # Keep line information so a profiler can map SASS back to source. Only
        # for non-Debug builds: -G already implies line info and ptxas rejects
        # both.
        $<$<AND:$<COMPILE_LANGUAGE:CUDA>,$<NOT:$<CONFIG:Debug>>>:-lineinfo>
        # Device-side debug information in Debug builds only.
        $<$<AND:$<COMPILE_LANGUAGE:CUDA>,$<CONFIG:Debug>>:-G>
        $<$<AND:$<COMPILE_LANGUAGE:CUDA>,$<CONFIG:Debug>>:-g>
        $<$<AND:$<COMPILE_LANGUAGE:CUDA>,$<CONFIG:Debug>>:-Xcompiler=/Zi>
        $<$<AND:$<COMPILE_LANGUAGE:CXX>,$<CONFIG:Debug>>:/Zi>)

    set_target_properties(${target} PROPERTIES
        MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")

    # A target without any .cu file is plain C++; it must not pull in the CUDA
    # runtime.
    if(has_cuda)
        target_link_libraries(${target} PRIVATE CUDA::cudart)
        set_target_properties(${target} PROPERTIES CUDA_RUNTIME_LIBRARY Static)
    endif()
endfunction()

# ---------------------------------------------------------------------------
# Shared code
#
#   src/common/*.cpp,*.cu   ->  static library cudalab_common
#
# Demos link this library, and because src/ is one of its PUBLIC include
# directories they reach the headers as "common/random.h".
# ---------------------------------------------------------------------------
set(CUDALAB_COMMON_DIR "${CMAKE_CURRENT_SOURCE_DIR}/src/common")

file(GLOB common_sources CONFIGURE_DEPENDS
    "${CUDALAB_COMMON_DIR}/*.cpp"
    "${CUDALAB_COMMON_DIR}/*.cxx"
    "${CUDALAB_COMMON_DIR}/*.cc"
    "${CUDALAB_COMMON_DIR}/*.cu")

if(common_sources)
    set(common_has_cuda FALSE)
    foreach(source IN LISTS common_sources)
        if(source MATCHES "\\.cu$")
            set(common_has_cuda TRUE)
        endif()
    endforeach()

    add_library(cudalab_common STATIC ${common_sources})
    target_include_directories(cudalab_common PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src")
    cudalab_configure_target(cudalab_common ${common_has_cuda})

    if(common_has_cuda)
        message(STATUS "cudalab: shared library -> cudalab_common (${common_sources}) (CUDA)")
    else()
        message(STATUS "cudalab: shared library -> cudalab_common (${common_sources}) (C++ only)")
    endif()
else()
    message(STATUS "cudalab: no shared sources under ${CUDALAB_COMMON_DIR}")
endif()

# ---------------------------------------------------------------------------
# Demo layout
#
#   src/demos/<demo_name>/       ->  executable target <demo_name>
#
# Every subdirectory of src/demos is one self-contained demo and becomes one
# executable target named after the directory. Sources are all the .cu/.cpp
# files directly inside it (headers are picked up through the include path);
# adding a demo means adding a directory, not editing this file.
# ---------------------------------------------------------------------------
set(CUDALAB_DEMOS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/src/demos")

# Optional subset: -DCUDALAB_DEMOS="demo_add_one;demo_bitonic_sort"
set(CUDALAB_DEMOS "" CACHE STRING
    "Semicolon-separated demos to build; empty builds every demo under src/demos")

# --- Discover demos --------------------------------------------------------
file(GLOB demo_entries CONFIGURE_DEPENDS
    RELATIVE "${CUDALAB_DEMOS_DIR}"
    "${CUDALAB_DEMOS_DIR}/*")

set(demo_names "")
foreach(entry IN LISTS demo_entries)
    if(IS_DIRECTORY "${CUDALAB_DEMOS_DIR}/${entry}")
        list(APPEND demo_names "${entry}")
    endif()
endforeach()
list(SORT demo_names)

if(CUDALAB_DEMOS)
    set(selected_demos "")
    foreach(wanted IN LISTS CUDALAB_DEMOS)
        if(wanted IN_LIST demo_names)
            list(APPEND selected_demos "${wanted}")
        else()
            message(WARNING
                "cudalab: CUDALAB_DEMOS requests '${wanted}', which is not a directory under ${CUDALAB_DEMOS_DIR}")
        endif()
    endforeach()
    set(demo_names "${selected_demos}")
endif()

# --- One executable target per demo ----------------------------------------
set(demo_count 0)

foreach(demo IN LISTS demo_names)
    set(demo_dir "${CUDALAB_DEMOS_DIR}/${demo}")

    file(GLOB demo_sources CONFIGURE_DEPENDS
        "${demo_dir}/*.cu"
        "${demo_dir}/*.cpp"
        "${demo_dir}/*.cxx"
        "${demo_dir}/*.cc")

    if(NOT demo_sources)
        # Happens while a demo directory exists but is still empty; skipping
        # keeps a work-in-progress directory from breaking the configure step.
        message(STATUS "cudalab: skipping '${demo}' - no .cu/.cpp sources yet")
        continue()
    endif()

    add_executable(${demo} ${demo_sources})

    # The demo's own directory holds its headers, so `#include "add_one.h"`
    # resolves without any extra setup.
    target_include_directories(${demo} PRIVATE "${demo_dir}")

    # Shared headers, if the project ever grows any.
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/include")
        target_include_directories(${demo} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/include")
    endif()

    # Shared code, and with it the src/ include directory.
    if(TARGET cudalab_common)
        target_link_libraries(${demo} PRIVATE cudalab_common)
    endif()

    set(demo_has_cuda FALSE)
    foreach(source IN LISTS demo_sources)
        if(source MATCHES "\\.cu$")
            set(demo_has_cuda TRUE)
        endif()
    endforeach()

    cudalab_configure_target(${demo} ${demo_has_cuda})

    if(demo_has_cuda)
        message(STATUS "cudalab: demo '${demo}' -> target ${demo} (CUDA)")
    else()
        message(STATUS "cudalab: demo '${demo}' -> target ${demo} (C++ only)")
    endif()

    math(EXPR demo_count "${demo_count} + 1")
endforeach()

message(STATUS "cudalab: ${demo_count} demo target(s) configured from ${CUDALAB_DEMOS_DIR}")
